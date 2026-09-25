#include "EditorProject.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QtGlobal>

EditorProject::EditorProject(QObject *parent) : QObject(parent) {}

QUrl EditorProject::mediaUrl() const { return m_mediaUrl; }
QString EditorProject::mediaName() const { return QFileInfo(m_mediaUrl.toLocalFile()).fileName(); }
QUrl EditorProject::projectUrl() const { return m_projectUrl; }
qint64 EditorProject::durationMs() const { return m_durationMs; }
qint64 EditorProject::inMs() const { return m_inMs; }
qint64 EditorProject::outMs() const { return m_outMs; }
bool EditorProject::hasMedia() const { return m_mediaUrl.isLocalFile() && !m_mediaUrl.isEmpty(); }
bool EditorProject::dirty() const { return m_dirty; }
QString EditorProject::errorText() const { return m_errorText; }

void EditorProject::setError(const QString &message)
{
    if (m_errorText == message)
        return;
    m_errorText = message;
    emit errorTextChanged();
}

void EditorProject::clearError() { setError({}); }

void EditorProject::markChanged()
{
    m_dirty = true;
    emit changed();
}

bool EditorProject::importMedia(const QUrl &url)
{
    if (!url.isLocalFile() || !QFileInfo(url.toLocalFile()).isFile()) {
        setError(QStringLiteral("Choose a media file on this computer."));
        return false;
    }
    clearError();
    m_mediaUrl = QUrl::fromLocalFile(QFileInfo(url.toLocalFile()).absoluteFilePath());
    m_projectUrl = QUrl();
    m_durationMs = 0;
    m_inMs = 0;
    m_outMs = 0;
    markChanged();
    return true;
}

bool EditorProject::openProject(const QUrl &url)
{
    if (!url.isLocalFile()) {
        setError(QStringLiteral("Choose a local Kadron project."));
        return false;
    }

    QFile file(url.toLocalFile());
    if (!file.open(QIODevice::ReadOnly)) {
        setError(QStringLiteral("Could not open the project: %1").arg(file.errorString()));
        return false;
    }
    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(file.readAll(), &parseError);
    const auto object = document.object();
    if (parseError.error != QJsonParseError::NoError || !document.isObject()
        || object.value("version").toInt() != 1 || !object.value("media").isString()) {
        setError(QStringLiteral("This is not a supported Kadron project."));
        return false;
    }

    const auto projectFile = QFileInfo(file);
    const auto mediaPath = QDir(projectFile.absolutePath()).absoluteFilePath(object.value("media").toString());
    if (!QFileInfo(mediaPath).isFile()) {
        setError(QStringLiteral("Source media is missing: %1").arg(mediaPath));
        return false;
    }

    const auto duration = qMax<qint64>(0, object.value("durationMs").toVariant().toLongLong());
    const auto in = qBound<qint64>(0, object.value("inMs").toVariant().toLongLong(), duration);
    const auto out = qBound(in, object.value("outMs").toVariant().toLongLong(), duration);
    m_mediaUrl = QUrl::fromLocalFile(QFileInfo(mediaPath).absoluteFilePath());
    m_projectUrl = QUrl::fromLocalFile(projectFile.absoluteFilePath());
    m_durationMs = duration;
    m_inMs = in;
    m_outMs = out;
    m_dirty = false;
    clearError();
    emit changed();
    return true;
}

bool EditorProject::saveProject(const QUrl &url)
{
    const auto target = url.isEmpty() ? m_projectUrl : url;
    if (!hasMedia() || !target.isLocalFile()) {
        setError(QStringLiteral("Choose where to save the project first."));
        return false;
    }

    const auto targetInfo = QFileInfo(target.toLocalFile());
    const auto relativeMedia = QDir(targetInfo.absolutePath()).relativeFilePath(m_mediaUrl.toLocalFile());
    QJsonObject object{
        {"version", 1},
        {"media", relativeMedia},
        {"durationMs", static_cast<double>(m_durationMs)},
        {"inMs", static_cast<double>(m_inMs)},
        {"outMs", static_cast<double>(m_outMs)}
    };
    QSaveFile file(targetInfo.absoluteFilePath());
    if (!file.open(QIODevice::WriteOnly)
        || file.write(QJsonDocument(object).toJson(QJsonDocument::Indented)) < 0
        || !file.commit()) {
        setError(QStringLiteral("Could not save the project: %1").arg(file.errorString()));
        return false;
    }
    m_projectUrl = QUrl::fromLocalFile(targetInfo.absoluteFilePath());
    m_dirty = false;
    clearError();
    emit changed();
    return true;
}

void EditorProject::setDurationMs(qint64 value)
{
    if (!hasMedia() || value <= 0 || value == m_durationMs)
        return;
    const auto oldDuration = m_durationMs;
    m_durationMs = value;
    m_inMs = qBound<qint64>(0, m_inMs, value);
    m_outMs = oldDuration == 0 || m_outMs == oldDuration ? value : qBound(m_inMs, m_outMs, value);
    markChanged();
}

void EditorProject::setInMs(qint64 value)
{
    if (m_durationMs <= 0)
        return;
    value = qBound<qint64>(0, value, qMax<qint64>(0, m_outMs - qMin<qint64>(100, m_durationMs)));
    if (m_inMs != value) {
        m_inMs = value;
        markChanged();
    }
}

void EditorProject::setOutMs(qint64 value)
{
    if (m_durationMs <= 0)
        return;
    value = qBound(m_inMs + qMin<qint64>(100, m_durationMs), value, m_durationMs);
    if (m_outMs != value) {
        m_outMs = value;
        markChanged();
    }
}

void EditorProject::moveRange(qint64 deltaMs)
{
    if (m_durationMs <= 0 || m_outMs <= m_inMs)
        return;
    const auto clamped = qBound(-m_inMs, deltaMs, m_durationMs - m_outMs);
    if (clamped == 0)
        return;
    m_inMs += clamped;
    m_outMs += clamped;
    markChanged();
}
