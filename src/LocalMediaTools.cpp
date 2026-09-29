#include "LocalMediaTools.h"
#include "MediaTools.h"

#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUuid>
#include <QtMath>

#include <limits>

LocalMediaTools::LocalMediaTools(QObject *parent)
    : QObject(parent), m_ffmpeg(ffmpegExecutable()), m_ffprobe(ffprobeExecutable())
{
    connect(&m_process, &QProcess::readyReadStandardOutput, this, [this] {
        if (m_phase == Phase::Encode)
            readProgress();
    });
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        m_errorBuffer += m_process.readAllStandardError();
        if (m_errorBuffer.size() > 4096)
            m_errorBuffer = m_errorBuffer.right(4096);
    });
    connect(&m_process, &QProcess::finished, this, &LocalMediaTools::onFinished);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart && m_operation != Operation::None)
            fail(QStringLiteral("Could not start FFmpeg or FFprobe. Check their installation."));
    });
}

LocalMediaTools::~LocalMediaTools()
{
    if (m_process.state() != QProcess::NotRunning) {
        m_process.kill();
        m_process.waitForFinished(5000);
    }
    discardPartial();
}

bool LocalMediaTools::available() const { return !m_ffmpeg.isEmpty() && !m_ffprobe.isEmpty(); }
bool LocalMediaTools::busy() const { return m_operation != Operation::None; }
QString LocalMediaTools::stage() const { return m_stage; }
QString LocalMediaTools::errorText() const { return m_errorText; }
int LocalMediaTools::progress() const { return m_progress; }
QUrl LocalMediaTools::outputUrl() const { return m_outputUrl; }
qint64 LocalMediaTools::outputBytes() const { return m_outputBytes; }

bool LocalMediaTools::begin(const QUrl &source, const QUrl &destination, Operation operation)
{
    if (busy())
        return false;
    m_errorText.clear();
    m_outputUrl = QUrl();
    m_outputBytes = 0;
    m_targetBytes = 0;
    if (!available()) {
        fail(QStringLiteral("FFmpeg and FFprobe are required. Set KADRON_FFMPEG and KADRON_FFPROBE or add them to PATH."));
        return false;
    }
    if (!source.isLocalFile() || !destination.isLocalFile() || !QFileInfo(source.toLocalFile()).isFile()) {
        fail(QStringLiteral("Choose a local source and output file."));
        return false;
    }
    const QFileInfo input(source.toLocalFile());
    const QFileInfo output(destination.toLocalFile());
    if (input.absoluteFilePath() == output.absoluteFilePath()) {
        fail(QStringLiteral("Output must be a different file from the source."));
        return false;
    }
    if (output.exists()) {
        fail(QStringLiteral("Output already exists. Choose a new name."));
        return false;
    }
    if (!output.dir().exists()) {
        fail(QStringLiteral("The output folder does not exist."));
        return false;
    }

    m_sourcePath = input.absoluteFilePath();
    m_outputPath = output.absoluteFilePath();
    m_partialPath = output.absolutePath() + "/." + output.completeBaseName() + "."
        + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".part." + output.suffix();
    m_operation = operation;
    m_phase = Phase::Probe;
    m_durationMs = 0;
    m_attempt = 0;
    m_progress = 0;
    m_cancelled = false;
    m_errorBuffer.clear();
    m_progressBuffer.clear();
    m_stage = QStringLiteral("Reading media");
    emit changed();
    probe();
    return true;
}

