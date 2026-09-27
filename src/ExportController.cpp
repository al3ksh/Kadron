#include "ExportController.h"
#include "MediaTools.h"

#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSettings>
#include <QUuid>
#include <QtConcurrent>
#include <QtMath>
#include <QtGlobal>

ExportController::ExportController(QObject *parent)
    : QObject(parent), m_ffmpeg(ffmpegExecutable()), m_ffprobe(ffprobeExecutable())
{
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &ExportController::readProgress);
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        m_errorBuffer += m_process.readAllStandardError();
        if (m_errorBuffer.size() > 4096)
            m_errorBuffer = m_errorBuffer.right(4096);
    });
    connect(&m_process, &QProcess::finished, this, &ExportController::finish);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            fail(QStringLiteral("Could not start FFmpeg. Check KADRON_FFMPEG or your PATH."));
    });
    const auto saved = QSettings().value(QStringLiteral("export/encoder")).toString();
    if (!saved.isEmpty())
        m_encoder = saved;
}

QString ExportController::encoder() const { return m_encoder; }
QStringList ExportController::hardwareEncoders() const { return m_hardwareEncoders; }
bool ExportController::detectingEncoders() const { return m_detecting; }
bool ExportController::encodersChecked() const { return m_checked; }
QString ExportController::encoderUsed() const { return encoderLabel(m_activeEncoder) + (m_fellBack ? QStringLiteral(" (GPU failed)") : QString()); }

void ExportController::setEncoder(const QString &encoder)
{
    static const QStringList known{"auto", "cpu", "nvenc", "qsv", "amf"};
    if (!known.contains(encoder) || encoder == m_encoder)
        return;
    m_encoder = encoder;
    QSettings().setValue(QStringLiteral("export/encoder"), encoder);
    emit encoderChanged();
}

QString ExportController::encoderLabel(const QString &encoder)
{
    if (encoder == "nvenc") return QStringLiteral("NVIDIA NVENC");
    if (encoder == "qsv") return QStringLiteral("Intel Quick Sync");
    if (encoder == "amf") return QStringLiteral("AMD AMF");
    return QStringLiteral("CPU (x264)");
}

QStringList ExportController::videoCodecArgs(const QString &encoder, bool fast)
{
    // Quality targets roughly match x264 CRF 20.
    if (encoder == "nvenc")
        return {"-c:v", "h264_nvenc", "-preset", fast ? "p4" : "p6", "-rc", "vbr", "-cq", "21", "-b:v", "0", "-pix_fmt", "yuv420p"};
    if (encoder == "qsv")
        return {"-c:v", "h264_qsv", "-preset", fast ? "faster" : "medium", "-global_quality", "21", "-pix_fmt", "nv12"};
    if (encoder == "amf")
        return {"-c:v", "h264_amf", "-quality", fast ? "speed" : "balanced", "-rc", "cqp", "-qp_i", "20", "-qp_p", "22", "-pix_fmt", "yuv420p"};
    return {"-c:v", "libx264", "-preset", fast ? "fast" : "medium", "-crf", "20"};
}

QStringList ExportController::probeHardwareEncoders(const QString &ffmpeg)
{
    QStringList found;
    if (ffmpeg.isEmpty())
        return found;
    // Listing an encoder only means FFmpeg was built with it; a real encode
    // proves the driver and GPU are there too.
    for (const auto &id : {QStringLiteral("nvenc"), QStringLiteral("qsv"), QStringLiteral("amf")}) {
        QProcess probe;
        QStringList args{"-hide_banner", "-nostdin", "-loglevel", "error",
                         "-f", "lavfi", "-i", "color=c=black:s=320x240:r=30:d=0.2"};
        args << videoCodecArgs(id, true) << "-f" << "null" << "-";
        probe.start(ffmpeg, args);
        if (!probe.waitForFinished(10000)) {
            probe.kill();
            probe.waitForFinished(1000);
            continue;
        }
        if (probe.exitStatus() == QProcess::NormalExit && probe.exitCode() == 0)
            found << id;
    }
    return found;
}

