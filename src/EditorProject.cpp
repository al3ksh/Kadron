#include "EditorProject.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QtGlobal>
#include <limits>
#include <QProcess>
#include "MediaTools.h"

EditorProject::EditorProject(QObject *parent) : QObject(parent)
{
    m_autosave.setSingleShot(true);
    m_autosave.setInterval(60 * 1000);
    connect(&m_autosave, &QTimer::timeout, this, &EditorProject::autosaveNow);
}

void EditorProject::setRecoveryPath(const QString &path) { m_recoveryPath = path; }

void EditorProject::autosaveNow()
{
    m_autosave.stop();
    if (m_recoveryPath.isEmpty() || !m_dirty || !hasMedia())
        return;
    const QFileInfo info(m_recoveryPath);
    QDir().mkpath(info.absolutePath());
    auto object = QJsonDocument::fromJson(serialize(info.absolutePath())).object();
    object.insert("origin", m_projectUrl.toLocalFile());
    object.insert("savedAt", QDateTime::currentDateTime().toString(Qt::ISODate));
    QSaveFile file(info.absoluteFilePath());
    if (file.open(QIODevice::WriteOnly) && file.write(QJsonDocument(object).toJson(QJsonDocument::Compact)) >= 0)
        file.commit();
}

QVariantMap EditorProject::recoveryInfo() const
{
    if (m_recoveryPath.isEmpty())
        return {};
    QFile file(m_recoveryPath);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const auto object = QJsonDocument::fromJson(file.readAll()).object();
    const auto clips = object.value("clips").toArray();
    if (clips.isEmpty())
        return {};
    const auto origin = object.value("origin").toString();
    return {
        {"name", origin.isEmpty() ? QFileInfo(clips.first().toObject().value("media").toString()).fileName() : QFileInfo(origin).fileName()},
        {"savedAt", QDateTime::fromString(object.value("savedAt").toString(), Qt::ISODate).toString("d MMM, HH:mm")},
        {"clipCount", clips.size()}
    };
}

bool EditorProject::restoreRecovery()
{
    if (m_recoveryPath.isEmpty() || !QFileInfo(m_recoveryPath).isFile())
        return false;
    QFile file(m_recoveryPath);
    QString origin;
    if (file.open(QIODevice::ReadOnly))
        origin = QJsonDocument::fromJson(file.readAll()).object().value("origin").toString();
    file.close();
    if (!openProject(QUrl::fromLocalFile(m_recoveryPath)))
        return false;
    m_projectUrl = origin.isEmpty() ? QUrl() : QUrl::fromLocalFile(origin);
    m_dirty = true;
    emit changed();
    return true;
}

void EditorProject::discardRecovery()
{
    m_autosave.stop();
    if (!m_recoveryPath.isEmpty())
        QFile::remove(m_recoveryPath);
}

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
bool EditorProject::canUndo() const { return !m_undo.isEmpty(); }
bool EditorProject::canRedo() const { return !m_redo.isEmpty(); }

QString EditorProject::transition() const { return m_mix.transition; }
int EditorProject::transitionMs() const { return m_mix.transitionMs; }
int EditorProject::audioCount() const { return m_mix.audio.size(); }
int EditorProject::activeAudioIndex() const { return m_activeAudioIndex; }
bool EditorProject::musicDuck() const { return m_mix.musicDuck; }

QVariantList EditorProject::audioItems() const
{
    QVariantList result;
    for (const auto &item : m_mix.audio) {
        result.append(QVariantMap{
            {"url", item.mediaUrl},
            {"name", QFileInfo(item.mediaUrl.toLocalFile()).fileName()},
            {"durationMs", item.durationMs},
            {"startMs", item.startMs},
            {"inMs", item.inMs},
            {"outMs", item.outMs},
            {"lengthMs", qMax<qint64>(0, item.outMs - item.inMs)},
            {"volume", item.volume},
            {"fadeInMs", item.fadeInMs},
            {"fadeOutMs", item.fadeOutMs}
        });
    }
    return result;
}

