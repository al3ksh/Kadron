#pragma once

#include <QObject>
#include <QProcess>
#include <QPointer>
#include <QStringList>
#include <QTemporaryDir>
#include <QUrl>
#include <memory>

class ThumbnailStrip final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList frames READ frames NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)

public:
    explicit ThumbnailStrip(QObject *parent = nullptr);
    ~ThumbnailStrip() override;
    QStringList frames() const;
    bool busy() const;
    Q_INVOKABLE void generate(const QUrl &source, qint64 durationMs);

signals:
    void changed();

private:
    struct Generation {
        std::unique_ptr<QTemporaryDir> directory;
        QString sourcePath;
        qint64 durationMs = 0;
        int nextFrame = 0;
    };
    void startNext();

    QPointer<QProcess> m_process;
    std::shared_ptr<Generation> m_generation;
    QStringList m_frames;
    QString m_sourcePath;
    qint64 m_durationMs = 0;
    bool m_busy = false;
};
