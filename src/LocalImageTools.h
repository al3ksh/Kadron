#pragma once

#include <QFutureWatcher>
#include <QMutex>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QSet>
#include <QTemporaryDir>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <atomic>
#include <memory>

// The Images workspace: batch convert, resize, crop and clean photos with the
// bundled FFmpeg.
//
// A job is a QVariantMap from QML:
//   source (url), format ("same", "jpg", "png", "webp", "avif"), quality
//   (1-100), targetKB (0 = off), resize ("none", "long", "percent", "box"),
//   longEdge, percent, boxWidth, boxHeight, rotate (0/90/180/270), flipH,
//   flipV, and a crop rectangle cropX/cropY/cropW/cropH normalized to the
//   image after its EXIF orientation and the rotation/flips.
// Saved images never carry metadata: FFmpeg re-encodes them and drops EXIF,
// GPS and camera details.
class LocalImageTools final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    // Per source URL string: {name, bytes, width, height, format, hasAlpha,
    // orientation, camera, taken, hasGps, latitude, longitude, thumb, error}.
    Q_PROPERTY(QVariantMap infos READ infos NOTIFY infosChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(int progress READ progress NOTIFY changed)
    Q_PROPERTY(QString stage READ stage NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY changed)
    // After a batch: [{source, output, bytes, sourceBytes, note, error}].
    Q_PROPERTY(QVariantList results READ results NOTIFY changed)
    Q_PROPERTY(QUrl outputFolder READ outputFolder NOTIFY changed)
    // The selected image with the current settings: {source, key, before,
    // after (display PNGs), bytes, width, height, note, error}.
    Q_PROPERTY(QVariantMap preview READ preview NOTIFY previewChanged)
    Q_PROPERTY(bool previewBusy READ previewBusy NOTIFY previewChanged)

public:
    explicit LocalImageTools(QObject *parent = nullptr);
    ~LocalImageTools() override;

    bool available() const;
    QVariantMap infos() const;
    bool busy() const;
    int progress() const;
    QString stage() const;
    QString errorText() const;
    QVariantList results() const;
    QUrl outputFolder() const;
    QVariantMap preview() const;
    bool previewBusy() const;

    Q_INVOKABLE void inspect(const QVariantList &sources);
    Q_INVOKABLE void renderPreview(const QVariantMap &job);
    Q_INVOKABLE bool process(const QVariantList &jobs, const QUrl &folder);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void clearResults();
    Q_INVOKABLE static bool isImageFile(const QUrl &url);

    // Building blocks, public for tests.
    static QVariantMap parseExif(const QByteArray &file);
    static QString outputFormat(const QString &requested, const QString &sourceExtension);
    static QString filterChain(const QVariantMap &job, bool flatten);
    static QStringList codecArguments(const QString &format, int quality);
    static QString uniqueOutputPath(const QString &folder, const QString &baseName, const QString &extension,
                                    const QSet<QString> &taken = {});

    struct Encoded {
        qint64 bytes = 0;
        QString note;
        QString error;
    };
    // Encodes one image to `outputPath`, searching the quality for a target
    // size when the job has one. Blocking; call off the UI thread.
    static Encoded encode(const QString &ffmpeg, const QString &sourcePath, const QVariantMap &job,
                          const QString &format, bool hasAlpha, const QString &outputPath,
                          const std::atomic_bool *cancelled = nullptr);

signals:
    void changed();
    void infosChanged();
    void previewChanged();

private:
    QString workPath(const QString &name) const;
    void setPreview(const QVariantMap &preview, bool busy);

    QString m_ffmpeg;
    QString m_ffprobe;
    std::unique_ptr<QTemporaryDir> m_work;
    QVariantMap m_infos;
    QSet<QString> m_inspecting;

    bool m_busy = false;
    int m_progress = 0;
    QString m_stage;
    QString m_errorText;
    QVariantList m_results;
    QUrl m_outputFolder;
    std::shared_ptr<std::atomic_bool> m_cancelled;

    QVariantMap m_preview;
    bool m_previewBusy = false;
    int m_previewGeneration = 0;
    QVariantMap m_pendingPreview;
};