void ExportController::detectEncoders()
{
    if (m_detecting)
        return;
    if (m_ffmpeg.isEmpty() || qEnvironmentVariableIsSet("KADRON_NO_GPU")) {
        m_checked = true;
        emit encoderChanged();
        return;
    }
    m_detecting = true;
    emit encoderChanged();
    auto *watcher = new QFutureWatcher<QStringList>(this);
    connect(watcher, &QFutureWatcher<QStringList>::finished, this, [this, watcher] {
        m_hardwareEncoders = watcher->result();
        m_detecting = false;
        m_checked = true;
        watcher->deleteLater();
        emit encoderChanged();
    });
    watcher->setFuture(QtConcurrent::run(&ExportController::probeHardwareEncoders, m_ffmpeg));
}

QString ExportController::resolvedEncoder() const
{
    if (m_encoder == "cpu")
        return QStringLiteral("cpu");
    if (m_encoder != "auto")
        return m_hardwareEncoders.contains(m_encoder) ? m_encoder : QStringLiteral("cpu");
    return m_hardwareEncoders.isEmpty() ? QStringLiteral("cpu") : m_hardwareEncoders.first();
}

// A GPU encoder that fails mid-export (driver reset, unsupported input) is
// retried once on the CPU instead of failing the export.
bool ExportController::fallBackToCpu()
{
    if (m_activeEncoder == "cpu" || m_cancelled)
        return false;
    m_activeEncoder = QStringLiteral("cpu");
    m_fellBack = true;
    m_errorBuffer.clear();
    m_progressBuffer.clear();
    return true;
}

QSize ExportController::canvasFor(int width, int height)
{
    if (width <= 0 || height <= 0)
        return {1280, 720};
    const auto ratio = qMin(1.0, qMin(1920.0 / qMax(width, height), 1080.0 / qMin(width, height)));
    return {qMax(2, qRound(width * ratio / 2) * 2), qMax(2, qRound(height * ratio / 2) * 2)};
}

QString ExportController::mixFilter(const QVector<qint64> &lengthsMs, int crossfadeMs, int musicInput,
                                     double musicVolume, bool duck)
{
    const auto seconds = [](qint64 milliseconds) { return QString::number(milliseconds / 1000.0, 'f', 3); };
    QStringList parts;
    QString audio = QStringLiteral("[0:a]");
    qint64 total = 0;
    for (const auto length : lengthsMs)
        total += length;
    const auto count = lengthsMs.size();
    if (crossfadeMs > 0 && count > 1) {
        // Each join overlaps the clips by crossfadeMs; offsets are in the joined timeline.
        for (int i = 0; i < count; ++i)
            parts << QStringLiteral("[%1:v]settb=AVTB,fps=30,format=yuv420p[in%1]").arg(i);
        QString video = QStringLiteral("[in0]");
        qint64 joined = lengthsMs.first();
        for (int i = 1; i < count; ++i) {
            const bool last = i + 1 == count;
            const auto nextVideo = last ? QStringLiteral("[v]") : QStringLiteral("[v%1]").arg(i);
            const auto nextAudio = last ? (musicInput < 0 ? QStringLiteral("[a]") : QStringLiteral("[joined]"))
                                        : QStringLiteral("[a%1]").arg(i);
            // Eased rather than linear: the blend starts and settles gently.
            // The sound crossfades at equal power, with no dip in the middle.
            parts << QStringLiteral("%1[in%2]xfade=transition=custom:expr='st(0,P*P*(3-2*P));A*ld(0)+B*(1-ld(0))'"
                                    ":duration=%3:offset=%4%5")
                         .arg(video).arg(i).arg(seconds(crossfadeMs), seconds(joined - crossfadeMs), nextVideo);
            parts << QStringLiteral("%1[%2:a]acrossfade=d=%3:c1=qsin:c2=qsin%4").arg(audio).arg(i).arg(seconds(crossfadeMs), nextAudio);
            video = nextVideo;
            audio = nextAudio;
            joined += lengthsMs.at(i) - crossfadeMs;
        }
        total = joined;
    }
    if (musicInput >= 0) {
        // Looped music cut to the video, eased in and faded out over the last seconds.
        const auto fadeOut = qMin<qint64>(2000, total / 3);
        parts << QStringLiteral("[%1:a]atrim=duration=%2,asetpts=PTS-STARTPTS,aformat=sample_rates=48000:channel_layouts=stereo,"
                                "volume=%3,afade=t=in:d=0.3,afade=t=out:st=%4:d=%5:curve=hsin[music]")
                     .arg(musicInput).arg(seconds(total), QString::number(musicVolume, 'f', 3),
                                          seconds(total - fadeOut), seconds(fadeOut));
        if (duck) {
            // The clips' own sound pushes the music down while it plays.
            parts << QStringLiteral("%1asplit=2[voice][key]").arg(audio);
            parts << QStringLiteral("[music][key]sidechaincompress=threshold=0.02:ratio=8:attack=20:release=400[ducked]");
            parts << QStringLiteral("[voice][ducked]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.97[a]");
        } else {
            parts << QStringLiteral("%1[music]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.97[a]").arg(audio);
        }
    }
    return parts.join(';');
}

