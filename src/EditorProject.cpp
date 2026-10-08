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
#include <algorithm>
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

QVariantList EditorProject::textItems() const
{
    QVariantList result;
    for (const auto &item : m_mix.texts)
        result.append(item.toMap());
    return result;
}

QVariantList EditorProject::markers() const
{
    QVariantList result;
    for (const auto at : m_mix.markers)
        result.append(at);
    return result;
}

QVariantList EditorProject::markerItems() const
{
    QVariantList result;
    for (int i = 0; i < m_mix.markers.size(); ++i)
        result.append(QVariantMap{{"atMs", m_mix.markers.at(i)}, {"name", m_mix.markerNames.value(i)}});
    return result;
}

bool EditorProject::toggleMarker(qint64 atMs, qint64 toleranceMs)
{
    if (m_clips.isEmpty())
        return false;
    atMs = qBound<qint64>(0, atMs, sequenceDurationMs());
    for (int i = 0; i < m_mix.markers.size(); ++i) {
        if (qAbs(m_mix.markers[i] - atMs) <= toleranceMs) {
            m_mix.markers.removeAt(i);
            m_mix.markerNames.removeAt(i);
            markChanged();
            return true;
        }
    }
    if (m_mix.markers.size() >= 500)
        return false;
    const auto at = std::lower_bound(m_mix.markers.begin(), m_mix.markers.end(), atMs) - m_mix.markers.begin();
    m_mix.markers.insert(at, atMs);
    m_mix.markerNames.insert(at, QString());
    markChanged();
    return true;
}

bool EditorProject::removeMarker(int index)
{
    if (index < 0 || index >= m_mix.markers.size())
        return false;
    m_mix.markers.removeAt(index);
    m_mix.markerNames.removeAt(index);
    markChanged();
    return true;
}

void EditorProject::clearMarkers()
{
    if (m_mix.markers.isEmpty())
        return;
    m_mix.markers.clear();
    m_mix.markerNames.clear();
    markChanged();
}

bool EditorProject::setMarkerName(int index, const QString &name)
{
    if (index < 0 || index >= m_mix.markers.size())
        return false;
    const auto value = name.simplified().left(100);
    if (m_mix.markerNames.at(index) != value) {
        m_mix.markerNames[index] = value;
        markChanged();
    }
    return true;
}

QVariantList EditorProject::chapters() const
{
    QVariantList result;
    const auto total = sequenceDurationMs();
    if (m_mix.markers.isEmpty())
        return result;
    // The part before the first marker is a chapter of its own.
    const bool intro = m_mix.markers.first() > 0;
    if (intro)
        result.append(QVariantMap{{"startMs", 0}, {"title", QStringLiteral("Intro")}});
    for (int i = 0; i < m_mix.markers.size(); ++i) {
        const auto at = m_mix.markers.at(i);
        if (at >= total)
            break;
        const auto name = m_mix.markerNames.value(i);
        result.append(QVariantMap{{"startMs", at},
                                  {"title", name.isEmpty() ? QStringLiteral("Chapter %1").arg(result.size() + 1) : name}});
    }
    return result;
}

QString EditorProject::chapterList() const
{
    const auto list = chapters();
    const bool hours = sequenceDurationMs() >= 3600000;
    QStringList lines;
    for (const auto &entry : list) {
        const auto chapter = entry.toMap();
        const auto seconds = chapter.value("startMs").toLongLong() / 1000;
        const auto time = hours ? QStringLiteral("%1:%2:%3").arg(seconds / 3600).arg(seconds / 60 % 60, 2, 10, QChar('0'))
                                      .arg(seconds % 60, 2, 10, QChar('0'))
                                : QStringLiteral("%1:%2").arg(seconds / 60).arg(seconds % 60, 2, 10, QChar('0'));
        lines << time + ' ' + chapter.value("title").toString();
    }
    return lines.join('\n');
}

int EditorProject::importSubtitles(const QUrl &url, qint64 offsetMs)
{
    QFile file(url.toLocalFile());
    if (!url.isLocalFile() || !file.open(QIODevice::ReadOnly)) {
        setError(QStringLiteral("Could not read the subtitles."));
        return -1;
    }
    auto texts = TextOverlay::parseSubtitles(QString::fromUtf8(file.readAll()));
    if (texts.isEmpty()) {
        setError(QStringLiteral("No subtitles were found in this file."));
        return -1;
    }
    int added = 0;
    for (auto &text : texts) {
        if (m_mix.texts.size() >= 1000)
            break;
        text.startMs += qMax<qint64>(0, offsetMs);
        text.endMs += qMax<qint64>(0, offsetMs);
        m_mix.texts.append(text);
        ++added;
    }
    clearError();
    markChanged();
    return added;
}

