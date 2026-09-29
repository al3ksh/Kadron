#pragma once

#include "TextOverlay.h"

#include <QObject>
#include <QTimer>
#include <QUrl>
#include <QFileInfo>
#include <QVariantList>
#include <QVector>
#include <QSet>

class EditorProject final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl mediaUrl READ mediaUrl NOTIFY changed)
    Q_PROPERTY(QString mediaName READ mediaName NOTIFY changed)
    Q_PROPERTY(QUrl projectUrl READ projectUrl NOTIFY changed)
    Q_PROPERTY(qint64 durationMs READ durationMs NOTIFY changed)
    Q_PROPERTY(qint64 inMs READ inMs NOTIFY changed)
    Q_PROPERTY(qint64 outMs READ outMs NOTIFY changed)
    Q_PROPERTY(QVariantList clips READ clips NOTIFY changed)
    Q_PROPERTY(int clipCount READ clipCount NOTIFY changed)
    Q_PROPERTY(int activeClipIndex READ activeClipIndex NOTIFY changed)
    Q_PROPERTY(qint64 sequenceDurationMs READ sequenceDurationMs NOTIFY changed)
    Q_PROPERTY(bool canExport READ canExport NOTIFY changed)
    Q_PROPERTY(bool hasMedia READ hasMedia NOTIFY changed)
    Q_PROPERTY(bool dirty READ dirty NOTIFY changed)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY changed)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY errorTextChanged)
    // How clips meet: "cut", "fade" (through black) or "crossfade".
    Q_PROPERTY(QString transition READ transition NOTIFY changed)
    Q_PROPERTY(int transitionMs READ transitionMs NOTIFY changed)
    // The audio track under the clips: music or sounds, each placed at a
    // sequence time and trimmed like a clip.
    Q_PROPERTY(QVariantList audioItems READ audioItems NOTIFY changed)
    Q_PROPERTY(int audioCount READ audioCount NOTIFY changed)
    Q_PROPERTY(int activeAudioIndex READ activeAudioIndex NOTIFY changed)
    // Lower the audio track while the clips have sound (speech).
    Q_PROPERTY(bool musicDuck READ musicDuck NOTIFY changed)
    // Captions over the video, each shown from startMs to endMs of the sequence.
    Q_PROPERTY(QVariantList textItems READ textItems NOTIFY changed)
    Q_PROPERTY(int activeTextIndex READ activeTextIndex NOTIFY changed)
    // Whether an export needs the full sequence pipeline rather than a plain trim.
    Q_PROPERTY(bool mixed READ mixed NOTIFY changed)
    // True while quiet parts of a clip are being looked for.
    Q_PROPERTY(bool findingSilence READ findingSilence NOTIFY findingSilenceChanged)