bool EditorProject::mixed() const
{
    if (m_clips.size() != 1 || !m_mix.audio.isEmpty())
        return true;
    const auto &clip = m_clips.first();
    return clip.muted || !qFuzzyCompare(clip.volume, 1.0) || !qFuzzyCompare(clip.speed, 1.0);
}

QVariantMap EditorProject::exportOptions() const
{
    return {
        {"transition", m_mix.transition},
        {"transitionMs", m_mix.transitionMs},
        {"audio", audioItems()},
        {"musicDuck", m_mix.musicDuck}
    };
}

bool EditorProject::setClipVolume(int index, double volume)
{
    if (index < 0 || index >= m_clips.size())
        return false;
    volume = qBound(0.0, volume, 2.0);
    auto &clip = m_clips[index];
    if (qFuzzyCompare(clip.volume + 1, volume + 1) && !clip.muted)
        return true;
    clip.volume = volume;
    clip.muted = false;
    markChanged();
    return true;
}

bool EditorProject::setClipMuted(int index, bool muted)
{
    if (index < 0 || index >= m_clips.size())
        return false;
    if (m_clips[index].muted != muted) {
        m_clips[index].muted = muted;
        markChanged();
    }
    return true;
}

bool EditorProject::setClipSpeed(int index, double speed)
{
    if (index < 0 || index >= m_clips.size())
        return false;
    speed = qBound(0.25, speed, 4.0);
    if (!qFuzzyCompare(m_clips[index].speed, speed)) {
        m_clips[index].speed = speed;
        markChanged();
    }
    return true;
}

bool EditorProject::replaceClipRanges(int index, const QVariantList &ranges)
{
    if (index < 0 || index >= m_clips.size() || ranges.isEmpty())
        return false;
    const auto source = m_clips.at(index);
    QList<Clip> parts;
    for (const auto &value : ranges) {
        const auto range = value.toMap();
        Clip part = source;
        part.inMs = qBound<qint64>(0, range.value("inMs").toLongLong(), source.durationMs);
        part.outMs = qBound<qint64>(part.inMs, range.value("outMs").toLongLong(), source.durationMs);
        if (part.outMs - part.inMs >= 100)
            parts.append(part);
    }
    if (parts.isEmpty())
        return false;
    m_clips.removeAt(index);
    for (int i = 0; i < parts.size(); ++i)
        m_clips.insert(index + i, parts.at(i));
    m_activeClipIndex = index;
    clearError();
    markChanged();
    return true;
}

QList<QPair<qint64, qint64>> EditorProject::parseSilence(const QString &log, qint64 offsetMs, qint64 endMs)
{
    QList<QPair<qint64, qint64>> result;
    qint64 start = -1;
    for (const auto &line : log.split(QLatin1Char('\n'))) {
        const auto startAt = line.indexOf(QLatin1String("silence_start:"));
        const auto endAt = line.indexOf(QLatin1String("silence_end:"));
        if (startAt >= 0) {
            start = offsetMs + qRound64(qMax(0.0, line.mid(startAt + 14).trimmed().section(' ', 0, 0).toDouble()) * 1000.0);
        } else if (endAt >= 0 && start >= 0) {
            const auto end = offsetMs + qRound64(line.mid(endAt + 12).trimmed().section(' ', 0, 0).toDouble() * 1000.0);
            result.append({start, qMin(end, endMs)});
            start = -1;
        }
    }
    if (start >= 0 && start < endMs)
        result.append({start, endMs});
    return result;
}

QVariantList EditorProject::keepRanges(qint64 inMs, qint64 outMs, const QList<QPair<qint64, qint64>> &silences, qint64 padMs)
{
    QVariantList result;
    auto cursor = inMs;
    for (const auto &silence : silences) {
        const auto cutFrom = qMax(cursor, silence.first + (silence.first <= inMs ? 0 : padMs));
        const auto cutTo = qMin(outMs, silence.second - (silence.second >= outMs ? 0 : padMs));
        if (cutTo - cutFrom < 100)
            continue;
        if (cutFrom - cursor >= 100)
            result.append(QVariantMap{{"inMs", cursor}, {"outMs", cutFrom}});
        cursor = cutTo;
    }
    if (outMs - cursor >= 100)
        result.append(QVariantMap{{"inMs", cursor}, {"outMs", outMs}});
    return result;
}

