#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QStringList>
#include <QTemporaryDir>
#include <QUrl>

// Caches a filmstrip and an audio waveform per source file. Both are produced by
// one FFmpeg pass each, queued one process at a time so the UI never blocks.
class ThumbnailStrip final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int revision READ revision NOTIFY changed)
    Q_PROPERTY(QStringList frames READ frames NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)

public:
    explicit ThumbnailStrip(QObject *parent = nullptr);
    ~ThumbnailStrip() override;
    int revision() const;
    QStringList frames() const;
    bool busy() const;

    Q_INVOKABLE QStringList framesFor(const QUrl &source, qint64 durationMs);
    Q_INVOKABLE QString waveformFor(const QUrl &source);
    Q_INVOKABLE void generate(const QUrl &source, qint64 durationMs);

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
    void startNext();

    QTemporaryDir m_directory;
    QHash<QString, Entry> m_entries;
    QList<Job> m_queue;
    QPointer<QProcess> m_process;
    QString m_lastSource;
    int m_revision = 0;
    int m_counter = 0;
};