public:
    explicit EditorProject(QObject *parent = nullptr);

    QUrl mediaUrl() const;
    QString mediaName() const;
    QUrl projectUrl() const;
    qint64 durationMs() const;
    qint64 inMs() const;
    qint64 outMs() const;
    QVariantList clips() const;
    int clipCount() const;
    int activeClipIndex() const;
    qint64 sequenceDurationMs() const;
    bool canExport() const;
    bool hasMedia() const;
    bool dirty() const;
    bool canUndo() const;
    bool canRedo() const;
    QString errorText() const;
    QString transition() const;
    int transitionMs() const;
    QVariantList audioItems() const;
    int audioCount() const;
    int activeAudioIndex() const;
    bool musicDuck() const;
    QVariantList textItems() const;
    int activeTextIndex() const { return m_activeTextIndex; }
    bool mixed() const;
    // Transition and music settings for ExportController::startSequence.
    Q_INVOKABLE QVariantMap exportOptions() const;

    Q_INVOKABLE bool importMedia(const QUrl &url);
    Q_INVOKABLE bool appendMedia(const QUrl &url);
    Q_INVOKABLE bool selectClip(int index);
    Q_INVOKABLE bool splitAt(qint64 positionMs);
    Q_INVOKABLE bool moveClip(int index, int direction);
    Q_INVOKABLE bool moveClipTo(int from, int to);
    Q_INVOKABLE bool setClipRange(int index, qint64 inMs, qint64 outMs);
    Q_INVOKABLE bool duplicateClip(int index);
    Q_INVOKABLE bool removeClip(int index);
    // Clip volume, 0 to 2 (200%); muting keeps the level for unmuting.
    Q_INVOKABLE bool setClipVolume(int index, double volume);
    Q_INVOKABLE bool setClipMuted(int index, bool muted);
    // Playback speed, 0.25x to 4x; the clip takes (out - in) / speed on the timeline.
    Q_INVOKABLE bool setClipSpeed(int index, double speed);
    // Replaces one clip with the given source ranges ({inMs, outMs}) as a single undo step.
    Q_INVOKABLE bool replaceClipRanges(int index, const QVariantList &ranges);
    // Cuts the quiet parts out of a clip (below thresholdDb for at least minMs), as one undo step.
    Q_INVOKABLE bool removeSilence(int index, double thresholdDb = -35, int minMs = 600);
    // Writes the active clip's frame at sourceMs to an image file at full size; answers with frameSaved.
    Q_INVOKABLE bool saveFrame(qint64 sourceMs, const QUrl &target);
    // For the recent list: drops files that were moved or deleted.
    Q_INVOKABLE static bool fileExists(const QUrl &url) { return url.isLocalFile() && QFileInfo::exists(url.toLocalFile()); }
    bool findingSilence() const { return m_findingSilence; }
    // silencedetect output to {start, end} pairs in ms, shifted by offsetMs; an open silence ends at endMs.
    static QList<QPair<qint64, qint64>> parseSilence(const QString &log, qint64 offsetMs, qint64 endMs);
    // The parts of [inMs, outMs] to keep, leaving padMs of each quiet part.
    static QVariantList keepRanges(qint64 inMs, qint64 outMs, const QList<QPair<qint64, qint64>> &silences, qint64 padMs = 150);
    Q_INVOKABLE bool setTransition(const QString &kind);
    Q_INVOKABLE void setTransitionMs(int value);
    // Adds a file to the audio track at startMs and selects it; returns its index or -1.
    Q_INVOKABLE int addAudio(const QUrl &url, qint64 startMs);
    // -1 clears the selection.
    Q_INVOKABLE bool selectAudio(int index);
    // Where the item starts on the sequence and which part of the file plays.
    Q_INVOKABLE bool setAudioPlacement(int index, qint64 startMs, qint64 inMs, qint64 outMs);
    Q_INVOKABLE bool setAudioVolume(int index, double volume);
    // Fade lengths at the item's start and end; together at most its length.
    Q_INVOKABLE bool setAudioFades(int index, qint64 fadeInMs, qint64 fadeOutMs);
    // Cuts the item in two at a sequence time; both parts keep at least 100 ms.
    Q_INVOKABLE bool splitAudio(int index, qint64 atMs);
    Q_INVOKABLE bool removeAudio(int index);
    Q_INVOKABLE void setMusicDuck(bool value);
    // Adds a caption at startMs and selects it; returns its index or -1.
    Q_INVOKABLE int addText(qint64 startMs);
    // -1 clears the selection.
    Q_INVOKABLE bool selectText(int index);
    Q_INVOKABLE bool setTextContent(int index, const QString &text);
    Q_INVOKABLE bool setTextPlacement(int index, qint64 startMs, qint64 endMs);
    // Merges changes (x, y, size, color, font, style; see TextOverlay) into
    // the caption; out of range values are clamped, unknown names dropped.
    Q_INVOKABLE bool setTextStyle(int index, const QVariantMap &changes);
    // Cuts the caption in two at a sequence time; both parts keep at least 200 ms.
    Q_INVOKABLE bool splitText(int index, qint64 atMs);
    // A copy right after the caption, or over it when there is no room.
    Q_INVOKABLE int duplicateText(int index);
    Q_INVOKABLE bool removeText(int index);
    Q_INVOKABLE bool openProject(const QUrl &url);
    // Back to an empty editor: no clips, no project file, no history.
    Q_INVOKABLE void closeProject();
    Q_INVOKABLE bool saveProject(const QUrl &url = {});
    Q_INVOKABLE void setDurationMs(qint64 value);
    Q_INVOKABLE void setInMs(qint64 value);
    Q_INVOKABLE void setOutMs(qint64 value);
    Q_INVOKABLE void moveRange(qint64 deltaMs);
    Q_INVOKABLE void clearError();
    Q_INVOKABLE bool undo();
    Q_INVOKABLE bool redo();

    // Crash recovery: unsaved work is copied to recoveryPath a minute after
    // an edit. A normal exit, a save or closing the project removes the copy,
    // so one that is still there at startup is from a crash.
    void setRecoveryPath(const QString &path);
    Q_INVOKABLE void autosaveNow();
    // {name, savedAt, clipCount} of the copy left behind, or empty.
    Q_INVOKABLE QVariantMap recoveryInfo() const;
    // Opens the copy as unsaved work (keeping the original project's path).
    Q_INVOKABLE bool restoreRecovery();
    Q_INVOKABLE void discardRecovery();