bool EditorProject::removeSilence(int index, double thresholdDb, int minMs)
{
    if (index < 0 || index >= m_clips.size() || m_findingSilence)
        return false;
    const auto ffmpeg = ffmpegExecutable();
    if (ffmpeg.isEmpty()) {
        setError(QStringLiteral("FFmpeg is needed to find silence."));
        return false;
    }
    const auto clip = m_clips.at(index);
    auto *process = new QProcess(this);
    m_findingSilence = true;
    emit findingSilenceChanged();
    connect(process, &QProcess::finished, this, [this, process, index, clip](int code, QProcess::ExitStatus status) {
        const auto log = QString::fromUtf8(process->readAllStandardError());
        process->deleteLater();
        m_findingSilence = false;
        emit findingSilenceChanged();
        // The clip may have been edited meanwhile; only cut what was measured.
        if (index >= m_clips.size() || m_clips.at(index).mediaUrl != clip.mediaUrl
            || m_clips.at(index).inMs != clip.inMs || m_clips.at(index).outMs != clip.outMs)
            return;
        if (code != 0 || status != QProcess::NormalExit) {
            setError(QStringLiteral("Could not read the clip's audio."));
            return;
        }
        const auto ranges = keepRanges(clip.inMs, clip.outMs, parseSilence(log, clip.inMs, clip.outMs));
        qint64 kept = 0;
        for (const auto &range : ranges)
            kept += range.toMap().value("outMs").toLongLong() - range.toMap().value("inMs").toLongLong();
        const auto removed = (clip.outMs - clip.inMs) - kept;
        if (ranges.isEmpty() || removed < 100) {
            emit silenceRemoved(0, 0);
            return;
        }
        replaceClipRanges(index, ranges);
        emit silenceRemoved(ranges.size(), removed);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        m_findingSilence = false;
        emit findingSilenceChanged();
        setError(QStringLiteral("FFmpeg could not be started."));
    });
    process->start(ffmpeg, {"-hide_banner", "-nostdin", "-vn",
                            "-ss", QString::number(clip.inMs / 1000.0, 'f', 3),
                            "-t", QString::number((clip.outMs - clip.inMs) / 1000.0, 'f', 3),
                            "-i", clip.mediaUrl.toLocalFile(),
                            "-af", QStringLiteral("silencedetect=noise=%1dB:d=%2").arg(thresholdDb).arg(minMs / 1000.0, 0, 'f', 2),
                            "-f", "null", "-"});
    return true;
}

bool EditorProject::setTransition(const QString &kind)
{
    if (kind != "cut" && kind != "fade" && kind != "crossfade")
        return false;
    if (m_mix.transition != kind) {
        m_mix.transition = kind;
        markChanged();
    }
    return true;
}

void EditorProject::setTransitionMs(int value)
{
    value = qBound(100, value, 3000);
    if (m_mix.transitionMs != value) {
        m_mix.transitionMs = value;
        markChanged();
    }
}

int EditorProject::addAudio(const QUrl &url, qint64 startMs)
{
    if (!validMedia(url))
        return -1;
    AudioItem item;
    item.mediaUrl = QUrl::fromLocalFile(QFileInfo(url.toLocalFile()).absoluteFilePath());
    item.startMs = qMax<qint64>(0, startMs);
    for (const auto &existing : std::as_const(m_mix.audio)) {
        if (existing.mediaUrl == item.mediaUrl && existing.durationMs > 0) {
            item.durationMs = existing.durationMs;
            item.outMs = existing.durationMs;
            break;
        }
    }
    if (item.durationMs <= 0) {
        // Known at once, so several files dropped together can line up.
        const auto ffprobe = ffprobeExecutable();
        QProcess probe;
        if (!ffprobe.isEmpty()) {
            probe.start(ffprobe, {"-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", item.mediaUrl.toLocalFile()});
            bool ok = false;
            const auto seconds = probe.waitForFinished(5000) ? QString::fromUtf8(probe.readAllStandardOutput()).trimmed().section('\n', 0, 0).toDouble(&ok) : 0.0;
            if (ok && seconds > 0) {
                item.durationMs = qRound64(seconds * 1000.0);
                item.outMs = item.durationMs;
            }
        }
    }
    m_mix.audio.append(item);
    m_activeAudioIndex = m_mix.audio.size() - 1;
    clearError();
    markChanged();
    probeDurations();
    return m_activeAudioIndex;
}

