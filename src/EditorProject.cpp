#include "EditorProject.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QtGlobal>

EditorProject::EditorProject(QObject *parent) : QObject(parent) {}

const EditorProject::Clip *EditorProject::active() const
{
    return m_activeClipIndex >= 0 && m_activeClipIndex < m_clips.size() ? &m_clips[m_activeClipIndex] : nullptr;
}

EditorProject::Clip *EditorProject::active()
{
    return m_activeClipIndex >= 0 && m_activeClipIndex < m_clips.size() ? &m_clips[m_activeClipIndex] : nullptr;
}

QUrl EditorProject::mediaUrl() const { return active() ? active()->mediaUrl : QUrl(); }
QString EditorProject::mediaName() const { return QFileInfo(mediaUrl().toLocalFile()).fileName(); }
QUrl EditorProject::projectUrl() const { return m_projectUrl; }
qint64 EditorProject::durationMs() const { return active() ? active()->durationMs : 0; }
qint64 EditorProject::inMs() const { return active() ? active()->inMs : 0; }
qint64 EditorProject::outMs() const { return active() ? active()->outMs : 0; }
int EditorProject::clipCount() const { return m_clips.size(); }
int EditorProject::activeClipIndex() const { return m_activeClipIndex; }
bool EditorProject::hasMedia() const { return active() != nullptr; }
bool EditorProject::dirty() const { return m_dirty; }
QString EditorProject::errorText() const { return m_errorText; }

QVariantList EditorProject::clips() const
{
    QVariantList result;
    for (const auto &clip : m_clips) {
        result.append(QVariantMap{
            {"url", clip.mediaUrl},
            {"name", QFileInfo(clip.mediaUrl.toLocalFile()).fileName()},
            {"durationMs", clip.durationMs},
            {"inMs", clip.inMs},
            {"outMs", clip.outMs},
            {"lengthMs", qMax<qint64>(0, clip.outMs - clip.inMs)}
        });
    }
    return result;
}

qint64 EditorProject::sequenceDurationMs() const
{
    qint64 total = 0;
    for (const auto &clip : m_clips)
        total += qMax<qint64>(0, clip.outMs - clip.inMs);
    return total;
}

bool EditorProject::canExport() const
{
    if (m_clips.isEmpty())
        return false;
    for (const auto &clip : m_clips) {
        if (!QFileInfo(clip.mediaUrl.toLocalFile()).isFile()
            || clip.durationMs <= 0 || clip.outMs - clip.inMs < 100 || clip.outMs > clip.durationMs)
            return false;
    }
    return true;
}

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

bool EditorProject::validMedia(const QUrl &url)
{
    if (url.isLocalFile() && QFileInfo(url.toLocalFile()).isFile())
        return true;
    setError(QStringLiteral("Choose a media file on this computer."));
    return false;
}

bool EditorProject::importMedia(const QUrl &url)
{
    if (!validMedia(url))
        return false;
    clearError();
    m_clips = {{QUrl::fromLocalFile(QFileInfo(url.toLocalFile()).absoluteFilePath()), 0, 0, 0}};
    m_activeClipIndex = 0;
    m_projectUrl = QUrl();
    markChanged();
    return true;
}

bool EditorProject::appendMedia(const QUrl &url)
{
    if (!validMedia(url))
        return false;
    const auto absoluteUrl = QUrl::fromLocalFile(QFileInfo(url.toLocalFile()).absoluteFilePath());
    Clip clip{absoluteUrl, 0, 0, 0};
    for (const auto &existing : m_clips) {
        if (existing.mediaUrl == absoluteUrl && existing.durationMs > 0) {
            clip.durationMs = existing.durationMs;
            clip.outMs = existing.durationMs;
            break;
        }
    }
    m_clips.append(clip);
    m_activeClipIndex = m_clips.size() - 1;
    clearError();
    markChanged();
    return true;
}

bool EditorProject::selectClip(int index)
{
    if (index < 0 || index >= m_clips.size())
        return false;
    if (index != m_activeClipIndex) {
        m_activeClipIndex = index;
        clearError();
        emit changed();
    }
    return true;
}

bool EditorProject::splitAt(qint64 positionMs)
{
    auto *clip = active();
    if (!clip || positionMs - clip->inMs < 100 || clip->outMs - positionMs < 100) {
        setError(QStringLiteral("Move the playhead inside the selected range before splitting."));
        return false;
    }
    Clip right = *clip;
    right.inMs = positionMs;
    clip->outMs = positionMs;
    m_clips.insert(m_activeClipIndex + 1, right);
    ++m_activeClipIndex;
    clearError();
    markChanged();
    return true;
}