bool LocalMediaTools::convertAudio(const QUrl &source, const QUrl &destination, const QString &format,
                                   int bitrate, bool normalize, double startSec, double endSec,
                                   const QVariantMap &options)
{
    if (busy())
        return false;
    const auto selected = format.toLower();
    if (!QStringList{"mp3", "m4a", "wav", "flac", "opus"}.contains(selected)
        || QFileInfo(destination.toLocalFile()).suffix().toLower() != selected
        || startSec < 0 || (endSec > 0 && endSec <= startSec)) {
        fail(QStringLiteral("Choose MP3, AAC, WAV, FLAC or Opus and a valid time range."));
        return false;
    }
    if (!begin(source, destination, Operation::Audio))
        return false;
    m_format = selected;
    m_bitrate = qBound(64, bitrate, 320);
    m_normalize = normalize;
    m_lufs = qBound(-30.0, options.value("lufs", -14).toDouble(), -5.0);
    m_fadeInSec = qMax(0.0, options.value("fadeIn").toDouble());
    m_fadeOutSec = qMax(0.0, options.value("fadeOut").toDouble());
    m_mono = options.value("mono").toBool();
    m_startSec = startSec;
    m_endSec = endSec;
    return true;
}

qint64 LocalMediaTools::fileBytes(const QUrl &url)
{
    const QFileInfo info(url.toLocalFile());
    return url.isLocalFile() && info.isFile() ? info.size() : 0;
}

bool LocalMediaTools::compress(const QUrl &source, const QUrl &destination, const QString &format,
                               int quality, double targetMB, int maxWidth, bool stripAudio)
{
    if (busy())
        return false;
    const auto selected = format.toLower();
    const auto sourceExt = QFileInfo(source.toLocalFile()).suffix().toLower();
    const bool image = QStringList{"jpg", "jpeg", "png", "webp", "bmp", "tif", "tiff"}.contains(sourceExt);
    const bool video = QStringList{"mp4", "mov", "mkv", "webm", "avi", "m4v", "gif"}.contains(sourceExt);
    if ((!image && !video) || targetMB < 0 || maxWidth < 0
        || QFileInfo(destination.toLocalFile()).suffix().toLower() != selected
        || (image && !QStringList{"jpg", "png", "webp", "gif"}.contains(selected))
        || (video && !QStringList{"mp4", "webm", "gif"}.contains(selected))) {
        fail(QStringLiteral("Choose a supported image or video and a compatible output format."));
        return false;
    }
    const auto operation = selected == "gif" ? Operation::Gif : image ? Operation::Image : Operation::Video;
    if (!begin(source, destination, operation))
        return false;
    m_format = selected;
    m_quality = qBound(1, quality, 100);
    m_targetBytes = qRound64(targetMB * 1024 * 1024);
    m_maxWidth = selected == "gif" && maxWidth == 0 ? 480 : maxWidth;
    m_stripAudio = stripAudio;
    m_startSec = 0;
    m_endSec = 0;
    m_fps = 10;
    m_gifDurationSec = 0;
    return true;
}

bool LocalMediaTools::createGif(const QUrl &source, const QUrl &destination, double startSec,
                                double durationSec, int fps, int width, double targetMB)
{
    if (busy())
        return false;
    if (QFileInfo(destination.toLocalFile()).suffix().toLower() != "gif" || startSec < 0
        || durationSec <= 0 || fps < 5 || fps > 30 || width < 120 || width > 1080 || targetMB < 0) {
        fail(QStringLiteral("Choose a GIF output and valid duration, FPS, width, and size limit."));
        return false;
    }
    if (!begin(source, destination, Operation::Gif))
        return false;
    m_format = "gif";
    m_startSec = startSec;
    m_gifDurationSec = durationSec;
    m_fps = fps;
    m_maxWidth = width;
    m_targetBytes = qRound64(targetMB * 1024 * 1024);
    return true;
}

bool LocalMediaTools::reframe(const QUrl &source, const QUrl &destination, const QVariantMap &options)
{
    if (busy())
        return false;
    const auto mode = options.value("mode").toString();
    if (QFileInfo(destination.toLocalFile()).suffix().toLower() != "mp4" || (mode != "crop" && mode != "blur" && mode != "split")
        || options.value("aspectW").toInt() <= 0 || options.value("aspectH").toInt() <= 0) {
        fail(QStringLiteral("Choose an MP4 output and a shape."));
        return false;
    }
    if (!begin(source, destination, Operation::Reframe))
        return false;
    m_format = "mp4";
    m_reframe = options;
    m_startSec = 0;
    m_endSec = 0;
    return true;
}

