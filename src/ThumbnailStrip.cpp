#include "ThumbnailStrip.h"
#include "MediaTools.h"

#include <QDir>
#include <QFileInfo>
#include <QTimer>
#include <QtMath>

ThumbnailStrip::ThumbnailStrip(QObject *parent) : QObject(parent) {}

ThumbnailStrip::~ThumbnailStrip()
{
    m_queue.clear();
    if (m_process && m_process->state() != QProcess::NotRunning) {
        m_process->kill();
        m_process->waitForFinished(2000);
    }
}

int ThumbnailStrip::revision() const { return m_revision; }
bool ThumbnailStrip::busy() const { return m_process || !m_queue.isEmpty(); }

QStringList ThumbnailStrip::frames() const
{
    return m_entries.value(m_lastSource).frames;
}

void ThumbnailStrip::generate(const QUrl &source, qint64 durationMs)
{
    m_lastSource = source.toLocalFile();
    framesFor(source, durationMs);
    emit changed();
}

QStringList ThumbnailStrip::framesFor(const QUrl &source, qint64 durationMs)
{
    const auto path = source.toLocalFile();
    if (!source.isLocalFile() || durationMs <= 0 || !QFileInfo(path).isFile())
        return {};
    auto &entry = m_entries[path];
    if (!entry.framesRequested || entry.durationMs != durationMs) {
        entry.framesRequested = true;
        entry.durationMs = durationMs;
        enqueue(path, Kind::Frames);
    }
    return entry.frames;
}

QString ThumbnailStrip::waveformFor(const QUrl &source)
{
    const auto path = source.toLocalFile();
    if (!source.isLocalFile() || !QFileInfo(path).isFile())
        return {};
    auto &entry = m_entries[path];
    if (!entry.waveformRequested) {
        entry.waveformRequested = true;
        enqueue(path, Kind::Waveform);
    }
    return entry.waveform;
}

void ThumbnailStrip::enqueue(const QString &path, Kind kind)
{
    for (const auto &job : std::as_const(m_queue))
        if (job.path == path && job.kind == kind)
            return;
    m_queue.append({path, kind});
    // Never start work (or emit) from inside a QML binding evaluation.
    QTimer::singleShot(0, this, &ThumbnailStrip::startNext);
}

void ThumbnailStrip::startNext()
{
    if (m_process || m_queue.isEmpty())
        return;
    const auto ffmpeg = ffmpegExecutable();
    if (ffmpeg.isEmpty() || !m_directory.isValid()) {
        m_queue.clear();
        emit changed();
        return;
    }
    const auto job = m_queue.takeFirst();
    const auto entry = m_entries.value(job.path);
    const auto prefix = m_directory.path() + QStringLiteral("/s%1").arg(++m_counter, 4, 10, QChar('0'));
    QStringList arguments{"-hide_banner", "-nostdin", "-loglevel", "error"};
    int expected = 0;
    if (job.kind == Kind::Frames) {
        const auto seconds = qMax(0.1, entry.durationMs / 1000.0);
        expected = qBound(12, qCeil(seconds * 2.0), 240);
        if (seconds > 90)
            arguments << "-skip_frame" << "nokey";
        arguments << "-i" << job.path
                  << "-an" << "-sn"
                  << "-vf" << QStringLiteral("fps=%1,scale=-2:96").arg(expected / seconds, 0, 'f', 6)
                  << "-frames:v" << QString::number(expected)
                  << "-q:v" << "6" << "-y" << prefix + "_%04d.jpg";
    } else {
        arguments << "-i" << job.path
                  << "-filter_complex" << "aformat=channel_layouts=mono,showwavespic=s=2400x120:colors=0xffffff:draw=full"
                  << "-frames:v" << "1" << "-y" << prefix + "_wave.png";
    }

    auto *process = new QProcess(this);
    m_process = process;
    emit changed();
    connect(process, &QProcess::finished, this, [this, process, job, prefix](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        m_process = nullptr;
        auto &entry = m_entries[job.path];
        const bool ok = code == 0 && status == QProcess::NormalExit;
        if (job.kind == Kind::Frames) {
            QStringList frames;
            const QFileInfo base(prefix);
            const auto files = QDir(base.absolutePath()).entryInfoList({base.fileName() + "_*.jpg"}, QDir::Files, QDir::Name);
            for (const auto &file : files)
                frames.append(QUrl::fromLocalFile(file.absoluteFilePath()).toString());
            if (ok || !frames.isEmpty())
                entry.frames = frames;
        } else if (ok && QFileInfo(prefix + "_wave.png").size() > 0) {
            entry.waveform = QUrl::fromLocalFile(prefix + "_wave.png").toString();
        }
        ++m_revision;
        emit changed();
        startNext();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        m_process = nullptr;
        emit changed();
        startNext();
    });
    process->start(ffmpeg, arguments);
}
