#include "ThumbnailStrip.h"
#include "MediaTools.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTimer>
#include <QtMath>
#include <algorithm>

namespace {
constexpr qint64 cacheLimitBytes = 500LL * 1024 * 1024;
const auto doneMarker = QStringLiteral("done");
}

ThumbnailStrip::ThumbnailStrip(const QString &cacheDirectory, QObject *parent)
    : QObject(parent)
    , m_directory(cacheDirectory.isEmpty()
                      ? QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/timeline")
                      : cacheDirectory)
{
    QDir().mkpath(m_directory);
    QTimer::singleShot(5000, this, [this] { prune(cacheLimitBytes); });
}

QString ThumbnailStrip::cacheDirectory() const { return m_directory; }

QString ThumbnailStrip::itemDirectory(const QString &path, Kind kind, qint64 durationMs) const
{
    const QFileInfo info(path);
    if (!info.isFile())
        return {};
    const auto identity = QStringLiteral("%1|%2|%3").arg(info.absoluteFilePath()).arg(info.size())
                              .arg(info.lastModified().toMSecsSinceEpoch());
    const auto key = QCryptographicHash::hash(identity.toUtf8(), QCryptographicHash::Sha1).toHex().left(20);
    const auto suffix = kind == Kind::Frames ? QStringLiteral("-f%1").arg(durationMs) : QStringLiteral("-w");
    return m_directory + '/' + QString::fromLatin1(key) + suffix;
}

QStringList ThumbnailStrip::cachedFiles(const QString &directory, const QString &pattern)
{
    QFile marker(directory + '/' + doneMarker);
    if (directory.isEmpty() || !marker.exists())
        return {};
    if (marker.open(QIODevice::ReadWrite))
        marker.setFileTime(QDateTime::currentDateTime(), QFileDevice::FileModificationTime);
    QStringList files;
    for (const auto &file : QDir(directory).entryInfoList({pattern}, QDir::Files, QDir::Name))
        files.append(QUrl::fromLocalFile(file.absoluteFilePath()).toString());
    return files;
}

void ThumbnailStrip::prune(qint64 maxBytes)
{
    struct Item { QString path; QDateTime used; qint64 bytes; };
    QList<Item> items;
    qint64 total = 0;
    for (const auto &folder : QDir(m_directory).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        Item item{folder.absoluteFilePath(), QFileInfo(folder.absoluteFilePath() + '/' + doneMarker).lastModified(), 0};
        for (const auto &file : QDir(item.path).entryInfoList(QDir::Files))
            item.bytes += file.size();
        total += item.bytes;
        items.append(item);
    }
    if (total <= maxBytes)
        return;
    // Unfinished folders have no marker, so they sort first and go first.
    std::sort(items.begin(), items.end(), [](const Item &a, const Item &b) { return a.used < b.used; });
    for (const auto &item : std::as_const(items)) {
        if (total <= maxBytes * 8 / 10)
            break;
        if (item.path == QFileInfo(m_activeDirectory).absoluteFilePath())
            continue;
        if (QDir(item.path).removeRecursively())
            total -= item.bytes;
    }
}

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
        const auto cached = cachedFiles(itemDirectory(path, Kind::Frames, durationMs), QStringLiteral("f_*.jpg"));
        if (cached.isEmpty())
            enqueue(path, Kind::Frames);
        else
            entry.frames = cached;
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
        const auto cached = cachedFiles(itemDirectory(path, Kind::Waveform, 0), QStringLiteral("wave.png"));
        if (cached.isEmpty())
            enqueue(path, Kind::Waveform);
        else
            entry.waveform = cached.first();
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
    const auto job = m_queue.isEmpty() ? Job{} : m_queue.first();
    const auto entry = m_entries.value(job.path);
    const auto directory = itemDirectory(job.path, job.kind, entry.durationMs);
    if (ffmpeg.isEmpty() || directory.isEmpty()) {
        m_queue.clear();
        emit changed();
        return;
    }
    m_queue.removeFirst();
    // Start clean so a result interrupted last time never mixes with this one.
    QDir(directory).removeRecursively();
    if (!QDir().mkpath(directory)) {
        QTimer::singleShot(0, this, &ThumbnailStrip::startNext);
        return;
    }
    m_activeDirectory = directory;
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
                  << "-q:v" << "6" << "-y" << directory + "/f_%04d.jpg";
    } else {
        arguments << "-i" << job.path
                  << "-filter_complex" << "aformat=channel_layouts=mono,showwavespic=s=2400x120:colors=0xffffff:draw=full:filter=peak"
                  << "-frames:v" << "1" << "-y" << directory + "/wave.png";
    }

    auto *process = new QProcess(this);
    m_process = process;
    emit changed();
    connect(process, &QProcess::finished, this, [this, process, job, directory](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        m_process = nullptr;
        m_activeDirectory.clear();
        auto &entry = m_entries[job.path];
        const bool ok = code == 0 && status == QProcess::NormalExit;
        if (job.kind == Kind::Frames) {
            QStringList frames;
            const auto files = QDir(directory).entryInfoList({QStringLiteral("f_*.jpg")}, QDir::Files, QDir::Name);
            for (const auto &file : files)
                frames.append(QUrl::fromLocalFile(file.absoluteFilePath()).toString());
            if (ok || !frames.isEmpty())
                entry.frames = frames;
        } else if (ok && QFileInfo(directory + "/wave.png").size() > 0) {
            entry.waveform = QUrl::fromLocalFile(directory + "/wave.png").toString();
        }
        // Only complete results are reused next time.
        if (ok) {
            QFile marker(directory + '/' + doneMarker);
            if (marker.open(QIODevice::WriteOnly))
                marker.close();
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
        m_activeDirectory.clear();
        emit changed();
        startNext();
    });
    process->start(ffmpeg, arguments);
}