QSize LocalMediaTools::reframeOutput(int aspectW, int aspectH)
{
    const auto even = [](double value) { return qMax(2, qRound(value / 2) * 2); };
    if (aspectW <= 0 || aspectH <= 0)
        return {};
    return aspectW <= aspectH ? QSize(1080, even(1080.0 * aspectH / aspectW))
                              : QSize(even(1080.0 * aspectW / aspectH), 1080);
}

QSize LocalMediaTools::reframeCrop(QSize source, int aspectW, int aspectH, double zoom)
{
    const auto even = [](double value) { return qMax(2, int(value / 2) * 2); };
    if (source.isEmpty() || aspectW <= 0 || aspectH <= 0)
        return {};
    const double ratio = double(aspectW) / aspectH;
    zoom = qBound(1.0, zoom, 4.0);
    double width = source.width(), height = source.height();
    if (width / height > ratio)
        width = height * ratio;
    else
        height = width / ratio;
    return QSize(qMin(even(width / zoom), source.width()), qMin(even(height / zoom), source.height()));
}

QPair<int, int> LocalMediaTools::splitHeights(QSize output, double share)
{
    const int top = qBound(2, qRound(output.height() * qBound(0.2, share, 0.8) / 2) * 2, output.height() - 2);
    return { top, output.height() - top };
}

// A value that eases between keyframes (smoothstep), as an FFmpeg expression of t.
static QString glide(const QList<QPair<double, double>> &points)
{
    const auto number = [](double value) { return QString::number(value, 'f', 3); };
    if (points.isEmpty())
        return QStringLiteral("0");
    auto expression = number(points.last().second);
    for (int i = int(points.size()) - 2; i >= 0; --i) {
        const auto [t0, v0] = points.at(i);
        const auto [t1, v1] = points.at(i + 1);
        // Holding still needs no easing.
        if (qAbs(v1 - v0) < 0.5 && expression == number(v1)) {
            expression = number(v0);
            continue;
        }
        const auto u = QStringLiteral("clip((t-%1)/%2,0,1)").arg(number(t0), number(qMax(0.001, t1 - t0)));
        const auto segment = QStringLiteral("%1+(%2)*%3*%3*(3-2*%3)").arg(number(v0), number(v1 - v0), u);
        expression = QStringLiteral("if(lt(t,%1),%2,%3)").arg(number(t1), segment, expression);
    }
    return expression;
}

QVector<TextOverlay> LocalMediaTools::reframeTexts(const QVariantMap &options)
{
    QVector<TextOverlay> texts;
    for (const auto &entry : options.value("texts").toList()) {
        const auto text = TextOverlay::fromMap(entry.toMap());
        if (!text.text.trimmed().isEmpty() && text.endMs - text.startMs >= 100)
            texts << text;
    }
    return texts;
}

QString LocalMediaTools::reframeFilter(QSize source, const QVariantMap &options)
{
    auto graph = reframePicture(source, options);
    const auto texts = reframeTexts(options);
    if (texts.isEmpty() || !graph.endsWith("[v]"))
        return graph;
    // Text goes on the finished frame, sized against the output's height.
    const auto output = reframeOutput(options.value("aspectW").toInt(), options.value("aspectH").toInt());
    graph.chop(3);
    return graph + TextOverlay::filter(texts, 0, std::numeric_limits<qint64>::max() / 4, output.height()) + "[v]";
}

