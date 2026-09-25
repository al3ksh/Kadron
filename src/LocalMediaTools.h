#pragma once

#include <QObject>
#include <QProcess>
#include <QUrl>

class LocalMediaTools final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString stage READ stage NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY changed)
    Q_PROPERTY(int progress READ progress NOTIFY changed)
    Q_PROPERTY(QUrl outputUrl READ outputUrl NOTIFY changed)
    Q_PROPERTY(qint64 outputBytes READ outputBytes NOTIFY changed)

public:
    explicit LocalMediaTools(QObject *parent = nullptr);
    bool available() const;
    bool busy() const;
    QString stage() const;
    QString errorText() const;
    int progress() const;
    QUrl outputUrl() const;
    qint64 outputBytes() const;

    Q_INVOKABLE bool convertAudio(const QUrl &source, const QUrl &destination, const QString &format,
                                  int bitrate, bool normalize, double startSec, double endSec);
    Q_INVOKABLE bool compress(const QUrl &source, const QUrl &destination, const QString &format,
                              int quality, double targetMB, int maxWidth, bool stripAudio);
    Q_INVOKABLE bool createGif(const QUrl &source, const QUrl &destination, double startSec,
                               double durationSec, int fps, int width, double targetMB);
    Q_INVOKABLE void cancel();

signals:
    void changed();

private:
    enum class Operation { None, Audio, Image, Video, Gif };
    enum class Phase { Idle, Probe, Encode };
    bool begin(const QUrl &source, const QUrl &destination, Operation operation);
    void probe();
    void encode();
    QStringList arguments() const;
    void onFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void readProgress();
    void fail(const QString &message);
    void discardPartial();

    QProcess m_process;
    QString m_ffmpeg;
    QString m_ffprobe;
    QString m_sourcePath;
    QString m_outputPath;
    QString m_partialPath;
    QString m_format;
    QString m_stage;
    QString m_errorText;
    QUrl m_outputUrl;
    QByteArray m_progressBuffer;
    QByteArray m_errorBuffer;
    Operation m_operation = Operation::None;
    Phase m_phase = Phase::Idle;
    qint64 m_durationMs = 0;
    qint64 m_targetBytes = 0;
    qint64 m_outputBytes = 0;
    int m_progress = 0;
    int m_quality = 75;
    int m_bitrate = 192;
    int m_videoKbps = 0;
    int m_maxWidth = 1280;
    int m_fps = 10;
    int m_attempt = 0;
    double m_startSec = 0;
    double m_endSec = 0;
    double m_gifDurationSec = 8;
    bool m_normalize = false;
    bool m_stripAudio = false;
    bool m_cancelled = false;
};