bool ExportController::available() const { return !m_ffmpeg.isEmpty(); }
bool ExportController::busy() const { return m_busy; }
int ExportController::progress() const { return m_progress; }
QString ExportController::stage() const { return m_stage; }
QString ExportController::errorText() const { return m_errorText; }
QUrl ExportController::outputUrl() const { return m_outputUrl; }

bool ExportController::start(const QUrl &source, const QUrl &destination, qint64 inMs, qint64 outMs)
{
    if (m_busy)
        return false;
    m_errorText.clear();
    m_outputUrl = QUrl();

    if (!available()) {
        fail(QStringLiteral("FFmpeg is not available. Set KADRON_FFMPEG or add it to PATH."));
        return false;
    }
    if (!source.isLocalFile() || !QFileInfo(source.toLocalFile()).isFile()
        || !destination.isLocalFile() || outMs <= inMs || inMs < 0) {
        fail(QStringLiteral("Choose a source, a time range, and a local output file."));
        return false;
    }

    const QFileInfo sourceInfo(source.toLocalFile());
    const QFileInfo outputInfo(destination.toLocalFile());
    if (sourceInfo.absoluteFilePath() == outputInfo.absoluteFilePath()) {
        fail(QStringLiteral("Export to a different file than the source."));
        return false;
    }
    if (outputInfo.exists()) {
        fail(QStringLiteral("The output file already exists. Choose a new name."));
        return false;
    }

    m_destinationPath = outputInfo.absoluteFilePath();
    m_partialPath = outputInfo.absolutePath() + "/." + outputInfo.completeBaseName()
        + "." + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".part.mp4";
    m_rangeMs = outMs - inMs;
    m_progress = 0;
    m_stage = QStringLiteral("Encoding");
    m_cancelled = false;
    m_progressBuffer.clear();
    m_errorBuffer.clear();
    m_busy = true;
    m_phase = Phase::Single;
    m_activeEncoder = resolvedEncoder();
    m_fellBack = false;
    m_singleSource = sourceInfo.absoluteFilePath();
    m_singleInMs = inMs;
    launchSingle();
    return true;
}

void ExportController::launchSingle()
{
    const auto seconds = [](qint64 milliseconds) {
        return QString::number(milliseconds / 1000.0, 'f', 3);
    };
    QStringList args{
        "-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1",
        "-ss", seconds(m_singleInMs), "-i", m_singleSource,
        "-t", seconds(m_rangeMs),
        "-map", "0:v:0?", "-map", "0:a:0?"
    };
    args << videoCodecArgs(m_activeEncoder, false)
         << "-c:a" << "aac" << "-b:a" << "192k" << "-movflags" << "+faststart"
         << "-y" << m_partialPath;
    m_process.setProgram(m_ffmpeg);
    m_process.setArguments(args);
    emit changed();
    m_process.start();
}

