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

QStringList ExportController::videoCodecArgs(const QString &encoder, bool fast, int videoKbps)
{
    if (videoKbps > 0) {
        const auto rate = QString::number(videoKbps) + "k";
        const auto buffer = QString::number(videoKbps * 2) + "k";
        if (encoder == "nvenc")
            return {"-c:v", "h264_nvenc", "-preset", fast ? "p4" : "p6", "-rc", "vbr", "-b:v", rate, "-maxrate", rate, "-bufsize", buffer, "-pix_fmt", "yuv420p"};
        if (encoder == "qsv")
            return {"-c:v", "h264_qsv", "-preset", fast ? "faster" : "medium", "-b:v", rate, "-maxrate", rate, "-bufsize", buffer, "-pix_fmt", "nv12"};
        if (encoder == "amf")
            return {"-c:v", "h264_amf", "-quality", fast ? "speed" : "balanced", "-rc", "vbr_peak", "-b:v", rate, "-maxrate", rate, "-pix_fmt", "yuv420p"};
        return {"-c:v", "libx264", "-preset", fast ? "fast" : "medium", "-b:v", rate, "-maxrate", rate, "-bufsize", buffer};
    }
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

QSize ExportController::canvasFor(int width, int height, int maxLong, int maxShort)
{
    if (width <= 0 || height <= 0)
        return {1280, 720};
    const auto ratio = qMin(1.0, qMin(double(maxLong) / qMax(width, height), double(maxShort) / qMin(width, height)));
    return {qMax(2, qRound(width * ratio / 2) * 2), qMax(2, qRound(height * ratio / 2) * 2)};
}

int ExportController::discordVideoKbps(qint64 durationMs)
{
    // 9.5 MB leaves room for the container under Discord's 10 MB.
    const auto seconds = qMax(1.0, durationMs / 1000.0);
    return qBound(100, qFloor(9.5 * 8000 / seconds) - 96, 8000);
}

ExportController::OutputPlan ExportController::outputPlan(const QString &preset, QSize source, double sourceFps, qint64 durationMs)
{
    const auto fps = [sourceFps](int cap) { return sourceFps >= 1 ? qBound(1, qRound(sourceFps), cap) : qMin(30, cap); };
    OutputPlan plan;
    if (preset == "1080p60") {
        plan.canvas = canvasFor(source.width(), source.height());
        plan.fps = fps(60);
    } else if (preset == "discord") {
        plan.canvas = canvasFor(source.width(), source.height(), 1280, 720);
        plan.fps = fps(30);
        plan.videoKbps = discordVideoKbps(durationMs);
        plan.audioKbps = 96;
    } else if (preset == "vertical") {
        plan.canvas = {1080, 1920};
        plan.fill = true;
        plan.fps = fps(60);
    } else {
        plan.canvas = canvasFor(source.width(), source.height(), 3840, 2160);
        plan.fps = fps(120);
    }
    return plan;
}

double ExportController::frameRate(const QString &rational)
{
    const auto numerator = rational.section('/', 0, 0).toDouble();
    const auto denominator = rational.contains('/') ? rational.section('/', 1, 1).toDouble() : 1.0;
    return denominator > 0 && numerator > 0 ? numerator / denominator : 0.0;
}

QString ExportController::mixFilter(const QVector<qint64> &lengthsMs, int crossfadeMs, int firstAudioInput,
                                     const QVector<AudioBed> &beds, bool duck, int fps)
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
            parts << QStringLiteral("[%1:v]settb=AVTB,fps=%2,format=yuv420p[in%1]").arg(i).arg(fps);
        QString video = QStringLiteral("[in0]");
        qint64 joined = lengthsMs.first();
        for (int i = 1; i < count; ++i) {
            const bool last = i + 1 == count;
            const auto nextVideo = last ? QStringLiteral("[v]") : QStringLiteral("[v%1]").arg(i);
            const auto nextAudio = last ? (beds.isEmpty() ? QStringLiteral("[a]") : QStringLiteral("[joined]"))
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
    if (!beds.isEmpty()) {
        // Each bed is cut to its range, de-clicked at both ends and delayed to
        // its place; together they make one track as long as the video.
        QString inputs;
        bool crossesEnd = false;
        for (int j = 0; j < beds.size(); ++j) {
            const auto &bed = beds.at(j);
            const auto length = bed.outMs - bed.inMs;
            // At least a few ms at each end so a cut never clicks.
            const auto fadeIn = qBound<qint64>(20, bed.fadeInMs, length / 2);
            const auto fadeOut = qBound<qint64>(20, bed.fadeOutMs, length / 2);
            parts << QStringLiteral("[%1:a]atrim=start=%2:end=%3,asetpts=PTS-STARTPTS,aformat=sample_rates=48000:channel_layouts=stereo,"
                                    "volume=%4,afade=t=in:d=%5:curve=hsin,afade=t=out:st=%6:d=%7:curve=hsin,adelay=delays=%8:all=1[bed%9]")
                         .arg(firstAudioInput + j)
                         .arg(seconds(bed.inMs), seconds(bed.outMs), QString::number(bed.volume, 'f', 3), seconds(fadeIn),
                              seconds(qMax<qint64>(0, length - fadeOut)), seconds(fadeOut), QString::number(bed.startMs))
                         .arg(j);
            inputs += QStringLiteral("[bed%1]").arg(j);
            crossesEnd = crossesEnd || bed.startMs + length > total;
        }
        if (beds.size() > 1)
            parts << QStringLiteral("%1amix=inputs=%2:duration=longest:normalize=0[bus]").arg(inputs).arg(beds.size());
        const auto bus = beds.size() > 1 ? QStringLiteral("[bus]") : inputs;
        // Sound still playing when the video ends fades out instead of cutting off.
        const auto fadeOut = qMin<qint64>(1500, total / 3);
        parts << QStringLiteral("%1apad,atrim=duration=%2%3[music]")
                     .arg(bus, seconds(total), crossesEnd ? QStringLiteral(",afade=t=out:st=%1:d=%2:curve=hsin")
                                                                .arg(seconds(total - fadeOut), seconds(fadeOut))
                                                          : QString());
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

bool ExportController::start(const QUrl &source, const QUrl &destination, qint64 inMs, qint64 outMs,
                             const QVariantMap &options)
{
    if (m_busy)
        return false;
    const auto preset = options.value("preset", "source").toString();
    const bool copy = options.value("copy").toBool();
    // Anything beyond a plain re-encode goes through the sequence pipeline.
    if (!copy && (preset != "source" || options.value("loudnorm").toBool())) {
        return startSequence({QVariantMap{{"url", source}, {"inMs", inMs}, {"outMs", outMs},
                                          {"durationMs", outMs}}}, destination, options);
    }
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
    m_copy = copy;
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
    if (m_copy) {
        // Starts at the keyframe before inMs; nothing is re-encoded.
        args << "-c" << "copy" << "-avoid_negative_ts" << "make_zero";
    } else {
        args << videoCodecArgs(m_activeEncoder, false) << "-c:a" << "aac" << "-b:a" << "192k";
    }
    args << "-movflags" << "+faststart" << "-y" << m_partialPath;
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
        segment.speed = qBound(0.25, clip.value("speed", 1.0).toDouble(), 4.0);
        segments.append(segment);
        totalMs += segment.lengthMs();
    }
    auto transition = options.value("transition", "cut").toString();
    auto transitionMs = qBound(100, options.value("transitionMs", 500).toInt(), 3000);
    if (transition == "crossfade") {
        // Every clip has to outlast the overlaps at both of its ends.
        qint64 shortest = totalMs;
        for (const auto &segment : std::as_const(segments))
            shortest = qMin(shortest, segment.lengthMs());
        transitionMs = qMin<qint64>(transitionMs, shortest * 2 / 5);
    }
    if (segments.size() < 2 || transitionMs < 100 || (transition != "fade" && transition != "crossfade"))
        transition = QStringLiteral("cut");
    // Audio track positions are in sequence time; crossfades pull every clip
    // after a join earlier by the overlap, and the track moves with them.
    const auto finalMs = totalMs - (transition == "crossfade" ? (segments.size() - 1) * transitionMs : 0);
    QStringList audioPaths;
    QVector<AudioBed> audioBeds;
    for (const auto &entry : options.value("audio").toList()) {
        const auto item = entry.toMap();
        const auto url = item.value("url").toUrl();
        const QFileInfo info(url.toLocalFile());
        if (!url.isLocalFile() || !info.isFile()) {
            fail(QStringLiteral("An audio track file is missing: %1").arg(url.toLocalFile()));
            return false;
        }
        AudioBed bed{qMax<qint64>(0, item.value("startMs").toLongLong()), qMax<qint64>(0, item.value("inMs").toLongLong()),
                     item.value("outMs").toLongLong(), qBound(0.0, item.value("volume", 1.0).toDouble(), 2.0),
                     qMax<qint64>(0, item.value("fadeInMs").toLongLong()), qMax<qint64>(0, item.value("fadeOutMs").toLongLong())};
        if (bed.outMs - bed.inMs < 20)
            continue;
        if (transition == "crossfade") {
            qint64 clipStart = 0;
            int joins = 0;
            for (int i = 1; i < segments.size(); ++i) {
                clipStart += segments.at(i - 1).lengthMs();
                if (bed.startMs >= clipStart) joins = i;
            }
            bed.startMs = qMax<qint64>(0, bed.startMs - joins * transitionMs);
        }
        if (bed.startMs >= finalMs - 20)
            continue;
        audioPaths << info.absoluteFilePath();
        audioBeds << bed;
    }
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
    m_audioPaths = audioPaths;
    m_audioBeds = audioBeds;
    m_musicDuck = options.value("musicDuck", true).toBool();
    m_encodeShare = transition == "crossfade" ? 50 : 90;
    m_finalMs = finalMs;
    m_completedMs = 0;
    m_segmentIndex = 0;
    m_canvasWidth = 0;
    m_canvasHeight = 0;
    m_sourceFps = 0;
    m_preset = options.value("preset", "source").toString();
    m_loudnorm = options.value("loudnorm").toBool();
    m_plan = {};
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
        m_plan = outputPlan(m_preset, QSize(m_canvasWidth, m_canvasHeight), m_sourceFps, m_finalMs);
        m_canvasWidth = m_plan.canvas.width();
        m_canvasHeight = m_plan.canvas.height();
        m_segmentIndex = 0;
        encodeNext();
        return;
    }
    m_phase = Phase::Probe;
    m_stage = QStringLiteral("Inspecting clip %1/%2").arg(m_segmentIndex + 1).arg(m_segments.size());
    m_errorBuffer.clear();
    m_progressBuffer.clear();
    m_process.start(m_ffprobe, {
        "-v", "error", "-show_entries", "stream=codec_type,width,height,avg_frame_rate,r_frame_rate:stream_side_data=rotation",
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
        args << "-f" << "lavfi" << "-i" << QString("color=c=black:s=%1x%2:r=%3").arg(m_canvasWidth).arg(m_canvasHeight).arg(m_plan.fps);
    else if (!segment.hasAudio)
        args << "-f" << "lavfi" << "-i" << "anullsrc=channel_layout=stereo:sample_rate=48000";
    args << "-t" << seconds(segment.lengthMs())
         << "-map" << (segment.hasVideo ? "0:v:0" : "1:v:0")
         << "-map" << (segment.hasAudio ? "0:a:0" : "1:a:0");
    // Fade through black: half the transition out of one clip, half into the next.
    const auto lengthMs = segment.lengthMs();
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
    const bool retimed = !qFuzzyCompare(segment.speed, 1.0);
    const auto speed = QString::number(segment.speed, 'f', 4);
    if (segment.hasVideo) {
        // Fill crops the frame to the canvas; otherwise it is letterboxed.
        const auto fit = m_plan.fill ? QString("scale=%1:%2:force_original_aspect_ratio=increase,crop=%1:%2")
                                     : QString("scale=%1:%2:force_original_aspect_ratio=decrease,pad=%1:%2:(ow-iw)/2:(oh-ih)/2");
        args << "-vf" << (retimed ? QString("setpts=PTS/%1,").arg(speed) : QString())
                             + fit.arg(m_canvasWidth).arg(m_canvasHeight)
                             + QString(",fps=%1,format=yuv420p,setsar=1").arg(m_plan.fps) + videoFades;
    } else {
        args << "-vf" << "format=yuv420p" + videoFades;
    }
    QString audio = retimed && segment.hasAudio ? QString("atempo=%1,").arg(speed) : QString();
    if (m_loudnorm && segment.hasAudio)
        audio += QStringLiteral("loudnorm=I=-16:TP=-1.5:LRA=11,");
    args << "-af" << audio + QString("volume=%1").arg(QString::number(segment.volume, 'f', 3)) + audioFades;
    args << videoCodecArgs(m_activeEncoder, true, m_plan.videoKbps)
         << "-r" << QString::number(m_plan.fps) << "-c:a" << "aac" << "-b:a" << QString::number(qMin(160, m_plan.audioKbps)) + "k"
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
        "-c", "copy", "-movflags", "+faststart", "-y", m_audioBeds.isEmpty() ? m_partialPath : joinedPath()
    });
}

// Crossfades the encoded clips and/or lays the music under them.
void ExportController::startFinal()
{
    m_phase = Phase::Final;
    m_stage = m_audioBeds.isEmpty() ? QStringLiteral("Joining clips") : QStringLiteral("Mixing the audio track");
    m_errorBuffer.clear();
    m_progressBuffer.clear();
    const bool crossfade = m_transition == "crossfade";
    QVector<qint64> lengths;
    for (const auto &segment : std::as_const(m_segments))
        lengths << segment.lengthMs();
    QStringList args{"-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1"};
    if (crossfade) {
        for (int index = 0; index < m_segments.size(); ++index)
            args << "-i" << segmentPath(index);
    } else {
        args << "-i" << joinedPath();
        lengths = {m_finalMs};
    }
    const int firstAudioInput = crossfade ? m_segments.size() : 1;
    for (const auto &path : std::as_const(m_audioPaths))
        args << "-i" << path;
    args << "-filter_complex" << mixFilter(lengths, crossfade ? m_transitionMs : 0, firstAudioInput, m_audioBeds, m_musicDuck, m_plan.fps);
    if (crossfade)
        args << "-map" << "[v]" << videoCodecArgs(m_activeEncoder, false, m_plan.videoKbps) << "-r" << QString::number(m_plan.fps);
    else
        args << "-map" << "0:v:0" << "-c:v" << "copy";
    args << "-map" << "[a]" << "-c:a" << "aac" << "-b:a" << QString::number(m_plan.audioKbps) + "k" << "-ar" << "48000"
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
                const auto segmentMs = m_segments[m_segmentIndex].lengthMs();
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
                auto width = stream.value("width").toInt();
                auto height = stream.value("height").toInt();
                // Phone videos are often stored sideways with a rotation tag.
                for (const auto &data : stream.value("side_data_list").toArray())
                    if (qAbs(data.toObject().value("rotation").toInt()) == 90) std::swap(width, height);
                if (m_canvasWidth == 0 && width > 0 && height > 0) {
                    m_canvasWidth = width;
                    m_canvasHeight = height;
                    m_sourceFps = frameRate(stream.value("avg_frame_rate").toString());
                    if (m_sourceFps < 1)
                        m_sourceFps = frameRate(stream.value("r_frame_rate").toString());
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
             : m_phase == Phase::Concat && !m_audioBeds.isEmpty() ? QFileInfo(joinedPath()).size() > 0
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
        m_completedMs += m_segments[m_segmentIndex].lengthMs();
        m_progress = qMax(m_progress, static_cast<int>(m_completedMs * m_encodeShare / m_rangeMs));
        ++m_segmentIndex;
        emit changed();
        encodeNext();
        return;
    }
    if (m_phase == Phase::Concat && !m_audioBeds.isEmpty()) {
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