signals:
    void changed();
    void errorTextChanged();
    void findingSilenceChanged();
    // Reported after removeSilence: the clip's parts left and the time cut (0 when nothing was quiet).
    void silenceRemoved(int parts, qint64 removedMs);
    void frameSaved(const QUrl &file, const QString &error);

private:
    struct Clip {
        QUrl mediaUrl;
        qint64 durationMs = 0;
        qint64 inMs = 0;
        qint64 outMs = 0;
        double volume = 1.0;
        bool muted = false;
        double speed = 1.0;
        qint64 lengthMs() const { return qMax<qint64>(0, qRound64((outMs - inMs) / speed)); }
    };
    struct AudioItem {
        QUrl mediaUrl;
        qint64 durationMs = 0;
        qint64 startMs = 0;
        qint64 inMs = 0;
        qint64 outMs = 0;
        double volume = 0.5;
        qint64 fadeInMs = 0;
        qint64 fadeOutMs = 0;
    };
    using TextItem = TextOverlay;
    struct Mix {
        QString transition = QStringLiteral("cut");
        int transitionMs = 500;
        QVector<AudioItem> audio;
        bool musicDuck = true;
        QVector<TextItem> texts;
    };
    const Clip *active() const;
    Clip *active();
    bool validMedia(const QUrl &url);
    void setError(const QString &message);
    void markChanged();
    // History: every edit that goes through markChanged() is one undo step.
    // Opening or importing starts a fresh history; metadata discovery
    // (probed durations) updates the baseline without adding a step.
    struct Snapshot {
        QVector<Clip> clips;
        int activeIndex = -1;
        Mix mix;
    };
    Snapshot snapshot() const;
    void restore(const Snapshot &state);
    void resetHistory();
    void probeDurations();
    void applyProbedDuration(const QUrl &url, qint64 durationMs);
    // The project as JSON, with media paths relative to directory.
    QByteArray serialize(const QString &directory) const;

    QVector<Clip> m_clips;
    int m_activeClipIndex = -1;
    int m_activeAudioIndex = -1;
    int m_activeTextIndex = -1;
    Mix m_mix;
    QUrl m_projectUrl;
    bool m_dirty = false;
    QString m_errorText;
    QSet<QUrl> m_probing;
    bool m_findingSilence = false;
    QVector<Snapshot> m_undo;
    QVector<Snapshot> m_redo;
    Snapshot m_baseline;
    QString m_recoveryPath;
    QTimer m_autosave;
};