bool EditorProject::selectAudio(int index)
{
    if (index < -1 || index >= m_mix.audio.size())
        return false;
    if (index != m_activeAudioIndex) {
        m_activeAudioIndex = index;
        emit changed();
    }
    return true;
}

bool EditorProject::setAudioPlacement(int index, qint64 startMs, qint64 inMs, qint64 outMs)
{
    if (index < 0 || index >= m_mix.audio.size())
        return false;
    auto &item = m_mix.audio[index];
    startMs = qMax<qint64>(0, startMs);
    if (item.durationMs > 0) {
        const auto minimum = qMin<qint64>(100, item.durationMs);
        inMs = qBound<qint64>(0, inMs, item.durationMs - minimum);
        outMs = qBound<qint64>(inMs + minimum, outMs, item.durationMs);
    } else {
        inMs = item.inMs;
        outMs = item.outMs;
    }
    if (item.startMs == startMs && item.inMs == inMs && item.outMs == outMs)
        return true;
    item.startMs = startMs;
    item.inMs = inMs;
    item.outMs = outMs;
    // Fades never outgrow a shortened item.
    item.fadeInMs = qMin(item.fadeInMs, outMs - inMs);
    item.fadeOutMs = qMin(item.fadeOutMs, outMs - inMs - item.fadeInMs);
    clearError();
    markChanged();
    return true;
}

bool EditorProject::setAudioVolume(int index, double volume)
{
    if (index < 0 || index >= m_mix.audio.size())
        return false;
    volume = qBound(0.0, volume, 2.0);
    if (!qFuzzyCompare(m_mix.audio[index].volume + 1, volume + 1)) {
        m_mix.audio[index].volume = volume;
        markChanged();
    }
    return true;
}

bool EditorProject::setAudioFades(int index, qint64 fadeInMs, qint64 fadeOutMs)
{
    if (index < 0 || index >= m_mix.audio.size())
        return false;
    auto &item = m_mix.audio[index];
    const auto length = qMax<qint64>(0, item.outMs - item.inMs);
    fadeInMs = qBound<qint64>(0, fadeInMs, length);
    fadeOutMs = qBound<qint64>(0, fadeOutMs, length - fadeInMs);
    if (item.fadeInMs == fadeInMs && item.fadeOutMs == fadeOutMs)
        return true;
    item.fadeInMs = fadeInMs;
    item.fadeOutMs = fadeOutMs;
    markChanged();
    return true;
}

bool EditorProject::removeAudio(int index)
{
    if (index < 0 || index >= m_mix.audio.size())
        return false;
    m_mix.audio.removeAt(index);
    if (m_activeAudioIndex >= m_mix.audio.size() || m_activeAudioIndex == index)
        m_activeAudioIndex = -1;
    else if (m_activeAudioIndex > index)
        --m_activeAudioIndex;
    markChanged();
    return true;
}

void EditorProject::setMusicDuck(bool value)
{
    if (m_mix.musicDuck != value) {
        m_mix.musicDuck = value;
        markChanged();
    }
}

EditorProject::Snapshot EditorProject::snapshot() const { return {m_clips, m_activeClipIndex, m_mix}; }

void EditorProject::restore(const Snapshot &state)
{
    m_clips = state.clips;
    m_activeClipIndex = state.activeIndex;
    m_mix = state.mix;
    if (m_activeAudioIndex >= m_mix.audio.size())
        m_activeAudioIndex = -1;
    m_baseline = state;
    m_dirty = true;
    clearError();
    emit changed();
}