QString LocalMediaTools::reframePicture(QSize source, const QVariantMap &options)
{
    const int aspectW = options.value("aspectW").toInt(), aspectH = options.value("aspectH").toInt();
    const auto output = reframeOutput(aspectW, aspectH);
    const auto W = QString::number(output.width()), H = QString::number(output.height());
    if (options.value("mode").toString() == "blur") {
        // The background is blurred small, so it stays cheap at 1080p.
        const auto w4 = QString::number(output.width() / 4), h4 = QString::number(output.height() / 4);
        return QStringLiteral("[0:v]split=2[bg][fg];"
                              "[bg]scale=%3:%4:force_original_aspect_ratio=increase,crop=%3:%4,boxblur=10:2,"
                              "scale=%1:%2,eq=brightness=-0.06[b];"
                              "[fg]scale=%1:%2:force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos,setsar=1[f];"
                              "[b][f]overlay=(W-w)/2:(H-h)/2,setsar=1,format=yuv420p[v]")
            .arg(W, H, w4, h4);
    }
    if (options.value("mode").toString() == "split") {
        // Two regions of the same picture (say a webcam corner and the game),
        // each filling its band, stacked. A region a little off the band's
        // shape is filled from its centre rather than stretched.
        const auto [topH, bottomH] = splitHeights(output, options.value("share", 0.5).toDouble());
        const auto panels = options.value("panels").toList();
        QStringList chains;
        const int heights[] = { topH, bottomH };
        for (int i = 0; i < 2; ++i) {
            const auto panel = panels.value(i).toMap();
            const int width = qBound(2, qRound(panel.value("w", 1.0).toDouble() * source.width()), source.width());
            const int height = qBound(2, qRound(panel.value("h", 1.0).toDouble() * source.height()), source.height());
            const int left = qBound(0, qRound(panel.value("x", 0.0).toDouble() * source.width()), source.width() - width);
            const int top = qBound(0, qRound(panel.value("y", 0.0).toDouble() * source.height()), source.height() - height);
            chains << QStringLiteral("[p%1]crop=%2:%3:%4:%5,scale=%6:%7:force_original_aspect_ratio=increase:flags=lanczos,crop=%6:%7,setsar=1[s%1]")
                          .arg(i).arg(width).arg(height).arg(left).arg(top).arg(output.width()).arg(heights[i]);
        }
        return QStringLiteral("[0:v]split=2[p0][p1];%1;%2;[s0][s1]vstack=inputs=2,format=yuv420p[v]").arg(chains.at(0), chains.at(1));
    }
    const auto crop = reframeCrop(source, aspectW, aspectH, options.value("zoom", 1.0).toDouble());
    auto keyframes = options.value("keyframes").toList();
    std::sort(keyframes.begin(), keyframes.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("t").toDouble() < b.toMap().value("t").toDouble();
    });
    QList<QPair<double, double>> xs, ys;
    for (const auto &entry : std::as_const(keyframes)) {
        const auto key = entry.toMap();
        const double t = qMax(0.0, key.value("t").toDouble());
        const double left = key.value("x", 0.5).toDouble() * source.width() - crop.width() / 2.0;
        const double top = key.value("y", 0.5).toDouble() * source.height() - crop.height() / 2.0;
        xs << qMakePair(t, qBound(0.0, left, double(source.width() - crop.width())));
        ys << qMakePair(t, qBound(0.0, top, double(source.height() - crop.height())));
    }
    if (xs.isEmpty()) {
        xs << qMakePair(0.0, (source.width() - crop.width()) / 2.0);
        ys << qMakePair(0.0, (source.height() - crop.height()) / 2.0);
    }
    return QStringLiteral("[0:v]crop=w=%1:h=%2:x='%3':y='%4',scale=%5:%6:flags=lanczos,setsar=1,format=yuv420p[v]")
        .arg(QString::number(crop.width()), QString::number(crop.height()), glide(xs), glide(ys), W, H);
}

void LocalMediaTools::probe()
{
    if (m_operation == Operation::Reframe) {
        m_process.start(m_ffprobe, {
            "-v", "error", "-select_streams", "v:0",
            "-show_entries", "format=duration:stream=width,height:stream_side_data=rotation",
            "-of", "json", m_sourcePath
        });
        return;
    }
    m_process.start(m_ffprobe, {
        "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", m_sourcePath
    });
}