bool ExportController::startSequence(const QVariantList &clips, const QUrl &destination, const QVariantMap &options)
{
    if (m_busy)
        return false;
    m_errorText.clear();
    m_outputUrl = QUrl();
    if (m_ffmpeg.isEmpty() || m_ffprobe.isEmpty()) {
        fail(QStringLiteral("FFmpeg and FFprobe are required for sequence export."));
        return false;
    }
    if (clips.isEmpty() || clips.size() > 1000 || !destination.isLocalFile()
        || QFileInfo(destination.toLocalFile()).suffix().toLower() != "mp4") {
        fail(QStringLiteral("Choose at least one clip and an MP4 output file."));
        return false;
    }
    const QFileInfo outputInfo(destination.toLocalFile());
    if (outputInfo.exists() || !outputInfo.dir().exists()) {
        fail(QStringLiteral("Choose a new output file in an existing folder."));
        return false;
    }

    QVector<Segment> segments;
    qint64 totalMs = 0;
    for (const auto &entry : clips) {
        const auto clip = entry.toMap();
        const auto source = clip.value("url").toUrl();
        const QFileInfo sourceInfo(source.toLocalFile());
        const auto in = clip.value("inMs").toLongLong();
        const auto out = clip.value("outMs").toLongLong();
        const auto duration = clip.value("durationMs").toLongLong();
        if (!source.isLocalFile() || !sourceInfo.isFile() || in < 0 || out - in < 100
            || out > duration || sourceInfo.absoluteFilePath() == outputInfo.absoluteFilePath()) {
            fail(QStringLiteral("A sequence clip is missing or has an invalid time range."));
            return false;
        }
        Segment segment{sourceInfo.absoluteFilePath(), in, out};
        segment.volume = clip.value("muted").toBool() ? 0.0 : qBound(0.0, clip.value("volume", 1.0).toDouble(), 2.0);
        segments.append(segment);
        totalMs += out - in;
    }
    const auto musicUrl = options.value("musicUrl").toUrl();
    const auto musicPath = musicUrl.isLocalFile() ? QFileInfo(musicUrl.toLocalFile()).absoluteFilePath() : QString();
    if (!musicUrl.isEmpty() && (musicPath.isEmpty() || !QFileInfo(musicPath).isFile())) {
        fail(QStringLiteral("The music file is missing."));
        return false;
    }
    auto transition = options.value("transition", "cut").toString();
    auto transitionMs = qBound(100, options.value("transitionMs", 500).toInt(), 3000);
    if (transition == "crossfade") {
        // Every clip has to outlast the overlaps at both of its ends.
        qint64 shortest = totalMs;
        for (const auto &segment : std::as_const(segments))
            shortest = qMin(shortest, segment.outMs - segment.inMs);
        transitionMs = qMin<qint64>(transitionMs, shortest * 2 / 5);
    }
    if (segments.size() < 2 || transitionMs < 100 || (transition != "fade" && transition != "crossfade"))
        transition = QStringLiteral("cut");
    auto directory = std::make_unique<QTemporaryDir>(outputInfo.absolutePath() + "/.kadron-sequence-XXXXXX");
    if (!directory->isValid()) {
        fail(QStringLiteral("Could not create temporary export files beside the output."));
        return false;
    }

    m_segments = segments;
    m_sequenceDir = std::move(directory);
    m_destinationPath = outputInfo.absoluteFilePath();
    m_partialPath = outputInfo.absolutePath() + "/." + outputInfo.completeBaseName()
        + "." + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".part.mp4";
    m_rangeMs = totalMs;
    m_transition = transition;
    m_transitionMs = transitionMs;
    m_musicPath = musicPath;
    m_musicVolume = qBound(0.0, options.value("musicVolume", 0.35).toDouble(), 1.0);
    m_musicDuck = options.value("musicDuck", true).toBool();
    m_encodeShare = transition == "crossfade" ? 50 : 90;
    m_finalMs = totalMs - (transition == "crossfade" ? (segments.size() - 1) * transitionMs : 0);
    m_completedMs = 0;
    m_segmentIndex = 0;
    m_canvasWidth = 0;
    m_canvasHeight = 0;
    m_progress = 0;
    m_cancelled = false;
    m_busy = true;
    m_phase = Phase::Probe;
    m_activeEncoder = resolvedEncoder();
    m_fellBack = false;
    emit changed();
    probeNext();
    return true;
}

void ExportController::probeNext()
{
    if (m_segmentIndex >= m_segments.size()) {
        if (m_canvasWidth == 0) {
            m_canvasWidth = 1280;
            m_canvasHeight = 720;
        }
        m_segmentIndex = 0;
        encodeNext();
        return;
    }
    m_phase = Phase::Probe;
    m_stage = QStringLiteral("Inspecting clip %1/%2").arg(m_segmentIndex + 1).arg(m_segments.size());
    m_errorBuffer.clear();
    m_progressBuffer.clear();
    m_process.start(m_ffprobe, {
        "-v", "error", "-show_entries", "stream=codec_type,width,height",
        "-of", "json", m_segments[m_segmentIndex].path
    });
    emit changed();
}

QString ExportController::segmentPath(int index) const
{
    return m_sequenceDir->path() + QString("/clip_%1.mp4").arg(index, 4, 10, QChar('0'));
}

