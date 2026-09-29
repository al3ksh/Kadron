#pragma once

#include "TextOverlay.h"

#include <QObject>
#include <memory>
#include <QProcess>
#include <QSize>
#include <QTemporaryDir>
#include <QUrl>
#include <QVariantMap>

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
    ~LocalMediaTools() override;
    bool available() const;
    bool busy() const;
    QString stage() const;
    QString errorText() const;
    int progress() const;
    QUrl outputUrl() const;
    qint64 outputBytes() const;

    // options: fadeIn and fadeOut in seconds, lufs (the loudness target when
    // normalizing, -14 by default) and mono.
    Q_INVOKABLE bool convertAudio(const QUrl &source, const QUrl &destination, const QString &format,
                                  int bitrate, bool normalize, double startSec, double endSec,
                                  const QVariantMap &options = {});
    Q_INVOKABLE bool compress(const QUrl &source, const QUrl &destination, const QString &format,
                              int quality, double targetMB, int maxWidth, bool stripAudio);
    Q_INVOKABLE bool createGif(const QUrl &source, const QUrl &destination, double startSec,
                               double durationSec, int fps, int width, double targetMB);
    // Turns a video into another shape. options: mode ("crop" follows the
    // keyframed frame, "blur" fits the whole picture over a blurred copy,
    // "split" stacks two regions: panels [{x, y, w, h}] top then bottom,
    // normalized to the picture, and share, the top band's part of the height),
    // aspectW/aspectH, zoom (crop only, 1 = largest frame that fits) and
    // keyframes: [{t: seconds, x, y}] with the frame centre normalized 0..1.
    Q_INVOKABLE bool reframe(const QUrl &source, const QUrl &destination, const QVariantMap &options);
    Q_INVOKABLE void cancel();

    // Size of a local file in bytes, 0 when it is missing.
    Q_INVOKABLE static qint64 fileBytes(const QUrl &url);

    // The export size for an aspect: 1080 on the short side.
    Q_INVOKABLE static QSize reframeOutput(int aspectW, int aspectH);
    // The crop in source pixels for an aspect and zoom.
    Q_INVOKABLE static QSize reframeCrop(QSize source, int aspectW, int aspectH, double zoom);
    // Heights of the top and bottom panels of a split output.
    static QPair<int, int> splitHeights(QSize output, double share);
    // FFmpeg filter graph from [0:v] to [v], with options.texts drawn on top
    // (their files come from TextOverlay::writeAssets in the working directory).
    static QString reframeFilter(QSize source, const QVariantMap &options);
    // The texts in options.texts worth drawing, in the order the filter numbers them.
    static QVector<TextOverlay> reframeTexts(const QVariantMap &options);

signals:
    void changed();

private:
    static QString reframePicture(QSize source, const QVariantMap &options);
    enum class Operation { None, Audio, Image, Video, Gif, Reframe };
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
    double m_lufs = -14;
    double m_fadeInSec = 0;
    double m_fadeOutSec = 0;
    bool m_mono = false;
    bool m_stripAudio = false;
    bool m_cancelled = false;
    QVariantMap m_reframe;
    std::unique_ptr<QTemporaryDir> m_textDir;
    QSize m_sourceSize;
};
