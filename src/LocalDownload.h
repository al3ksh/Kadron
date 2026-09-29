#pragma once

#include "LocalMediaTools.h"
#include <QDate>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QTemporaryDir>
#include <QTimer>
#include <QUrl>
#include <memory>

class LocalDownload final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString ytDlpVersion READ ytDlpVersion NOTIFY changed)
    Q_PROPERTY(int ytDlpAgeDays READ ytDlpAgeDays NOTIFY changed)
    Q_PROPERTY(bool ytDlpOutdated READ ytDlpOutdated NOTIFY changed)
    Q_PROPERTY(QString ytDlpLatest READ ytDlpLatest NOTIFY changed)
    Q_PROPERTY(bool ytDlpUpdateAvailable READ ytDlpUpdateAvailable NOTIFY changed)
    Q_PROPERTY(bool checkingYtDlp READ checkingYtDlp NOTIFY changed)
    Q_PROPERTY(bool ytDlpUpdateFailed READ ytDlpUpdateFailed NOTIFY changed)
    Q_PROPERTY(bool updatingYtDlp READ updatingYtDlp NOTIFY changed)
    Q_PROPERTY(QString updateText READ updateText NOTIFY changed)
    Q_PROPERTY(bool probing READ probing NOTIFY previewChanged)
    Q_PROPERTY(QVariantMap preview READ preview NOTIFY previewChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString stage READ stage NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY changed)
    Q_PROPERTY(int progress READ progress NOTIFY changed)
    Q_PROPERTY(QUrl outputUrl READ outputUrl NOTIFY changed)
    Q_PROPERTY(qint64 outputBytes READ outputBytes NOTIFY changed)
    // The link being downloaded and its title, when known.
    Q_PROPERTY(QString currentUrl READ currentUrl NOTIFY changed)
    Q_PROPERTY(QString currentTitle READ currentTitle NOTIFY changed)
    // Links waiting their turn: [{ id, url, title, preset }].
    Q_PROPERTY(QVariantList queue READ queue NOTIFY queueChanged)
    // A playlist's videos: { url, title, entries: [{ url, title, durationMs }] },
    // plus loading or error while it is being read.
    Q_PROPERTY(QVariantMap playlist READ playlist NOTIFY playlistChanged)

