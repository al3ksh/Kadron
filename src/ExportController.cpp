#include "ExportController.h"
#include "MediaTools.h"

#include <QFile>
#include <QFileInfo>
#include <QUuid>
#include <QtGlobal>

ExportController::ExportController(QObject *parent) : QObject(parent), m_ffmpeg(ffmpegExecutable())
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

    const auto seconds = [](qint64 milliseconds) {
        return QString::number(milliseconds / 1000.0, 'f', 3);
    };
    m_process.setProgram(m_ffmpeg);
    m_process.setArguments({
        "-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1",
        "-ss", seconds(inMs), "-i", sourceInfo.absoluteFilePath(),
        "-t", seconds(m_rangeMs),
        "-map", "0:v:0?", "-map", "0:a:0?",
        "-c:v", "libx264", "-preset", "medium", "-crf", "20",
        "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
        "-y", m_partialPath
    });
    emit changed();
    m_process.start();
    return true;
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

void ExportController::readProgress()
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
        if (valid && m_rangeMs > 0) {
            const auto next = qBound(0, static_cast<int>(microseconds / (m_rangeMs * 10)), 99);
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
        m_busy = false;
        m_stage = QStringLiteral("Cancelled");
        emit changed();
        return;
    }
    if (exitStatus != QProcess::NormalExit || exitCode != 0
        || !QFileInfo(m_partialPath).isFile() || QFileInfo(m_partialPath).size() == 0) {
        const auto details = QString::fromUtf8(m_errorBuffer).trimmed();
        fail(details.isEmpty() ? QStringLiteral("Export failed. Check the source file and codec support.")
                               : details.right(500));
        return;
    }
    if (!QFile::rename(m_partialPath, m_destinationPath)) {
        fail(QStringLiteral("Encoding finished, but the output could not be placed at the chosen path."));
        return;
    }
    m_partialPath.clear();
    m_outputUrl = QUrl::fromLocalFile(m_destinationPath);
    m_progress = 100;
    m_busy = false;
    m_stage = QStringLiteral("Ready");
    emit changed();
}
