#include "ThumbnailStrip.h"
#include "MediaTools.h"

#include <QDir>
#include <QFileInfo>

ThumbnailStrip::ThumbnailStrip(QObject *parent) : QObject(parent)
{
    connect(&m_process, &QProcess::finished, this, &ThumbnailStrip::complete);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_busy = false;
            emit changed();
        }
    });
}

QStringList ThumbnailStrip::frames() const { return m_frames; }
bool ThumbnailStrip::busy() const { return m_busy; }

void ThumbnailStrip::generate(const QUrl &source, qint64 durationMs)
{
    const auto sourcePath = source.toLocalFile();
    if (!source.isLocalFile() || !QFileInfo(sourcePath).isFile() || durationMs <= 0)
        return;
    if (sourcePath == m_sourcePath && durationMs == m_durationMs)
        return;

    if (m_process.state() != QProcess::NotRunning) {
        m_process.kill();
        m_process.waitForFinished(1000);
    }
    m_frames.clear();
    m_sourcePath = sourcePath;
    m_durationMs = durationMs;
    m_directory = std::make_unique<QTemporaryDir>();
    const auto executable = ffmpegExecutable();
    if (executable.isEmpty() || !m_directory->isValid()) {
        m_busy = false;
        emit changed();
        return;
    }

    const auto fps = QString::number(qMin(4.0, 12'000.0 / durationMs), 'f', 4);
    m_process.setProgram(executable);
    m_process.setArguments({
        "-hide_banner", "-nostdin", "-loglevel", "error", "-i", sourcePath,
        "-vf", "fps=" + fps + ",scale=180:-1",
        "-frames:v", "12", "-q:v", "5", "-y",
        m_directory->path() + "/frame_%03d.jpg"
    });
    m_busy = true;
    emit changed();
    m_process.start();
}

void ThumbnailStrip::complete(int exitCode, QProcess::ExitStatus status)
{
    m_busy = false;
    m_frames.clear();
    if (exitCode == 0 && status == QProcess::NormalExit && m_directory && m_directory->isValid()) {
        const QDir directory(m_directory->path());
        for (const auto &name : directory.entryList({"frame_*.jpg"}, QDir::Files, QDir::Name))
            m_frames.append(QUrl::fromLocalFile(directory.absoluteFilePath(name)).toString());
    }
    emit changed();
}