void EditorProject::closeProject()
{
    m_clips.clear();
    m_activeClipIndex = -1;
    m_activeAudioIndex = -1;
    m_mix = {};
    m_projectUrl.clear();
    m_dirty = false;
    m_probing.clear();
    resetHistory();
    discardRecovery();
    clearError();
    emit changed();
}

void EditorProject::resetHistory()
{
    m_undo.clear();
    m_redo.clear();
    m_baseline = snapshot();
}

bool EditorProject::undo()
{
    if (m_undo.isEmpty())
        return false;
    m_redo.append(snapshot());
    restore(m_undo.takeLast());
    return true;
}

bool EditorProject::redo()
{
    if (m_redo.isEmpty())
        return false;
    m_undo.append(snapshot());
    restore(m_redo.takeLast());
    return true;
}
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
            {"lengthMs", clip.lengthMs()},
            {"volume", clip.volume},
            {"muted", clip.muted},
            {"speed", clip.speed}
        });
    }
    return result;
}

qint64 EditorProject::sequenceDurationMs() const
{
    qint64 total = 0;
    for (const auto &clip : m_clips)
        total += clip.lengthMs();
    return total;
}

bool EditorProject::canExport() const
{
    if (m_clips.isEmpty())
        return false;
    for (const auto &item : m_mix.audio) {
        if (!QFileInfo(item.mediaUrl.toLocalFile()).isFile() || item.durationMs <= 0 || item.outMs - item.inMs < 100)
            return false;
    }
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
    m_undo.append(m_baseline);
    if (m_undo.size() > 200)
        m_undo.removeFirst();
    m_redo.clear();
    m_baseline = snapshot();
    if (!m_recoveryPath.isEmpty() && !m_autosave.isActive())
        m_autosave.start();
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
    m_activeAudioIndex = -1;
    m_mix = {};
    m_projectUrl = QUrl();
    markChanged();
    resetHistory();
    probeDurations();
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
    probeDurations();
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
        || version < 1 || version > 5) {
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
        Clip clip{QUrl::fromLocalFile(QFileInfo(mediaPath).absoluteFilePath()), duration, in, out};
        clip.volume = qBound(0.0, item.value("volume").toDouble(1.0), 2.0);
        clip.muted = item.value("muted").toBool(false);
        clip.speed = qBound(0.25, item.value("speed").toDouble(1.0), 4.0);
        parsedClips.append(clip);
    }

    Mix mix;
    const auto kind = object.value("transition").toString();
    if (kind == "fade" || kind == "crossfade")
        mix.transition = kind;
    mix.transitionMs = qBound(100, object.value("transitionMs").toInt(500), 3000);
    QJsonArray audioEntries = object.value("audio").toArray();
    mix.musicDuck = object.value("duck").toBool(true);
    // Version 3 had one music file under the whole sequence.
    const auto music = object.value("music").toObject();
    if (!music.isEmpty()) {
        audioEntries = {QJsonObject{{"media", music.value("media")}, {"volume", music.value("volume").toDouble(0.35)}}};
        mix.musicDuck = music.value("duck").toBool(true);
    }
    for (const auto &entry : std::as_const(audioEntries)) {
        const auto item = entry.toObject();
        const auto relative = item.value("media").toString();
        const auto audioPath = QDir(projectFile.absolutePath()).absoluteFilePath(relative);
        if (relative.isEmpty() || !QFileInfo(audioPath).isFile()) {
            setError(QStringLiteral("Audio is missing: %1").arg(audioPath));
            return false;
        }
        AudioItem audio;
        audio.mediaUrl = QUrl::fromLocalFile(QFileInfo(audioPath).absoluteFilePath());
        audio.durationMs = qMax<qint64>(0, item.value("durationMs").toVariant().toLongLong());
        audio.startMs = qMax<qint64>(0, item.value("startMs").toVariant().toLongLong());
        audio.inMs = qBound<qint64>(0, item.value("inMs").toVariant().toLongLong(), audio.durationMs);
        audio.outMs = qBound(audio.inMs, item.value("outMs").toVariant().toLongLong(), audio.durationMs);
        audio.volume = qBound(0.0, item.value("volume").toDouble(0.5), 2.0);
        // Unknown until probed; the fades are kept as saved until then.
        const auto length = audio.durationMs > 0 ? audio.outMs - audio.inMs : std::numeric_limits<qint64>::max() / 4;
        audio.fadeInMs = qBound<qint64>(0, item.value("fadeInMs").toVariant().toLongLong(), length);
        audio.fadeOutMs = qBound<qint64>(0, item.value("fadeOutMs").toVariant().toLongLong(), length - audio.fadeInMs);
        mix.audio.append(audio);
        if (mix.audio.size() > 1000)
            break;
    }

    m_clips = parsedClips;
    m_mix = mix;
    m_activeClipIndex = qBound(0, object.value("activeIndex").toInt(), m_clips.size() - 1);
    m_activeAudioIndex = -1;
    m_projectUrl = QUrl::fromLocalFile(projectFile.absoluteFilePath());
    m_dirty = false;
    resetHistory();
    clearError();
    emit changed();
    probeDurations();
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
    QSaveFile file(targetInfo.absoluteFilePath());
    if (!file.open(QIODevice::WriteOnly)
        || file.write(serialize(targetInfo.absolutePath())) < 0
        || !file.commit()) {
        setError(QStringLiteral("Could not save the project: %1").arg(file.errorString()));
        return false;
    }
    m_projectUrl = QUrl::fromLocalFile(targetInfo.absoluteFilePath());
    m_dirty = false;
    discardRecovery();
    clearError();
    emit changed();
    return true;
}

