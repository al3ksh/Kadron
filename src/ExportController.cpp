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

bool ExportController::startSequence(const QVariantList &clips, const QUrl &destination)
{
    if (m_busy)
        return false;
    m_errorText.clear();
    m_outputUrl = QUrl();
    if (m_ffmpeg.isEmpty() || m_ffprobe.isEmpty()) {
        fail(QStringLiteral("FFmpeg and FFprobe are required for sequence export."));
        return false;
    }
    if (clips.size() < 2 || clips.size() > 1000 || !destination.isLocalFile()
        || QFileInfo(destination.toLocalFile()).suffix().toLower() != "mp4") {
        fail(QStringLiteral("Choose at least two clips and an MP4 output file."));
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
        segments.append({sourceInfo.absoluteFilePath(), in, out});
        totalMs += out - in;
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

void ExportController::encodeNext()
{
    if (m_segmentIndex >= m_segments.size()) {
        concatSegments();
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
    if (segment.hasVideo) {
        args << "-vf" << QString("scale=%1:%2:force_original_aspect_ratio=decrease,"
                                 "pad=%1:%2:(ow-iw)/2:(oh-ih)/2,fps=30,format=yuv420p,setsar=1")
                                 .arg(m_canvasWidth).arg(m_canvasHeight);
    } else {
        args << "-vf" << "format=yuv420p";
    }
    args << videoCodecArgs(m_activeEncoder, true)
         << "-r" << "30" << "-c:a" << "aac" << "-b:a" << "160k"
         << "-ar" << "48000" << "-ac" << "2" << "-shortest" << "-movflags" << "+faststart"
         << "-y" << (m_sequenceDir->path() + QString("/clip_%1.mp4").arg(m_segmentIndex, 4, 10, QChar('0')));
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
        auto path = m_sequenceDir->path() + QString("/clip_%1.mp4").arg(index, 4, 10, QChar('0'));
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
        "-c", "copy", "-movflags", "+faststart", "-y", m_partialPath
    });
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
                                                  * 90 / m_rangeMs), 90);
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
                    const auto ratio = qMin(1.0, qMin(1920.0 / width, 1080.0 / height));
                    m_canvasWidth = qMax(2, qRound(width * ratio / 2) * 2);
                    m_canvasHeight = qMax(2, qRound(height * ratio / 2) * 2);
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
             ? QFileInfo(m_sequenceDir->path() + QString("/clip_%1.mp4").arg(m_segmentIndex, 4, 10, QChar('0'))).size() > 0
             : QFileInfo(m_partialPath).isFile() && QFileInfo(m_partialPath).size() > 0)) {
        if ((m_phase == Phase::Single || m_phase == Phase::Encode) && fallBackToCpu()) {
            if (m_phase == Phase::Single) {
                QFile::remove(m_partialPath);
                m_progress = 0;
                launchSingle();
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
        m_progress = qMax(m_progress, static_cast<int>(m_completedMs * 90 / m_rangeMs));
        ++m_segmentIndex;
        emit changed();
        encodeNext();
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
