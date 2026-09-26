#include "AppUpdater.h"
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDate>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QVersionNumber>

namespace {
QString withoutPrefix(QString version)
{
    version = version.trimmed();
    if (version.startsWith('v', Qt::CaseInsensitive))
        version.remove(0, 1);
    return version;
}
}

AppUpdater::AppUpdater(QObject *parent)
    : QObject(parent)
{
    connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, &AppUpdater::applyPending);
}

QString AppUpdater::currentVersion() const { return QCoreApplication::applicationVersion(); }
QString AppUpdater::latestVersion() const { return m_release.value("version").toString(); }
bool AppUpdater::checking() const { return m_checking; }
bool AppUpdater::downloading() const { return m_downloading; }
qreal AppUpdater::progress() const { return m_progress; }
bool AppUpdater::ready() const { return !m_installer.isEmpty(); }
QString AppUpdater::statusText() const { return m_statusText; }

QUrl AppUpdater::releaseUrl() const
{
    const auto page = m_release.value("page").toUrl();
    return page.isValid() ? page : QUrl("https://github.com/al3ksh/Kadron/releases/latest");
}

bool AppUpdater::updateAvailable() const
{
    return !m_release.isEmpty() && isNewer(latestVersion(), currentVersion());
}

bool AppUpdater::canInstall() const
{
#ifdef Q_OS_WIN
    // Only installed copies have an uninstaller; the setup would not touch a portable folder.
    return QFileInfo::exists(QCoreApplication::applicationDirPath() + "/uninstall.exe");
#else
    return false;
#endif
}

QVariantMap AppUpdater::parseRelease(const QByteArray &json)
{
    const auto release = QJsonDocument::fromJson(json).object();
    if (release.value("draft").toBool() || release.value("prerelease").toBool())
        return {};
    const auto version = withoutPrefix(release.value("tag_name").toString());
    if (QVersionNumber::fromString(version).isNull())
        return {};

    QVariantMap result{{"version", version}, {"page", QUrl(release.value("html_url").toString())}};
    for (const auto &value : release.value("assets").toArray()) {
        const auto asset = value.toObject();
        const auto name = asset.value("name").toString();
        if (!name.endsWith("-setup.exe", Qt::CaseInsensitive))
            continue;
        const auto digest = asset.value("digest").toString();
        result.insert("asset", QUrl(asset.value("browser_download_url").toString()));
        result.insert("assetName", name);
        result.insert("size", asset.value("size").toInteger());
        result.insert("sha256", digest.startsWith("sha256:") ? digest.mid(7).toLower() : QString());
        break;
    }
    return result;
}

bool AppUpdater::isNewer(const QString &candidate, const QString &current)
{
    const auto next = QVersionNumber::fromString(withoutPrefix(candidate));
    return !next.isNull() && next > QVersionNumber::fromString(withoutPrefix(current));
}

QUrl AppUpdater::apiUrl() const
{
    const auto configured = qEnvironmentVariable("KADRON_UPDATE_URL");
    return QUrl(configured.isEmpty() ? QStringLiteral("https://api.github.com/repos/al3ksh/Kadron/releases/latest") : configured);
}

void AppUpdater::checkDaily()
{
    QSettings settings;
    const auto today = QDate::currentDate();
    if (settings.value("updates/lastCheck").toDate() == today)
        return;
    settings.setValue("updates/lastCheck", today);
    startCheck(false);
}

void AppUpdater::check()
{
    startCheck(true);
}

// A manual check reports every outcome; the automatic one only a new version.
void AppUpdater::startCheck(bool manual)
{
    if (m_checking || m_downloading || ready())
        return;
    m_manual = manual;
    m_checking = true;
    m_statusText = manual ? QStringLiteral("Checking for updates…") : QString();
    emit changed();

    QNetworkRequest request(apiUrl());
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setRawHeader("Accept", "application/vnd.github+json");
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Kadron/%1").arg(currentVersion()));
    request.setTransferTimeout(15000);
    auto *reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        m_checking = false;
        const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status == 404) {
            // No published release yet.
            m_release.clear();
            finish(m_manual ? QStringLiteral("Kadron %1 is up to date").arg(currentVersion()) : QString());
            return;
        }
        const auto release = reply->error() == QNetworkReply::NoError ? parseRelease(reply->readAll()) : QVariantMap{};
        if (release.isEmpty()) {
            finish(m_manual ? QStringLiteral("Could not check for updates") : QString());
            return;
        }
        m_release = release;
        if (updateAvailable())
            finish(QStringLiteral("Kadron %1 is available").arg(latestVersion()));
        else
            finish(m_manual ? QStringLiteral("Kadron %1 is up to date").arg(currentVersion()) : QString());
    });
}

void AppUpdater::install()
{
    if (!updateAvailable() || m_downloading || m_checking || ready())
        return;
    const auto asset = m_release.value("asset").toUrl();
    if (!canInstall() || !asset.isValid()) {
        finish(QStringLiteral("Download Kadron %1 from the release page").arg(latestVersion()));
        return;
    }

    m_downloading = true;
    m_progress = 0;
    m_statusText = QStringLiteral("Downloading Kadron %1…").arg(latestVersion());
    emit changed();

    QNetworkRequest request(asset);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Kadron/%1").arg(currentVersion()));
    auto *reply = m_network.get(request);
    connect(reply, &QNetworkReply::downloadProgress, this, [this](qint64 received, qint64 total) {
        if (total <= 0)
            total = m_release.value("size").toLongLong();
        m_progress = total > 0 ? qreal(received) / total : 0;
        emit changed();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        m_downloading = false;
        if (reply->error() != QNetworkReply::NoError) {
            finish(QStringLiteral("Update download failed: %1").arg(reply->errorString()));
            return;
        }
        const auto data = reply->readAll();
        const auto expectedSize = m_release.value("size").toLongLong();
        const auto expectedHash = m_release.value("sha256").toString();
        if ((expectedSize > 0 && data.size() != expectedSize)
            || (!expectedHash.isEmpty() && QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex() != expectedHash.toLatin1())) {
            finish(QStringLiteral("The downloaded update did not match the release; nothing was installed."));
            return;
        }

        const auto target = QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation))
                                .filePath(m_release.value("assetName").toString());
        QSaveFile file(target);
        if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size() || !file.commit()) {
            finish(QStringLiteral("Could not save the update to %1").arg(QDir::toNativeSeparators(target)));
            return;
        }
        m_installer = target;
        finish(QStringLiteral("Kadron %1 is ready to install").arg(latestVersion()));
    });
}

void AppUpdater::restartToUpdate()
{
    m_relaunch = true;
}

void AppUpdater::applyPending()
{
    if (m_installer.isEmpty())
        return;
    // The installer waits for this process to exit, then updates the install
    // folder recorded in the registry and, with /relaunch, starts Kadron again.
    QStringList arguments{QStringLiteral("/S")};
    if (m_relaunch)
        arguments << QStringLiteral("/relaunch");
    QProcess::startDetached(m_installer, arguments);
}

void AppUpdater::finish(const QString &message)
{
    m_statusText = message;
    emit changed();
}