public:
    explicit LocalDownload(QObject *parent = nullptr);
    ~LocalDownload() override;
    bool available() const;
    bool busy() const;
    QString stage() const;
    QString errorText() const;
    int progress() const;
    QUrl outputUrl() const;
    qint64 outputBytes() const;
    QString ytDlpVersion() const;
    int ytDlpAgeDays() const;
    bool ytDlpOutdated() const;
    QString ytDlpLatest() const;
    bool ytDlpUpdateAvailable() const;
    bool checkingYtDlp() const;
    bool ytDlpUpdateFailed() const;
    bool updatingYtDlp() const;
    QString updateText() const;
    bool probing() const;
    QVariantMap preview() const;
    QString currentUrl() const { return m_currentUrl; }
    QString currentTitle() const { return m_currentTitle; }
    QVariantList queue() const { return m_queue; }
    QVariantMap playlist() const { return m_playlist; }

    // Turns a media title into a safe file name (no path separators or reserved characters).
    Q_INVOKABLE static QString safeFileName(const QString &title);
    // `base.extension` in folder, or `base (2).extension` and so on when taken.
    static QString uniquePath(const QString &folder, const QString &base, const QString &extension);
    // YouTube video id from watch, shorts, embed or youtu.be links; empty otherwise.
    static QString youtubeId(const QString &url);
    // og:/twitter: title and image from a page, resolved against its URL.
    static QVariantMap pageMetadata(const QString &html, const QUrl &base);

    // Parses the date-based yt-dlp version (e.g. 2025.09.26 or 2025.09.26.1).
    static QDate versionDate(const QString &version);
    // True when the latest yt-dlp release is newer than the installed version.
    static bool isNewerYtDlp(const QString &latest, const QString &installed);
    // Picks the line worth showing from yt-dlp's stderr: its ERROR, not warnings.
    static QString summarizeError(const QString &stderrText);

    Q_INVOKABLE bool download(const QString &url, const QString &preset, const QUrl &destination,
                              double gifStart, double gifDuration, int gifFps, int gifWidth, double gifTargetMB);
    Q_INVOKABLE void cancel();
    // Downloads into a folder under the video's title, now or after the
    // downloads ahead of it. options may hold the GIF settings.
    Q_INVOKABLE void enqueue(const QString &url, const QString &preset, const QUrl &folder,
                             const QString &title = QString(), const QVariantMap &options = {});
    Q_INVOKABLE void removeQueued(int id);
    Q_INVOKABLE void clearQueue();
    // Lists the videos of a playlist link without downloading them.
    Q_INVOKABLE void probePlaylist(const QString &url);
    Q_INVOKABLE void clearPlaylist();
    // Updates Kadron's own yt-dlp copy, downloading the official release first if needed.
    Q_INVOKABLE void updateYtDlp();
    Q_INVOKABLE void refreshYtDlpVersion();
    // Asks GitHub for the newest yt-dlp release. The automatic check is skipped
    // when the last one was under 6 hours ago; the result is remembered.
    Q_INVOKABLE void checkYtDlpRelease(bool automatic = false);
    // Checks now and then every intervalMs while Kadron is open.
    void startAutomaticChecks(int intervalMs);
    // The clipboard text when it is a single http(s) link, empty otherwise.
    Q_INVOKABLE static QString clipboardLink();
    // Looks up title, thumbnail, duration and source for a URL without downloading it.
    Q_INVOKABLE void probe(const QString &url);

signals:
    void changed();
    void previewChanged();
    void queueChanged();
    void playlistChanged();
    // A download saved its file.
    void finished(const QUrl &file, const QString &url, const QString &title);

private:
    void readOutput();
    void finishDownload(int exitCode, QProcess::ExitStatus exitStatus);
    void fail(const QString &message);
    void finishUpdate(const QString &message, bool failed = false);
    void runSelfUpdate();
    void fetchPageMetadata(const QString &url);
    void startNext();
    void scheduleNext();
    static QVariantList playlistEntries(const QJsonObject &json);

    std::unique_ptr<QTemporaryDir> m_temp;
    QProcess m_process;
    LocalMediaTools m_gifTools;
    QString m_ytdlp;
    QString m_ffmpeg;
    QString m_destination;
    QString m_outputFolder;
    QString m_extension;
    QString m_downloaded;
    QString m_preset;
    QString m_stage;
    QString m_errorText;
    QByteArray m_outputBuffer;
    QByteArray m_errorBuffer;
    QUrl m_outputUrl;
    qint64 m_outputBytes = 0;
    int m_progress = 0;
    bool m_busy = false;
    bool m_encodingGif = false;
    bool m_cancelled = false;
    double m_gifStart = 0;
    double m_gifDuration = 8;
    double m_gifTargetMB = 8;
    int m_gifFps = 10;
    int m_gifWidth = 480;
    QNetworkAccessManager m_network;
    QPointer<QProcess> m_versionProcess;
    QString m_ytdlpVersion;
    QString m_updateText;
    bool m_updating = false;
    bool m_updateFailed = false;
    QString m_ytdlpLatest;
    bool m_checkingLatest = false;
    QTimer *m_checkTimer = nullptr;
    QPointer<QProcess> m_probeProcess;
    QString m_probeUrl;
    QVariantMap m_preview;
    QString m_currentUrl;
    QString m_currentTitle;
    QString m_folder;
    QVariantList m_queue;
    int m_nextQueueId = 1;
    QVariantMap m_playlist;
    QPointer<QProcess> m_playlistProcess;
};