QVariantList EditorProject::readSubtitles(const QUrl &url)
{
    QFile file(url.toLocalFile());
    QVariantList list;
    if (!url.isLocalFile() || !file.open(QIODevice::ReadOnly))
        return list;
    for (const auto &text : TextOverlay::parseSubtitles(QString::fromUtf8(file.readAll()))) {
        if (list.size() >= 1000)
            break;
        list << text.toMap();
    }
    return list;
}

bool EditorProject::exportSubtitles(const QUrl &url)
{
    QSaveFile file(url.toLocalFile());
    const auto data = TextOverlay::toSrt(m_mix.texts).toUtf8();
    if (!url.isLocalFile() || m_mix.texts.isEmpty() || !file.open(QIODevice::WriteOnly)
        || file.write(data) != data.size() || !file.commit()) {
        setError(QStringLiteral("Could not save the subtitles."));
        return false;
    }
    clearError();
    return true;
}

bool EditorProject::mixed() const
{
    if (m_clips.size() != 1 || !m_mix.audio.isEmpty() || !m_mix.texts.isEmpty())
        return true;
    const auto &clip = m_clips.first();
    return clip.muted || !qFuzzyCompare(clip.volume, 1.0) || !qFuzzyCompare(clip.speed, 1.0) || clip.adjusted();
}

