#pragma once

#include <QObject>
#include <QProcess>
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
    QStringList frames() const;
    bool busy() const;
    Q_INVOKABLE void generate(const QUrl &source, qint64 durationMs);

signals:
    void changed();

private:
    void complete(int exitCode, QProcess::ExitStatus status);

    QProcess m_process;
    std::unique_ptr<QTemporaryDir> m_directory;
    QStringList m_frames;
    QString m_sourcePath;
    qint64 m_durationMs = 0;
    bool m_busy = false;
};