QByteArray EditorProject::serialize(const QString &directory) const
{
    const QDir base(directory);
    QJsonArray entries;
    for (const auto &clip : m_clips) {
        entries.append(QJsonObject{
            {"media", base.relativeFilePath(clip.mediaUrl.toLocalFile())},
            {"durationMs", static_cast<double>(clip.durationMs)},
            {"inMs", static_cast<double>(clip.inMs)},
            {"outMs", static_cast<double>(clip.outMs)},
            {"volume", clip.volume},
            {"muted", clip.muted},
            {"speed", clip.speed}
        });
    }
    QJsonArray audioEntries;
    for (const auto &item : m_mix.audio) {
        audioEntries.append(QJsonObject{
            {"media", base.relativeFilePath(item.mediaUrl.toLocalFile())},
            {"durationMs", static_cast<double>(item.durationMs)},
            {"startMs", static_cast<double>(item.startMs)},
            {"inMs", static_cast<double>(item.inMs)},
            {"outMs", static_cast<double>(item.outMs)},
            {"volume", item.volume},
            {"fadeInMs", static_cast<double>(item.fadeInMs)},
            {"fadeOutMs", static_cast<double>(item.fadeOutMs)}
        });
    }
    QJsonObject object{{"version", 5}, {"clips", entries}, {"activeIndex", m_activeClipIndex},
                       {"transition", m_mix.transition}, {"transitionMs", m_mix.transitionMs},
                       {"audio", audioEntries}, {"duck", m_mix.musicDuck}};
    return QJsonDocument(object).toJson(QJsonDocument::Indented);
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
    m_dirty = true;
    m_baseline = snapshot();
    emit changed();
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

bool EditorProject::moveClipTo(int from, int to)
{
    if (from < 0 || from >= m_clips.size() || to < 0 || to >= m_clips.size())
        return false;
    if (from == to)
        return true;
    const auto activeUrlIndex = m_activeClipIndex;
    m_clips.move(from, to);
    if (activeUrlIndex == from)
        m_activeClipIndex = to;
    else if (from < activeUrlIndex && to >= activeUrlIndex)
        --m_activeClipIndex;
    else if (from > activeUrlIndex && to <= activeUrlIndex)
        ++m_activeClipIndex;
    clearError();
    markChanged();
    return true;
}

bool EditorProject::setClipRange(int index, qint64 inMs, qint64 outMs)
{
    if (index < 0 || index >= m_clips.size())
        return false;
    auto &clip = m_clips[index];
    if (clip.durationMs <= 0)
        return false;
    const auto minimum = qMin<qint64>(100, clip.durationMs);
    inMs = qBound<qint64>(0, inMs, clip.durationMs - minimum);
    outMs = qBound<qint64>(inMs + minimum, outMs, clip.durationMs);
    if (clip.inMs == inMs && clip.outMs == outMs)
        return true;
    clip.inMs = inMs;
    clip.outMs = outMs;
    clearError();
    markChanged();
    return true;
}

bool EditorProject::duplicateClip(int index)
{
    if (index < 0 || index >= m_clips.size())
        return false;
    m_clips.insert(index + 1, m_clips.at(index));
    m_activeClipIndex = index + 1;
    clearError();
    markChanged();
    return true;
}

void EditorProject::probeDurations()
{
    const auto ffprobe = ffprobeExecutable();
    if (ffprobe.isEmpty())
        return;
    QList<QUrl> pending;
    for (const auto &clip : std::as_const(m_clips))
        if (clip.durationMs <= 0) pending << clip.mediaUrl;
    for (const auto &item : std::as_const(m_mix.audio))
        if (item.durationMs <= 0) pending << item.mediaUrl;
    for (const auto &url : std::as_const(pending)) {
        if (m_probing.contains(url))
            continue;
        m_probing.insert(url);
        auto *process = new QProcess(this);
        connect(process, &QProcess::finished, this, [this, process, url](int code, QProcess::ExitStatus status) {
            m_probing.remove(url);
            const auto text = QString::fromUtf8(process->readAllStandardOutput()).trimmed();
            process->deleteLater();
            bool ok = false;
            const auto seconds = text.section('\n', 0, 0).toDouble(&ok);
            if (code == 0 && status == QProcess::NormalExit && ok && seconds > 0)
                applyProbedDuration(url, qRound64(seconds * 1000.0));
        });
        connect(process, &QProcess::errorOccurred, this, [this, process, url](QProcess::ProcessError error) {
            if (error != QProcess::FailedToStart)
                return;
            m_probing.remove(url);
            process->deleteLater();
        });
        process->start(ffprobe, {"-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", url.toLocalFile()});
    }
}

void EditorProject::applyProbedDuration(const QUrl &url, qint64 durationMs)
{
    bool touched = false;
    for (auto &clip : m_clips) {
        if (clip.mediaUrl != url || clip.durationMs > 0)
            continue;
        clip.durationMs = durationMs;
        clip.inMs = qBound<qint64>(0, clip.inMs, durationMs);
        clip.outMs = clip.outMs <= clip.inMs ? durationMs : qBound(clip.inMs, clip.outMs, durationMs);
        touched = true;
    }
    const auto fillAudio = [url, durationMs](QVector<AudioItem> &items) {
        bool filled = false;
        for (auto &item : items) {
            if (item.mediaUrl != url || item.durationMs > 0)
                continue;
            item.durationMs = durationMs;
            item.inMs = qBound<qint64>(0, item.inMs, durationMs);
            item.outMs = item.outMs <= item.inMs ? durationMs : qBound(item.inMs, item.outMs, durationMs);
            item.fadeInMs = qMin(item.fadeInMs, item.outMs - item.inMs);
            item.fadeOutMs = qMin(item.fadeOutMs, item.outMs - item.inMs - item.fadeInMs);
            filled = true;
        }
        return filled;
    };
    touched = fillAudio(m_mix.audio) || touched;
    if (touched) {
        // Durations are facts about the media, not edits: fold them into history.
        m_baseline = snapshot();
        for (auto *stack : {&m_undo, &m_redo})
            for (auto &state : *stack)
                for (auto &clip : state.clips)
                    if (clip.mediaUrl == url && clip.durationMs <= 0) {
                        clip.durationMs = durationMs;
                        clip.outMs = clip.outMs <= clip.inMs ? durationMs : qMin(clip.outMs, durationMs);
                    }
        for (auto *stack : {&m_undo, &m_redo})
            for (auto &state : *stack)
                fillAudio(state.mix.audio);
        emit changed();
    }
}