QVariantMap EditorProject::exportOptions() const
{
    return {
        {"transition", m_mix.transition},
        {"transitionMs", m_mix.transitionMs},
        {"audio", audioItems()},
        {"musicDuck", m_mix.musicDuck},
        {"texts", textItems()},
        {"chapters", chapters()}
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

bool EditorProject::setClipRotation(int index, int degrees)
{
    if (index < 0 || index >= m_clips.size())
        return false;
    degrees = ((degrees % 360) + 360) % 360 / 90 * 90;
    auto &clip = m_clips[index];
    if (clip.rotation != degrees) {
        // The crop is in the turned frame; it does not survive a turn.
        clip.rotation = degrees;
        clip.cropX = clip.cropY = 0;
        clip.cropWidth = clip.cropHeight = 1;
        markChanged();
    }
    return true;
}

bool EditorProject::setClipCrop(int index, double x, double y, double width, double height)
{
    if (index < 0 || index >= m_clips.size())
        return false;
    width = qBound(0.05, width, 1.0);
    height = qBound(0.05, height, 1.0);
    x = qBound(0.0, x, 1.0 - width);
    y = qBound(0.0, y, 1.0 - height);
    auto &clip = m_clips[index];
    const auto same = [](double a, double b) { return qAbs(a - b) < 0.0005; };
    if (same(clip.cropX, x) && same(clip.cropY, y) && same(clip.cropWidth, width) && same(clip.cropHeight, height))
        return true;
    clip.cropX = x;
    clip.cropY = y;
    clip.cropWidth = width;
    clip.cropHeight = height;
    markChanged();
    return true;
}

bool EditorProject::setClipColor(int index, double brightness, double contrast, double saturation)
{
    if (index < 0 || index >= m_clips.size())
        return false;
    // Whole percents, so a dragged slider settles on clean values.
    const auto level = [](double value) { return qRound(qBound(-1.0, value, 1.0) * 100) / 100.0; };
    auto &clip = m_clips[index];
    if (clip.brightness == level(brightness) && clip.contrast == level(contrast) && clip.saturation == level(saturation))
        return true;
    clip.brightness = level(brightness);
    clip.contrast = level(contrast);
    clip.saturation = level(saturation);
    markChanged();
    return true;
}

bool EditorProject::insertFreeze(int index, qint64 sourceMs, qint64 holdMs)
{
    if (index < 0 || index >= m_clips.size() || m_clips.at(index).holdMs > 0 || m_clips.at(index).durationMs < 100)
        return false;
    auto &clip = m_clips[index];
    sourceMs = qBound(clip.inMs, sourceMs, clip.outMs);
    Clip still = clip;
    still.holdMs = qBound(qint64(200), qint64(holdMs), qint64(30000));
    still.inMs = qMin(sourceMs, clip.durationMs - 100);
    still.outMs = still.inMs + 100;
    still.speed = 1.0;
    int at = index + 1;
    if (sourceMs - clip.inMs < 100) {
        at = index;
    } else if (clip.outMs - sourceMs >= 100) {
        Clip right = clip;
        right.inMs = sourceMs;
        clip.outMs = sourceMs;
        m_clips.insert(index + 1, right);
    }
    m_clips.insert(at, still);
    m_activeClipIndex = at;
    clearError();
    markChanged();
    return true;
}

bool EditorProject::setClipHold(int index, qint64 holdMs)
{
    if (index < 0 || index >= m_clips.size() || m_clips.at(index).holdMs <= 0)
        return false;
    holdMs = qBound(qint64(200), qint64(holdMs), qint64(30000));
    if (m_clips[index].holdMs != holdMs) {
        m_clips[index].holdMs = holdMs;
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

bool EditorProject::saveFrame(qint64 sourceMs, const QUrl &target)
{
    if (m_activeClipIndex < 0 || m_activeClipIndex >= m_clips.size() || !target.isLocalFile())
        return false;
    const auto ffmpeg = ffmpegExecutable();
    if (ffmpeg.isEmpty()) {
        emit frameSaved(target, QStringLiteral("FFmpeg is needed to save a frame."));
        return false;
    }
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process, target](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        const bool ok = code == 0 && status == QProcess::NormalExit && QFileInfo(target.toLocalFile()).size() > 0;
        emit frameSaved(target, ok ? QString() : QStringLiteral("Could not save the frame."));
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, target](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        process->deleteLater();
        emit frameSaved(target, QStringLiteral("FFmpeg could not be started."));
    });
    process->start(ffmpeg, {"-hide_banner", "-nostdin", "-loglevel", "error", "-y",
                            "-ss", QString::number(qMax<qint64>(0, sourceMs) / 1000.0, 'f', 3),
                            "-i", m_clips.at(m_activeClipIndex).mediaUrl.toLocalFile(),
                            "-frames:v", "1", "-update", "1", target.toLocalFile()});
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
    m_activeTextIndex = -1;
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
        if (index >= 0)
            m_activeTextIndex = -1;
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

bool EditorProject::splitAudio(int index, qint64 atMs)
{
    if (index < 0 || index >= m_mix.audio.size())
        return false;
    const auto item = m_mix.audio.at(index);
    const auto offset = atMs - item.startMs;
    if (offset < 100 || item.outMs - item.inMs - offset < 100)
        return false;
    auto head = item, tail = item;
    head.outMs = item.inMs + offset;
    head.fadeInMs = qMin(item.fadeInMs, offset);
    head.fadeOutMs = 0;
    tail.startMs = atMs;
    tail.inMs = head.outMs;
    tail.fadeInMs = 0;
    tail.fadeOutMs = qMin(item.fadeOutMs, tail.outMs - tail.inMs);
    m_mix.audio[index] = head;
    m_mix.audio.insert(index + 1, tail);
    m_activeAudioIndex = index + 1;
    m_activeTextIndex = -1;
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

int EditorProject::addText(qint64 startMs)
{
    const auto total = sequenceDurationMs();
    if (m_clips.isEmpty() || total < 200)
        return -1;
    TextItem item;
    item.text = QStringLiteral("Your text");
    item.startMs = qBound<qint64>(0, startMs, total - 200);
    item.endMs = qMin(total, item.startMs + 3000);
    m_mix.texts.append(item);
    m_activeTextIndex = m_mix.texts.size() - 1;
    m_activeAudioIndex = -1;
    markChanged();
    return m_activeTextIndex;
}

bool EditorProject::selectText(int index)
{
    if (index < -1 || index >= m_mix.texts.size())
        return false;
    if (index != m_activeTextIndex) {
        m_activeTextIndex = index;
        if (index >= 0)
            m_activeAudioIndex = -1;
        emit changed();
    }
    return true;
}

bool EditorProject::setTextContent(int index, const QString &text)
{
    if (index < 0 || index >= m_mix.texts.size())
        return false;
    // Trailing blank lines would push the caption off its place.
    auto value = text.left(500);
    while (!value.isEmpty() && value.back().isSpace())
        value.chop(1);
    if (value.trimmed().isEmpty() || value == m_mix.texts[index].text)
        return !value.trimmed().isEmpty();
    m_mix.texts[index].text = value;
    markChanged();
    return true;
}

bool EditorProject::setTextPlacement(int index, qint64 startMs, qint64 endMs)
{
    if (index < 0 || index >= m_mix.texts.size())
        return false;
    startMs = qMax<qint64>(0, startMs);
    endMs = qMax(startMs + 200, endMs);
    auto &item = m_mix.texts[index];
    if (item.startMs == startMs && item.endMs == endMs)
        return true;
    item.startMs = startMs;
    item.endMs = endMs;
    markChanged();
    return true;
}

bool EditorProject::setTextStyle(int index, const QVariantMap &changes)
{
    if (index < 0 || index >= m_mix.texts.size())
        return false;
    auto merged = m_mix.texts.at(index).toMap();
    for (auto it = changes.cbegin(); it != changes.cend(); ++it) {
        if (QStringList{"x", "y", "size", "color", "font", "style"}.contains(it.key()))
            merged.insert(it.key(), it.value());
    }
    const auto item = TextOverlay::fromMap(merged);
    auto &current = m_mix.texts[index];
    if (item.x == current.x && item.y == current.y && item.size == current.size
        && item.color == current.color && item.font == current.font && item.style == current.style)
        return true;
    current = item;
    markChanged();
    return true;
}

bool EditorProject::splitText(int index, qint64 atMs)
{
    if (index < 0 || index >= m_mix.texts.size())
        return false;
    const auto item = m_mix.texts.at(index);
    if (atMs - item.startMs < 200 || item.endMs - atMs < 200)
        return false;
    auto tail = item;
    m_mix.texts[index].endMs = atMs;
    tail.startMs = atMs;
    m_mix.texts.insert(index + 1, tail);
    m_activeTextIndex = index + 1;
    m_activeAudioIndex = -1;
    markChanged();
    return true;
}

int EditorProject::duplicateText(int index)
{
    if (index < 0 || index >= m_mix.texts.size())
        return -1;
    auto copy = m_mix.texts.at(index);
    const auto length = copy.endMs - copy.startMs;
    const auto total = sequenceDurationMs();
    if (copy.endMs + qMin<qint64>(length, 200) <= total) {
        copy.startMs = copy.endMs;
        copy.endMs = qMin(total, copy.startMs + length);
    }
    m_mix.texts.insert(index + 1, copy);
    m_activeTextIndex = index + 1;
    m_activeAudioIndex = -1;
    markChanged();
    return m_activeTextIndex;
}

bool EditorProject::removeText(int index)
{
    if (index < 0 || index >= m_mix.texts.size())
        return false;
    m_mix.texts.removeAt(index);
    if (m_activeTextIndex >= m_mix.texts.size() || m_activeTextIndex == index)
        m_activeTextIndex = -1;
    else if (m_activeTextIndex > index)
        --m_activeTextIndex;
    markChanged();
    return true;
}

EditorProject::Snapshot EditorProject::snapshot() const { return {m_clips, m_activeClipIndex, m_mix}; }

void EditorProject::restore(const Snapshot &state)
{
    m_clips = state.clips;
    m_activeClipIndex = state.activeIndex;
    m_mix = state.mix;
    if (m_activeAudioIndex >= m_mix.audio.size())
        m_activeAudioIndex = -1;
    if (m_activeTextIndex >= m_mix.texts.size())
        m_activeTextIndex = -1;
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
    m_activeTextIndex = -1;
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
            {"speed", clip.speed},
            {"holdMs", clip.holdMs},
            {"rotation", clip.rotation},
            {"cropX", clip.cropX},
            {"cropY", clip.cropY},
            {"cropWidth", clip.cropWidth},
            {"cropHeight", clip.cropHeight},
            {"brightness", clip.brightness},
            {"contrast", clip.contrast},
            {"saturation", clip.saturation}
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
    m_activeTextIndex = -1;
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
    if (clip && clip->holdMs > 0) {
        setError(QStringLiteral("A still frame cannot be split; change how long it holds instead."));
        return false;
    }
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
        || version < 1 || version > 6) {
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
        const auto hold = item.value("holdMs").toVariant().toLongLong();
        if (hold > 0)
            clip.holdMs = qBound(qint64(200), qint64(hold), qint64(30000));
        clip.rotation = ((item.value("rotation").toInt() % 360) + 360) % 360 / 90 * 90;
        const auto crop = item.value("crop").toArray();
        if (crop.size() == 4) {
            clip.cropWidth = qBound(0.05, crop.at(2).toDouble(1), 1.0);
            clip.cropHeight = qBound(0.05, crop.at(3).toDouble(1), 1.0);
            clip.cropX = qBound(0.0, crop.at(0).toDouble(), 1.0 - clip.cropWidth);
            clip.cropY = qBound(0.0, crop.at(1).toDouble(), 1.0 - clip.cropHeight);
        }
        clip.brightness = qBound(-1.0, item.value("brightness").toDouble(), 1.0);
        clip.contrast = qBound(-1.0, item.value("contrast").toDouble(), 1.0);
        clip.saturation = qBound(-1.0, item.value("saturation").toDouble(), 1.0);
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
    for (const auto &entry : object.value("texts").toArray()) {
        const auto item = entry.toObject();
        // Older projects keep a position and a size name; fromMap maps them.
        auto text = TextOverlay::fromMap(item.toVariantMap());
        text.startMs = qMax<qint64>(0, text.startMs);
        text.endMs = qMax(text.startMs + 200, text.endMs);
        if (!text.text.trimmed().isEmpty())
            mix.texts.append(text);
        if (mix.texts.size() > 1000)
            break;
    }
    // Plain times, or {atMs, name} once a marker has a name.
    QList<QPair<qint64, QString>> markers;
    for (const auto &entry : object.value("markers").toArray()) {
        if (entry.isObject())
            markers.append({qMax<qint64>(0, entry.toObject().value("atMs").toVariant().toLongLong()),
                            entry.toObject().value("name").toString().simplified().left(100)});
        else
            markers.append({qMax<qint64>(0, entry.toVariant().toLongLong()), QString()});
        if (markers.size() >= 500)
            break;
    }
    std::stable_sort(markers.begin(), markers.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
    for (const auto &marker : std::as_const(markers)) {
        mix.markers.append(marker.first);
        mix.markerNames.append(marker.second);
    }

    m_clips = parsedClips;
    m_mix = mix;
    m_activeClipIndex = qBound(0, object.value("activeIndex").toInt(), m_clips.size() - 1);
    m_activeAudioIndex = -1;
    m_activeTextIndex = -1;
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
        // Only what differs from a plain clip, so older Kadron still opens the project.
        auto object = entries.last().toObject();
        if (clip.holdMs > 0)
            object.insert("holdMs", static_cast<double>(clip.holdMs));
        if (clip.rotation != 0)
            object.insert("rotation", clip.rotation);
        if (clip.cropX > 0 || clip.cropY > 0 || clip.cropWidth < 1 || clip.cropHeight < 1)
            object.insert("crop", QJsonArray{clip.cropX, clip.cropY, clip.cropWidth, clip.cropHeight});
        if (clip.brightness != 0 || clip.contrast != 0 || clip.saturation != 0) {
            object.insert("brightness", clip.brightness);
            object.insert("contrast", clip.contrast);
            object.insert("saturation", clip.saturation);
        }
        entries.replace(entries.size() - 1, object);
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
    QJsonArray textEntries;
    for (const auto &item : m_mix.texts) {
        textEntries.append(QJsonObject{
            {"text", item.text},
            {"startMs", static_cast<double>(item.startMs)},
            {"endMs", static_cast<double>(item.endMs)},
            {"x", item.x},
            {"y", item.y},
            {"size", item.size},
            {"color", item.color},
            {"font", item.font},
            {"style", item.style}
        });
    }
    // Version 6 only when there are captions, so older Kadron still opens the rest.
    QJsonObject object{{"version", textEntries.isEmpty() ? 5 : 6}, {"clips", entries}, {"activeIndex", m_activeClipIndex},
                       {"transition", m_mix.transition}, {"transitionMs", m_mix.transitionMs},
                       {"audio", audioEntries}, {"duck", m_mix.musicDuck}};
    if (!textEntries.isEmpty())
        object.insert("texts", textEntries);
    if (!m_mix.markers.isEmpty()) {
        QJsonArray markerEntries;
        for (int i = 0; i < m_mix.markers.size(); ++i) {
            const auto name = m_mix.markerNames.value(i);
            if (name.isEmpty())
                markerEntries.append(static_cast<double>(m_mix.markers.at(i)));
            else
                markerEntries.append(QJsonObject{{"atMs", static_cast<double>(m_mix.markers.at(i))}, {"name", name}});
        }
        object.insert("markers", markerEntries);
    }
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