bool EditorProject::moveClip(int index, int direction)
{
    const auto target = index + direction;
    if ((direction != -1 && direction != 1) || index < 0 || target < 0
        || index >= m_clips.size() || target >= m_clips.size())
        return false;
    m_clips.swapItemsAt(index, target);
    if (m_activeClipIndex == index) m_activeClipIndex = target;
    else if (m_activeClipIndex == target) m_activeClipIndex = index;
    clearError();
    markChanged();
    return true;
}

bool EditorProject::removeClip(int index)
{
    if (index < 0 || index >= m_clips.size() || m_clips.size() <= 1)
        return false;
    m_clips.removeAt(index);
    if (m_activeClipIndex >= index)
        m_activeClipIndex = qMax(0, m_activeClipIndex - 1);
    clearError();
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
    const auto version = object.value("version").toInt();
    if (parseError.error != QJsonParseError::NoError || !document.isObject()
        || (version != 1 && version != 2)) {
        setError(QStringLiteral("This is not a supported Kadron project."));
        return false;
    }

    const auto projectFile = QFileInfo(file);
    QJsonArray entries;
    if (version == 1) {
        if (!object.value("media").isString()) {
            setError(QStringLiteral("This is not a supported Kadron project."));
            return false;
        }
        entries.append(object);
    } else {
        entries = object.value("clips").toArray();
        if (entries.isEmpty() || entries.size() > 1000) {
            setError(QStringLiteral("This project has no valid clip sequence."));
            return false;
        }
    }

    QVector<Clip> parsedClips;
    for (const auto &entry : entries) {
        const auto item = entry.toObject();
        const auto relative = item.value("media").toString();
        if (relative.isEmpty()) {
            setError(QStringLiteral("This project contains an invalid clip."));
            return false;
        }
        const auto mediaPath = QDir(projectFile.absolutePath()).absoluteFilePath(relative);
        if (!QFileInfo(mediaPath).isFile()) {
            setError(QStringLiteral("Source media is missing: %1").arg(mediaPath));
            return false;
        }
        const auto duration = qMax<qint64>(0, item.value("durationMs").toVariant().toLongLong());
        const auto in = qBound<qint64>(0, item.value("inMs").toVariant().toLongLong(), duration);
        const auto out = qBound(in, item.value("outMs").toVariant().toLongLong(), duration);
        parsedClips.append({QUrl::fromLocalFile(QFileInfo(mediaPath).absoluteFilePath()), duration, in, out});
    }

    m_clips = parsedClips;
    m_activeClipIndex = qBound(0, object.value("activeIndex").toInt(), m_clips.size() - 1);
    m_projectUrl = QUrl::fromLocalFile(projectFile.absoluteFilePath());
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
    QJsonArray entries;
    for (const auto &clip : m_clips) {
        entries.append(QJsonObject{
            {"media", QDir(targetInfo.absolutePath()).relativeFilePath(clip.mediaUrl.toLocalFile())},
            {"durationMs", static_cast<double>(clip.durationMs)},
            {"inMs", static_cast<double>(clip.inMs)},
            {"outMs", static_cast<double>(clip.outMs)}
        });
    }
    QJsonObject object{{"version", 2}, {"clips", entries}, {"activeIndex", m_activeClipIndex}};
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
    auto *clip = active();
    if (!clip || value <= 0 || value == clip->durationMs)
        return;
    const auto oldDuration = clip->durationMs;
    clip->durationMs = value;
    clip->inMs = qBound<qint64>(0, clip->inMs, value);
    clip->outMs = oldDuration == 0 || clip->outMs == oldDuration ? value : qBound(clip->inMs, clip->outMs, value);
    markChanged();
}

void EditorProject::setInMs(qint64 value)
{
    auto *clip = active();
    if (!clip || clip->durationMs <= 0)
        return;
    value = qBound<qint64>(0, value, qMax<qint64>(0, clip->outMs - qMin<qint64>(100, clip->durationMs)));
    if (clip->inMs != value) {
        clip->inMs = value;
        markChanged();
    }
}

void EditorProject::setOutMs(qint64 value)
{
    auto *clip = active();
    if (!clip || clip->durationMs <= 0)
        return;
    value = qBound(clip->inMs + qMin<qint64>(100, clip->durationMs), value, clip->durationMs);
    if (clip->outMs != value) {
        clip->outMs = value;
        markChanged();
    }
}

void EditorProject::moveRange(qint64 deltaMs)
{
    auto *clip = active();
    if (!clip || clip->durationMs <= 0 || clip->outMs <= clip->inMs)
        return;
    const auto clamped = qBound(-clip->inMs, deltaMs, clip->durationMs - clip->outMs);
    if (clamped == 0)
        return;
    clip->inMs += clamped;
    clip->outMs += clamped;
    markChanged();
}