QString ExportController::joinedPath() const
{
    return m_sequenceDir->path() + QStringLiteral("/joined.mp4");
}

void ExportController::encodeNext()
{
    if (m_segmentIndex >= m_segments.size()) {
        if (m_transition == "crossfade") startFinal();
        else concatSegments();
        return;
    }
    m_phase = Phase::Encode;
    m_stage = QStringLiteral("Encoding clip %1/%2").arg(m_segmentIndex + 1).arg(m_segments.size());
    m_errorBuffer.clear();
    m_progressBuffer.clear();
    const auto &segment = m_segments[m_segmentIndex];
    const auto seconds = [](qint64 milliseconds) { return QString::number(milliseconds / 1000.0, 'f', 3); };
    QStringList args{
        "-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1",
        "-ss", seconds(segment.inMs), "-i", segment.path
    };
    if (!segment.hasVideo)
        args << "-f" << "lavfi" << "-i" << QString("color=c=black:s=%1x%2:r=30").arg(m_canvasWidth).arg(m_canvasHeight);
    else if (!segment.hasAudio)
        args << "-f" << "lavfi" << "-i" << "anullsrc=channel_layout=stereo:sample_rate=48000";
    args << "-t" << seconds(segment.outMs - segment.inMs)
         << "-map" << (segment.hasVideo ? "0:v:0" : "1:v:0")
         << "-map" << (segment.hasAudio ? "0:a:0" : "1:a:0");
    // Fade through black: half the transition out of one clip, half into the next.
    const auto lengthMs = segment.outMs - segment.inMs;
    const auto half = m_transition == "fade" ? qMin<qint64>(m_transitionMs / 2, lengthMs / 2) : 0;
    const bool fadeIn = half > 0 && m_segmentIndex > 0;
    const bool fadeOut = half > 0 && m_segmentIndex + 1 < m_segments.size();
    QString videoFades, audioFades;
    if (fadeIn || fadeOut) {
        // An eased dip (smoothstep), only on the frames that fade: register 0
        // holds the fade-in level and 1 the fade-out level.
        QStringList levels, factors, windows;
        if (fadeIn) {
            levels << QString("st(0,clip(T/%1,0,1))").arg(seconds(half));
            factors << "ld(0)*ld(0)*(3-2*ld(0))";
            windows << QString("lt(t,%1)").arg(seconds(half));
        }
        if (fadeOut) {
            levels << QString("st(1,clip((%1-T)/%2,0,1))").arg(seconds(lengthMs), seconds(half));
            factors << "ld(1)*ld(1)*(3-2*ld(1))";
            windows << QString("gte(t,%1)").arg(seconds(lengthMs - half));
        }
        const auto level = levels.join(';') + ';';
        const auto factor = factors.join('*');
        videoFades = QString(",geq=lum='%1 16+(lum(X,Y)-16)*%2':cb='%1 128+(cb(X,Y)-128)*%2':cr='%1 128+(cr(X,Y)-128)*%2'"
                             ":enable='%3'").arg(level, factor, windows.join('+'));
        if (fadeIn)
            audioFades += QString(",afade=t=in:st=0:d=%1:curve=hsin").arg(seconds(half));
        if (fadeOut)
            audioFades += QString(",afade=t=out:st=%1:d=%2:curve=hsin").arg(seconds(lengthMs - half), seconds(half));
    }
    if (segment.hasVideo) {
        args << "-vf" << QString("scale=%1:%2:force_original_aspect_ratio=decrease,"
                                 "pad=%1:%2:(ow-iw)/2:(oh-ih)/2,fps=30,format=yuv420p,setsar=1")
                                 .arg(m_canvasWidth).arg(m_canvasHeight) + videoFades;
    } else {
        args << "-vf" << "format=yuv420p" + videoFades;
    }
    args << "-af" << QString("volume=%1").arg(QString::number(segment.volume, 'f', 3)) + audioFades;
    args << videoCodecArgs(m_activeEncoder, true)
         << "-r" << "30" << "-c:a" << "aac" << "-b:a" << "160k"
         << "-ar" << "48000" << "-ac" << "2" << "-shortest" << "-movflags" << "+faststart"
         << "-y" << segmentPath(m_segmentIndex);
    m_process.start(m_ffmpeg, args);
    emit changed();
}

