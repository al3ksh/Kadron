#include "ThumbnailStrip.h"
#include "MediaTools.h"

#include <QFileInfo>

ThumbnailStrip::ThumbnailStrip(QObject *parent) : QObject(parent) {}

ThumbnailStrip::~ThumbnailStrip()
{
    for (auto *process : findChildren<QProcess *>()) {
        if (process->state() != QProcess::NotRunning) {
            process->kill();
            process->waitForFinished(2000);
        }
    }
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

    if (m_process && m_process->state() != QProcess::NotRunning)
        m_process->kill();
    m_process = nullptr;
    m_sourcePath = sourcePath;
    m_durationMs = durationMs;
    m_frames.clear();
    for (int i = 0; i < 12; ++i)
        m_frames.append(QString());

    m_generation = std::make_shared<Generation>();
    m_generation->directory = std::make_unique<QTemporaryDir>();
    m_generation->sourcePath = sourcePath;
    m_generation->durationMs = durationMs;
    m_busy = !ffmpegExecutable().isEmpty() && m_generation->directory->isValid();
    emit changed();
    if (m_busy)
        startNext();
}

void ThumbnailStrip::startNext()
{
    const auto generation = m_generation;
    if (!generation || generation->nextFrame >= m_frames.size()) {
        m_busy = false;
        emit changed();
        return;
    }

    const auto index = generation->nextFrame;
    const auto timeMs = generation->durationMs * index / m_frames.size();
    const auto output = generation->directory->path() + QString("/frame_%1.jpg").arg(index, 2, 10, QChar('0'));
    auto *process = new QProcess(this);
    m_process = process;
    process->setProgram(ffmpegExecutable());
    process->setArguments({
        "-hide_banner", "-nostdin", "-loglevel", "error",
        "-ss", QString::number(timeMs / 1000.0, 'f', 3),
        "-i", generation->sourcePath,
        "-frames:v", "1", "-vf", "scale=180:-1",
        "-q:v", "5", "-y", output
    });
    connect(process, &QProcess::finished, this, [this, generation, process, index, output](int code, QProcess::ExitStatus status) {
        if (m_process == process)
            m_process = nullptr;
        process->deleteLater();
        if (generation != m_generation)
            return;
        if (code == 0 && status == QProcess::NormalExit && QFileInfo(output).size() > 0) {
            m_frames[index] = QUrl::fromLocalFile(output).toString();
            emit changed();
        }
        generation->nextFrame++;
        startNext();
    });
    connect(process, &QProcess::errorOccurred, this, [this, generation, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        if (m_process == process)
            m_process = nullptr;
        process->deleteLater();
        if (generation == m_generation) {
            m_busy = false;
            emit changed();
        }
    });
    process->start();
}
