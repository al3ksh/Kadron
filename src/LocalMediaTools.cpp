#include "LocalMediaTools.h"
#include "MediaTools.h"

#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QUuid>
#include <QtMath>

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
                                   int bitrate, bool normalize, double startSec, double endSec)
{
    if (busy())
        return false;
    const auto selected = format.toLower();
    if (!QStringList{"mp3", "wav", "flac", "opus"}.contains(selected)
        || QFileInfo(destination.toLocalFile()).suffix().toLower() != selected
        || startSec < 0 || (endSec > 0 && endSec <= startSec)) {
        fail(QStringLiteral("Choose MP3, WAV, FLAC or Opus and a valid time range."));
        return false;
    }
    if (!begin(source, destination, Operation::Audio))
        return false;
    m_format = selected;
    m_bitrate = qBound(64, bitrate, 320);
    m_normalize = normalize;
    m_startSec = startSec;
    m_endSec = endSec;
    return true;
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

void LocalMediaTools::probe()
{
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
        if (m_normalize)
            args << "-af" << "loudnorm=I=-14:TP=-1.5:LRA=11";
        if (m_format == "mp3") args << "-c:a" << "libmp3lame" << "-b:a" << QString::number(m_bitrate) + "k";
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
