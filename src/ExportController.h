#pragma once

#include <QObject>
#include <QProcess>
#include <QUrl>

class ExportController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(int progress READ progress NOTIFY changed)
    Q_PROPERTY(QString stage READ stage NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY changed)
    Q_PROPERTY(QUrl outputUrl READ outputUrl NOTIFY changed)

public:
    explicit ExportController(QObject *parent = nullptr);
    bool available() const;
    bool busy() const;
    int progress() const;
    QString stage() const;
    QString errorText() const;
    QUrl outputUrl() const;

    Q_INVOKABLE bool start(const QUrl &source, const QUrl &destination, qint64 inMs, qint64 outMs);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void resetResult();

signals:
    void changed();

private:
    void readProgress();
    void finish(int exitCode, QProcess::ExitStatus exitStatus);
    void fail(const QString &message);
    void discardPartial();

    QString m_ffmpeg;
    QProcess m_process;
    QString m_partialPath;
    QString m_destinationPath;
    QByteArray m_progressBuffer;
    QByteArray m_errorBuffer;
    qint64 m_rangeMs = 0;
    bool m_busy = false;
    bool m_cancelled = false;
    int m_progress = 0;
    QString m_stage;
    QString m_errorText;
    QUrl m_outputUrl;
};