void ExportController::concatSegments()
{
    m_phase = Phase::Concat;
    m_stage = QStringLiteral("Finalizing sequence");
    m_errorBuffer.clear();
    m_progressBuffer.clear();
    const auto listPath = m_sequenceDir->path() + "/clips.ffconcat";
    QSaveFile list(listPath);
    if (!list.open(QIODevice::WriteOnly)) {
        fail(QStringLiteral("Could not prepare the sequence for final export."));
        return;
    }
    for (int index = 0; index < m_segments.size(); ++index) {
        auto path = segmentPath(index);
        path = QDir::fromNativeSeparators(path).replace("'", "'\\''");
        const auto line = QString("file '%1'\n").arg(path).toUtf8();
        if (list.write(line) != line.size()) {
            list.cancelWriting();
            fail(QStringLiteral("Could not prepare the sequence for final export."));
            return;
        }
    }
    if (!list.commit()) {
        fail(QStringLiteral("Could not prepare the sequence for final export."));
        return;
    }
    m_progress = qMax(m_progress, 90);
    emit changed();
    m_process.start(m_ffmpeg, {
        "-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1",
        "-safe", "0", "-f", "concat", "-i", listPath,
        "-c", "copy", "-movflags", "+faststart", "-y", m_musicPath.isEmpty() ? m_partialPath : joinedPath()
    });
}

// Crossfades the encoded clips and/or lays the music under them.
void ExportController::startFinal()
{
    m_phase = Phase::Final;
    m_stage = m_musicPath.isEmpty() ? QStringLiteral("Joining clips") : QStringLiteral("Mixing music");
    m_errorBuffer.clear();
    m_progressBuffer.clear();
    const bool crossfade = m_transition == "crossfade";
    QVector<qint64> lengths;
    for (const auto &segment : std::as_const(m_segments))
        lengths << segment.outMs - segment.inMs;
    QStringList args{"-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1"};
    if (crossfade) {
        for (int index = 0; index < m_segments.size(); ++index)
            args << "-i" << segmentPath(index);
    } else {
        args << "-i" << joinedPath();
        lengths = {m_finalMs};
    }
    const int musicInput = m_musicPath.isEmpty() ? -1 : (crossfade ? m_segments.size() : 1);
    if (musicInput >= 0)
        args << "-stream_loop" << "-1" << "-i" << m_musicPath;
    args << "-filter_complex" << mixFilter(lengths, crossfade ? m_transitionMs : 0, musicInput, m_musicVolume, m_musicDuck);
    if (crossfade)
        args << "-map" << "[v]" << videoCodecArgs(m_activeEncoder, false) << "-r" << "30";
    else
        args << "-map" << "0:v:0" << "-c:v" << "copy";
    args << "-map" << "[a]" << "-c:a" << "aac" << "-b:a" << "192k" << "-ar" << "48000"
         << "-t" << QString::number(m_finalMs / 1000.0, 'f', 3)
         << "-movflags" << "+faststart" << "-y" << m_partialPath;
    m_process.start(m_ffmpeg, args);
    emit changed();
}

void ExportController::clearSequence()
{
    m_sequenceDir.reset();
    m_segments.clear();
    m_segmentIndex = 0;
    m_completedMs = 0;
    m_phase = Phase::Idle;
}

void ExportController::cancel()
{
    if (!m_busy)
        return;
    m_cancelled = true;
    m_stage = QStringLiteral("Cancelling");
    emit changed();
    m_process.kill();
}

void ExportController::resetResult()
{
    if (m_busy)
        return;
    m_outputUrl = QUrl();
    m_errorText.clear();
    m_stage.clear();
    m_progress = 0;
    emit changed();
}

void ExportController::readProgress()
{
    if (m_phase == Phase::Probe)
        return;
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
        if (valid && m_rangeMs > 0) {
            int next = 0;
            if (m_phase == Phase::Encode) {
                const auto segmentMs = m_segments[m_segmentIndex].outMs - m_segments[m_segmentIndex].inMs;
                next = qBound(0, static_cast<int>((m_completedMs + qMin(segmentMs, microseconds / 1000))
                                                  * m_encodeShare / m_rangeMs), m_encodeShare);
            } else if (m_phase == Phase::Final) {
                next = qBound(m_encodeShare, m_encodeShare + static_cast<int>(microseconds / 1000 * (99 - m_encodeShare)
                                                                               / qMax<qint64>(1, m_finalMs)), 99);
            } else if (m_phase == Phase::Concat) {
                next = qBound(90, 90 + static_cast<int>(microseconds / (m_rangeMs * 100)), 99);
            } else {
                next = qBound(0, static_cast<int>(microseconds / (m_rangeMs * 10)), 99);
            }
            if (next > m_progress) {
                m_progress = next;
                emit changed();
            }
        }
    }
}

