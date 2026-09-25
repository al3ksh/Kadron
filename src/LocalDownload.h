#pragma once

#include "LocalMediaTools.h"
#include <QDate>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QTemporaryDir>
#include <QUrl>
#include <memory>

class LocalDownload final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString ytDlpVersion READ ytDlpVersion NOTIFY changed)
    Q_PROPERTY(int ytDlpAgeDays READ ytDlpAgeDays NOTIFY changed)
    Q_PROPERTY(bool ytDlpOutdated READ ytDlpOutdated NOTIFY changed)
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
    bool updatingYtDlp() const;
    QString updateText() const;
    bool probing() const;
    QVariantMap preview() const;

    // Turns a media title into a safe file name (no path separators or reserved characters).
    static QString safeFileName(const QString &title);
    // YouTube video id from watch, shorts, embed or youtu.be links; empty otherwise.
    static QString youtubeId(const QString &url);
    // og:/twitter: title and image from a page, resolved against its URL.
    static QVariantMap pageMetadata(const QString &html, const QUrl &base);

    // Parses the date-based yt-dlp version (e.g. 2025.09.26 or 2025.09.26.1).
    static QDate versionDate(const QString &version);
    // Picks the line worth showing from yt-dlp's stderr: its ERROR, not warnings.
    static QString summarizeError(const QString &stderrText);

    Q_INVOKABLE bool download(const QString &url, const QString &preset, const QUrl &destination,
                              double gifStart, double gifDuration, int gifFps, int gifWidth, double gifTargetMB);
    Q_INVOKABLE void cancel();
    // Updates Kadron's own yt-dlp copy, downloading the official release first if needed.
    Q_INVOKABLE void updateYtDlp();
    Q_INVOKABLE void refreshYtDlpVersion();
    // Looks up title, thumbnail, duration and source for a URL without downloading it.
    Q_INVOKABLE void probe(const QString &url);

signals:
    void changed();
    void previewChanged();

private:
    void readOutput();
    void finishDownload(int exitCode, QProcess::ExitStatus exitStatus);
    void fail(const QString &message);
    void finishUpdate(const QString &message);
    void runSelfUpdate();
    void fetchPageMetadata(const QString &url);

    std::unique_ptr<QTemporaryDir> m_temp;
    QProcess m_process;
    LocalMediaTools m_gifTools;
    QString m_ytdlp;
    QString m_ffmpeg;
    QString m_destination;
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
    QPointer<QProcess> m_probeProcess;
    QString m_probeUrl;
    QVariantMap m_preview;
};