QStringList LocalMediaTools::arguments() const
{
    QStringList args{"-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1", "-y"};
    if (m_startSec > 0)
        args << "-ss" << QString::number(m_startSec, 'f', 3);
    args << "-i" << m_sourcePath;

    if (m_operation == Operation::Audio) {
        if (m_endSec > m_startSec)
            args << "-t" << QString::number(m_endSec - m_startSec, 'f', 3);
        args << "-vn";
        QStringList filters;
        if (m_normalize)
            filters << QString("loudnorm=I=%1:TP=-1.5:LRA=11").arg(m_lufs);
        if (m_fadeInSec > 0)
            filters << QString("afade=t=in:st=0:d=%1").arg(m_fadeInSec, 0, 'f', 3);
        // The fade out ends with the output, so it needs the output's length.
        const double lengthSec = m_endSec > m_startSec ? m_endSec - m_startSec : m_durationMs / 1000.0 - m_startSec;
        if (m_fadeOutSec > 0 && lengthSec > 0) {
            const double fade = qMin(m_fadeOutSec, lengthSec);
            filters << QString("afade=t=out:st=%1:d=%2").arg(lengthSec - fade, 0, 'f', 3).arg(fade, 0, 'f', 3);
        }
        if (!filters.isEmpty())
            args << "-af" << filters.join(',');
        if (m_mono)
            args << "-ac" << "1";
        if (m_format == "mp3") args << "-c:a" << "libmp3lame" << "-b:a" << QString::number(m_bitrate) + "k";
        else if (m_format == "m4a") args << "-c:a" << "aac" << "-b:a" << QString::number(m_bitrate) + "k";
        else if (m_format == "wav") args << "-c:a" << "pcm_s16le";
        else if (m_format == "flac") args << "-c:a" << "flac";
        else args << "-c:a" << "libopus" << "-b:a" << QString::number(m_bitrate) + "k";
    } else if (m_operation == Operation::Image) {
        if (m_maxWidth > 0)
            args << "-vf" << QString("scale=w='min(%1,iw)':h=-2").arg(m_maxWidth);
        args << "-frames:v" << "1" << "-an";
        if (m_format == "jpg") args << "-q:v" << QString::number(qBound(2, 31 - m_quality * 29 / 100, 31));
        else if (m_format == "png") args << "-compression_level" << "9";
        else args << "-c:v" << "libwebp" << "-quality" << QString::number(m_quality) << "-compression_level" << "6";
    } else if (m_operation == Operation::Video) {
        if (m_maxWidth > 0)
            args << "-vf" << QString("scale=w='min(%1,iw)':h=-2").arg(m_maxWidth);
        if (m_format == "webm") {
            args << "-c:v" << "libvpx-vp9" << "-deadline" << "good" << "-cpu-used" << "3";
            if (m_targetBytes > 0) args << "-b:v" << QString::number(m_videoKbps) + "k";
            else args << "-crf" << QString::number(38 - m_quality * 25 / 100) << "-b:v" << "0";
        } else {
            args << "-c:v" << "libx264" << "-preset" << "fast" << "-movflags" << "+faststart";
            if (m_targetBytes > 0)
                args << "-b:v" << QString::number(m_videoKbps) + "k" << "-maxrate" << QString::number(m_videoKbps) + "k" << "-bufsize" << QString::number(m_videoKbps * 2) + "k";
            else args << "-crf" << QString::number(34 - m_quality * 16 / 100);
        }
        if (m_stripAudio) args << "-an";
        else args << "-c:a" << (m_format == "webm" ? "libopus" : "aac") << "-b:a" << "96k";
    } else if (m_operation == Operation::Reframe) {
        args << "-filter_complex" << reframeFilter(m_sourceSize, m_reframe) << "-map" << "[v]" << "-map" << "0:a?"
             << "-c:v" << "libx264" << "-preset" << "medium" << "-crf" << "19" << "-movflags" << "+faststart"
             << "-c:a" << "aac" << "-b:a" << "192k";
    } else if (m_operation == Operation::Gif) {
        if (m_gifDurationSec > 0)
            args << "-t" << QString::number(m_gifDurationSec, 'f', 3);
        const auto filters = QString("[0:v]fps=%1,scale=%2:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=5[v]")
            .arg(m_fps).arg(m_maxWidth);
        args << "-filter_complex" << filters << "-map" << "[v]" << "-an" << "-loop" << "0";
    }
    args << m_partialPath;
    return args;
}

