#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QStringList>
#include <QUrl>

// Caches a filmstrip and an audio waveform per source file. Both are produced by
// one FFmpeg pass each, queued one process at a time so the UI never blocks.
// Results stay on disk, keyed by path, size and modification time, so reopening
// a file shows them at once; the oldest are pruned past a size limit.
class ThumbnailStrip final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int revision READ revision NOTIFY changed)
    Q_PROPERTY(QStringList frames READ frames NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)

public:
    // An empty directory means the user's cache location.
    explicit ThumbnailStrip(const QString &cacheDirectory = {}, QObject *parent = nullptr);
    ~ThumbnailStrip() override;
    int revision() const;
    QStringList frames() const;
    bool busy() const;

    Q_INVOKABLE QStringList framesFor(const QUrl &source, qint64 durationMs);
    Q_INVOKABLE QString waveformFor(const QUrl &source);
    Q_INVOKABLE void generate(const QUrl &source, qint64 durationMs);
    QString cacheDirectory() const;
    // Removes the least recently used results until the cache is under maxBytes.
    void prune(qint64 maxBytes);

signals:
    void changed();

private:
    enum class Kind { Frames, Waveform };
    struct Entry {
        QStringList frames;
        QString waveform;
        qint64 durationMs = 0;
        bool framesRequested = false;
        bool waveformRequested = false;
    };
    struct Job {
        QString path;
        Kind kind;
    };
    void enqueue(const QString &path, Kind kind);
    // Cache folder for one result; empty when the source can't be read.
    QString itemDirectory(const QString &path, Kind kind, qint64 durationMs) const;
    // Files of a finished cached result, touching it as recently used.
    static QStringList cachedFiles(const QString &directory, const QString &pattern);
    void startNext();

    QString m_directory;
    QString m_activeDirectory;
    QHash<QString, Entry> m_entries;
    QList<Job> m_queue;
    QPointer<QProcess> m_process;
    QString m_lastSource;
    int m_revision = 0;
};