void ExportController::discardPartial()
{
    if (!m_partialPath.isEmpty())
        QFile::remove(m_partialPath);
    m_partialPath.clear();
}

void ExportController::fail(const QString &message)
{
    discardPartial();
    clearSequence();
    m_busy = false;
    m_stage = QStringLiteral("Failed");
    m_errorText = message;
    emit changed();
}

void ExportController::finish(int exitCode, QProcess::ExitStatus exitStatus)
{
    if (!m_busy)
        return;
    readProgress();
    if (m_cancelled) {
        discardPartial();
        clearSequence();
        m_busy = false;
        m_stage = QStringLiteral("Cancelled");
        emit changed();
        return;
    }
    if (m_phase == Phase::Probe) {
        if (exitStatus != QProcess::NormalExit || exitCode != 0) {
            fail(QStringLiteral("Could not inspect clip %1: %2")
                 .arg(m_segmentIndex + 1).arg(QString::fromUtf8(m_errorBuffer).trimmed().right(300)));
            return;
        }
        const auto streams = QJsonDocument::fromJson(m_process.readAllStandardOutput()).object().value("streams").toArray();
        auto &segment = m_segments[m_segmentIndex];
        for (const auto &entry : streams) {
            const auto stream = entry.toObject();
            const auto codecType = stream.value("codec_type").toString();
            if (codecType == "audio") segment.hasAudio = true;
            if (codecType == "video") {
                segment.hasVideo = true;
                const auto width = stream.value("width").toInt();
                const auto height = stream.value("height").toInt();
                if (m_canvasWidth == 0 && width > 0 && height > 0) {
                    const auto canvas = canvasFor(width, height);
                    m_canvasWidth = canvas.width();
                    m_canvasHeight = canvas.height();
                }
            }
        }
        if (!segment.hasVideo && !segment.hasAudio) {
            fail(QStringLiteral("Clip %1 has no playable video or audio stream.").arg(m_segmentIndex + 1));
            return;
        }
        ++m_segmentIndex;
        probeNext();
        return;
    }
    if (exitStatus != QProcess::NormalExit || exitCode != 0
        || !(m_phase == Phase::Encode
             ? QFileInfo(segmentPath(m_segmentIndex)).size() > 0
             : m_phase == Phase::Concat && !m_musicPath.isEmpty() ? QFileInfo(joinedPath()).size() > 0
             : QFileInfo(m_partialPath).isFile() && QFileInfo(m_partialPath).size() > 0)) {
        const bool reencodes = m_phase == Phase::Single || m_phase == Phase::Encode
            || (m_phase == Phase::Final && m_transition == "crossfade");
        if (reencodes && fallBackToCpu()) {
            if (m_phase == Phase::Single) {
                QFile::remove(m_partialPath);
                m_progress = 0;
                launchSingle();
            } else if (m_phase == Phase::Final) {
                startFinal();
            } else {
                encodeNext();
            }
            return;
        }
        const auto details = QString::fromUtf8(m_errorBuffer).trimmed();
        fail(details.isEmpty() ? QStringLiteral("Export failed. Check the source file and codec support.")
                               : details.right(500));
        return;
    }
    if (m_phase == Phase::Encode) {
        m_completedMs += m_segments[m_segmentIndex].outMs - m_segments[m_segmentIndex].inMs;
        m_progress = qMax(m_progress, static_cast<int>(m_completedMs * m_encodeShare / m_rangeMs));
        ++m_segmentIndex;
        emit changed();
        encodeNext();
        return;
    }
    if (m_phase == Phase::Concat && !m_musicPath.isEmpty()) {
        startFinal();
        return;
    }
    if (!QFile::rename(m_partialPath, m_destinationPath)) {
        fail(QStringLiteral("Encoding finished, but the output could not be placed at the chosen path."));
        return;
    }
    m_partialPath.clear();
    clearSequence();
    m_outputUrl = QUrl::fromLocalFile(m_destinationPath);
    m_progress = 100;
    m_busy = false;
    m_stage = QStringLiteral("Ready");
    emit changed();
}
