#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QUrl>
#include <QVariantMap>

class QNetworkReply;

// Checks GitHub Releases for a newer Kadron and installs it with the release's
// setup.exe. The download is verified first; the installer only runs once
// Kadron exits, so the normal close (and its unsaved-project prompt) decides.
// Portable copies (no uninstaller next to kadron.exe) are pointed at the
// release page instead, since the installer would not update them in place.
class AppUpdater final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY changed)
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY changed)
    Q_PROPERTY(bool canInstall READ canInstall CONSTANT)
    Q_PROPERTY(bool checking READ checking NOTIFY changed)
    Q_PROPERTY(bool downloading READ downloading NOTIFY changed)
    Q_PROPERTY(qreal progress READ progress NOTIFY changed)
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(QString statusText READ statusText NOTIFY changed)
    Q_PROPERTY(QUrl releaseUrl READ releaseUrl NOTIFY changed)

public:
    explicit AppUpdater(QObject *parent = nullptr);
    QString currentVersion() const;
    QString latestVersion() const;
    bool updateAvailable() const;
    bool canInstall() const;
    bool checking() const;
    bool downloading() const;
    qreal progress() const;
    bool ready() const;
    QString statusText() const;
    QUrl releaseUrl() const;

    // Reads a GitHub "latest release" response: version (without a leading v),
    // page, and the setup.exe asset's URL, size and SHA-256 (empty if GitHub
    // did not publish one). Returns an empty map for anything unusable.
    static QVariantMap parseRelease(const QByteArray &json);
    static bool isNewer(const QString &candidate, const QString &current);

    Q_INVOKABLE void check();
    // Checks at most once a day; used at startup.
    Q_INVOKABLE void checkDaily();
    // Downloads and verifies the installer; it runs when Kadron exits.
    Q_INVOKABLE void install();
    // Makes the pending installer start Kadron again; the caller closes the window.
    Q_INVOKABLE void restartToUpdate();

signals:
    void changed();

private:
    void startCheck(bool manual);
    void applyPending();
    void finish(const QString &message);
    QUrl apiUrl() const;

    QNetworkAccessManager m_network;
    QVariantMap m_release;
    bool m_checking = false;
    bool m_downloading = false;
    bool m_manual = false;
    bool m_relaunch = false;
    QString m_installer;
    qreal m_progress = 0;
    QString m_statusText;
};