void LocalMediaTools::encode()
{
    ++m_attempt;
    m_phase = Phase::Encode;
    m_progress = 0;
    m_progressBuffer.clear();
    m_errorBuffer.clear();
    m_stage = m_attempt == 1 ? QStringLiteral("Encoding") : QStringLiteral("Refining size (%1/4)").arg(m_attempt);
    QFile::remove(m_partialPath);
    emit changed();
    m_process.setWorkingDirectory(QString());
    if (m_operation == Operation::Reframe) {
        const auto texts = reframeTexts(m_reframe);
        if (!texts.isEmpty()) {
            m_textDir = std::make_unique<QTemporaryDir>();
            if (!m_textDir->isValid() || !TextOverlay::writeAssets(m_textDir->path(), texts)) {
                fail(QStringLiteral("Could not prepare the text for the video."));
                return;
            }
            m_process.setWorkingDirectory(m_textDir->path());
        }
    }
    m_process.start(m_ffmpeg, arguments());
}

void LocalMediaTools::readProgress()
{
    m_progressBuffer += m_process.readAllStandardOutput();
    while (true) {
        const auto end = m_progressBuffer.indexOf('\n');
        if (end < 0)
            break;
        const auto line = m_progressBuffer.left(end).trimmed();
        m_progressBuffer.remove(0, end + 1);
        if (!line.startsWith("out_time_us=") && !line.startsWith("out_time_ms="))
            continue;
        bool valid = false;
        const auto microseconds = line.mid(line.indexOf('=') + 1).toLongLong(&valid);
        const auto workMs = m_operation == Operation::Gif && m_gifDurationSec > 0
            ? qRound64(m_gifDurationSec * 1000) : m_operation == Operation::Audio && m_endSec > m_startSec
                ? qRound64((m_endSec - m_startSec) * 1000) : m_durationMs;
        if (valid && workMs > 0) {
            const auto next = qBound(0, static_cast<int>(microseconds / (workMs * 10)), 99);
            if (next > m_progress) {
                m_progress = next;
                emit changed();
            }
        }
    }
}

