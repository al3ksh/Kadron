#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QTemporaryDir>
#include <QUrl>
#include <QVariantList>
#include <QVector>
#include <memory>

class ExportController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(int progress READ progress NOTIFY changed)
    Q_PROPERTY(QString stage READ stage NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY changed)
    Q_PROPERTY(QUrl outputUrl READ outputUrl NOTIFY changed)
    // Video encoder: "auto" (a working GPU encoder, else CPU), "cpu", or one
    // of the detected hardware encoders ("nvenc", "qsv", "amf").
    Q_PROPERTY(QString encoder READ encoder WRITE setEncoder NOTIFY encoderChanged)
    Q_PROPERTY(QStringList hardwareEncoders READ hardwareEncoders NOTIFY encoderChanged)
    Q_PROPERTY(bool detectingEncoders READ detectingEncoders NOTIFY encoderChanged)
    Q_PROPERTY(bool encodersChecked READ encodersChecked NOTIFY encoderChanged)
    // What the running or last export actually used, e.g. "NVIDIA NVENC".
    Q_PROPERTY(QString encoderUsed READ encoderUsed NOTIFY changed)

public:
    explicit ExportController(QObject *parent = nullptr);
    bool available() const;
    bool busy() const;
    int progress() const;
    QString stage() const;
    QString errorText() const;
    QUrl outputUrl() const;
    QString encoder() const;
    void setEncoder(const QString &encoder);
    QStringList hardwareEncoders() const;
    bool detectingEncoders() const;
    bool encodersChecked() const;
    QString encoderUsed() const;

    // Arguments that select and tune the encoder, between inputs and output.
    static QStringList videoCodecArgs(const QString &encoder, bool fast);
    static QString encoderLabel(const QString &encoder);
    // Tries each hardware encoder with a tiny encode; slow, call off the UI thread.
    static QStringList probeHardwareEncoders(const QString &ffmpeg);

    Q_INVOKABLE void detectEncoders();
    Q_INVOKABLE bool start(const QUrl &source, const QUrl &destination, qint64 inMs, qint64 outMs);
    Q_INVOKABLE bool startSequence(const QVariantList &clips, const QUrl &destination);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void resetResult();

signals:
    void changed();
    void encoderChanged();

private:
    struct Segment {
        QString path;
        qint64 inMs = 0;
        qint64 outMs = 0;
        bool hasVideo = false;
        bool hasAudio = false;
    };
    enum class Phase { Idle, Single, Probe, Encode, Concat };
    void probeNext();
    void encodeNext();
    void concatSegments();
    void clearSequence();
    void readProgress();
    void finish(int exitCode, QProcess::ExitStatus exitStatus);
    void fail(const QString &message);
    void discardPartial();
    void launchSingle();
    QString resolvedEncoder() const;
    bool fallBackToCpu();

    QString m_ffmpeg;
    QString m_ffprobe;
    QProcess m_process;
    QString m_partialPath;
    QString m_destinationPath;
    QByteArray m_progressBuffer;
    QByteArray m_errorBuffer;
    QVector<Segment> m_segments;
    std::unique_ptr<QTemporaryDir> m_sequenceDir;
    Phase m_phase = Phase::Idle;
    int m_segmentIndex = 0;
    int m_canvasWidth = 0;
    int m_canvasHeight = 0;
    qint64 m_completedMs = 0;
    qint64 m_rangeMs = 0;
    bool m_busy = false;
    bool m_cancelled = false;
    int m_progress = 0;
    QString m_stage;
    QString m_errorText;
    QUrl m_outputUrl;
    QString m_encoder = QStringLiteral("auto");
    QStringList m_hardwareEncoders;
    bool m_detecting = false;
    bool m_checked = false;
    QString m_activeEncoder = QStringLiteral("cpu");
    bool m_fellBack = false;
    QString m_singleSource;
    qint64 m_singleInMs = 0;
};
