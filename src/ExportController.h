#pragma once

#include <QObject>
#include <QProcess>
#include <QSize>
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
    // A bitrate (kbit/s) instead of constant quality when videoKbps > 0.
    static QStringList videoCodecArgs(const QString &encoder, bool fast, int videoKbps = 0);
    static QString encoderLabel(const QString &encoder);
    // Tries each hardware encoder with a tiny encode; slow, call off the UI thread.
    static QStringList probeHardwareEncoders(const QString &ffmpeg);
    // Sequence frame size for a first clip of this size: at most 1920 on the
    // long side and 1080 on the short one, so portrait stays 1080x1920.
    static QSize canvasFor(int width, int height, int maxLong = 1920, int maxShort = 1080);
    // What an export preset makes of a sequence whose first clip is source
    // at sourceFps: "source" keeps size and frame rate (up to 4K/120),
    // "1080p60" caps at 1080p and 60 fps, "discord" fits 10 MB at 720p and
    // "vertical" fills a 1080x1920 frame.
    struct OutputPlan {
        QSize canvas;
        int fps = 30;
        bool fill = false;
        int videoKbps = 0;
        int audioKbps = 192;
    };
    static OutputPlan outputPlan(const QString &preset, QSize source, double sourceFps, qint64 durationMs);
    // Video bitrate that keeps an export of this length under 10 MB.
    Q_INVOKABLE static int discordVideoKbps(qint64 durationMs);
    // "30000/1001" -> 29.97; 0 when unknown.
    static double frameRate(const QString &rational);
    // One file on the audio track: the part inMs..outMs of it plays from
    // startMs of the exported video.
    struct AudioBed {
        qint64 startMs = 0;
        qint64 inMs = 0;
        qint64 outMs = 0;
        double volume = 1.0;
        qint64 fadeInMs = 0;
        qint64 fadeOutMs = 0;
    };
    // Final pass over the encoded clips (inputs 0..n-1, or one joined file):
    // crossfades them when crossfadeMs > 0 and mixes in the audio track, one
    // input per bed from firstAudioInput. Outputs [a], and [v] when crossfading.
    static QString mixFilter(const QVector<qint64> &lengthsMs, int crossfadeMs, int firstAudioInput,
                             const QVector<AudioBed> &beds, bool duck, int fps = 30);

    Q_INVOKABLE void detectEncoders();
    // options: preset (see outputPlan), loudnorm to even out loudness, and
    // copy for a lossless cut at keyframes (no re-encode, ignores the rest).
    Q_INVOKABLE bool start(const QUrl &source, const QUrl &destination, qint64 inMs, qint64 outMs,
                           const QVariantMap &options = {});
    // options: the ones above, transition ("cut", "fade", "crossfade"),
    // transitionMs, audio (a list of {url, startMs, inMs, outMs, volume} in
    // sequence time) and musicDuck to lower the audio track under the clips'
    // own sound. Clips may carry a speed (0.25 to 4).
    Q_INVOKABLE bool startSequence(const QVariantList &clips, const QUrl &destination,
                                   const QVariantMap &options = {});
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
        double volume = 1.0;
        double speed = 1.0;
        // Length in the exported video.
        qint64 lengthMs() const { return qRound64((outMs - inMs) / speed); }
    };
    enum class Phase { Idle, Single, Probe, Encode, Concat, Final };
    void probeNext();
    void encodeNext();
    void concatSegments();
    void startFinal();
    QString segmentPath(int index) const;
    QString joinedPath() const;
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
    double m_sourceFps = 0;
    QString m_preset;
    bool m_loudnorm = false;
    OutputPlan m_plan;
    qint64 m_completedMs = 0;
    qint64 m_rangeMs = 0;
    // Sequence options.
    QString m_transition;
    int m_transitionMs = 0;
    QStringList m_audioPaths;
    QVector<AudioBed> m_audioBeds;
    bool m_musicDuck = true;
    // Share of the progress bar the clip encodes take; the rest is the final pass.
    int m_encodeShare = 90;
    qint64 m_finalMs = 0;
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
    bool m_copy = false;
};