void LocalMediaTools::onFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    if (m_operation == Operation::None)
        return;
    if (m_cancelled) {
        discardPartial();
        m_operation = Operation::None;
        m_phase = Phase::Idle;
        m_stage = QStringLiteral("Cancelled");
        emit changed();
        return;
    }
    if (m_phase == Phase::Probe) {
        if (exitStatus != QProcess::NormalExit || exitCode != 0) {
            fail(QStringLiteral("Could not read media metadata: %1").arg(QString::fromUtf8(m_errorBuffer).trimmed().right(300)));
            return;
        }
        bool valid = false;
        if (m_operation == Operation::Reframe) {
            const auto probe = QJsonDocument::fromJson(m_process.readAllStandardOutput()).object();
            const auto stream = probe.value("streams").toArray().first().toObject();
            m_sourceSize = QSize(stream.value("width").toInt(), stream.value("height").toInt());
            // FFmpeg turns rotated phone videos upright, so the crop works on that frame.
            for (const auto &side : stream.value("side_data_list").toArray())
                if (qAbs(side.toObject().value("rotation").toInt()) % 180 == 90)
                    m_sourceSize.transpose();
            const auto seconds = probe.value("format").toObject().value("duration").toString().toDouble(&valid);
            m_durationMs = valid && seconds > 0 ? qRound64(seconds * 1000) : 0;
            if (m_sourceSize.isEmpty()) {
                fail(QStringLiteral("This file has no video to reframe."));
                return;
            }
            encode();
            return;
        }
        const auto seconds = QString::fromUtf8(m_process.readAllStandardOutput()).trimmed().toDouble(&valid);
        m_durationMs = valid && seconds > 0 ? qRound64(seconds * 1000) : 0;
        if (m_operation == Operation::Video && m_targetBytes > 0) {
            if (m_durationMs <= 0) {
                fail(QStringLiteral("A readable video duration is required for target-size compression."));
                return;
            }
            const auto totalKbps = qMax(120, static_cast<int>(m_targetBytes * 8.0 / m_durationMs * 1000 / 1024 * 0.9));
            m_videoKbps = qMax(80, totalKbps - (m_stripAudio ? 0 : 96));
        }
        if (m_operation == Operation::Gif && m_gifDurationSec <= 0)
            m_gifDurationSec = m_durationMs / 1000.0;
        encode();
        return;
    }

    readProgress();
    const QFileInfo output(m_partialPath);
    if (exitStatus != QProcess::NormalExit || exitCode != 0 || !output.isFile() || output.size() == 0) {
        const auto details = QString::fromUtf8(m_errorBuffer).trimmed();
        if (m_operation == Operation::Audio && details.contains(QStringLiteral("does not contain any stream"))) {
            fail(QStringLiteral("This file has no sound to convert."));
            return;
        }
        fail(details.isEmpty() ? QStringLiteral("Processing failed. Check media and codec support.") : details.right(500));
        return;
    }
    if (m_targetBytes > 0 && output.size() > m_targetBytes) {
        if (m_attempt >= 4) {
            fail(QStringLiteral("Could not reach the target size without truncating the file. Choose a larger limit."));
            return;
        }
        if (m_operation == Operation::Video) {
            const auto next = qMax(80, qRound(m_videoKbps * static_cast<double>(m_targetBytes) / output.size() * 0.88));
            if (next >= m_videoKbps) {
                fail(QStringLiteral("Target size is too small for this video and audio."));
                return;
            }
            m_videoKbps = next;
        } else if (m_operation == Operation::Image) {
            if (m_quality > 15 && m_format != "png") m_quality = qMax(15, m_quality * 2 / 3);
            else m_maxWidth = m_maxWidth > 0 ? qMax(160, m_maxWidth * 3 / 4) : 1280;
        } else if (m_operation == Operation::Gif) {
            m_maxWidth = qMax(120, m_maxWidth * 3 / 4);
            m_fps = qMax(5, m_fps * 4 / 5);
        }
        encode();
        return;
    }
    if (!QFile::rename(m_partialPath, m_outputPath)) {
        fail(QStringLiteral("Processing finished, but the output could not be saved."));
        return;
    }
    m_outputBytes = QFileInfo(m_outputPath).size();
    m_outputUrl = QUrl::fromLocalFile(m_outputPath);
    m_operation = Operation::None;
    m_phase = Phase::Idle;
    m_progress = 100;
    m_stage = QStringLiteral("Ready");
    emit changed();
}

void LocalMediaTools::discardPartial()
{
    if (!m_partialPath.isEmpty())
        QFile::remove(m_partialPath);
}

void LocalMediaTools::fail(const QString &message)
{
    discardPartial();
    m_operation = Operation::None;
    m_phase = Phase::Idle;
    m_stage = QStringLiteral("Failed");
    m_errorText = message;
    emit changed();
}

void LocalMediaTools::cancel()
{
    if (!busy())
        return;
    m_cancelled = true;
    m_stage = QStringLiteral("Cancelling");
    emit changed();
    m_process.kill();
}
