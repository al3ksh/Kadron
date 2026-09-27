#pragma once

#include <QObject>
#include <QUrl>
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
    // A music track under the whole sequence, looped and faded out at the end.
    Q_PROPERTY(QUrl musicUrl READ musicUrl NOTIFY changed)
    Q_PROPERTY(QString musicName READ musicName NOTIFY changed)
    Q_PROPERTY(double musicVolume READ musicVolume NOTIFY changed)
    // Lower the music while the clips have sound (speech).
    Q_PROPERTY(bool musicDuck READ musicDuck NOTIFY changed)
    // Whether an export needs the full sequence pipeline rather than a plain trim.
    Q_PROPERTY(bool mixed READ mixed NOTIFY changed)

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
    QUrl musicUrl() const;
    QString musicName() const;
    double musicVolume() const;
    bool musicDuck() const;
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
    Q_INVOKABLE bool setTransition(const QString &kind);
    Q_INVOKABLE void setTransitionMs(int value);
    Q_INVOKABLE bool setMusic(const QUrl &url);
    Q_INVOKABLE void clearMusic();
    Q_INVOKABLE void setMusicVolume(double value);
    Q_INVOKABLE void setMusicDuck(bool value);
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

signals:
    void changed();
    void errorTextChanged();

private:
    struct Clip {
        QUrl mediaUrl;
        qint64 durationMs = 0;
        qint64 inMs = 0;
        qint64 outMs = 0;
        double volume = 1.0;
        bool muted = false;
    };
    struct Mix {
        QString transition = QStringLiteral("cut");
        int transitionMs = 500;
        QUrl musicUrl;
        double musicVolume = 0.35;
        bool musicDuck = true;
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

    QVector<Clip> m_clips;
    int m_activeClipIndex = -1;
    Mix m_mix;
    QUrl m_projectUrl;
    bool m_dirty = false;
    QString m_errorText;
    QSet<QUrl> m_probing;
    QVector<Snapshot> m_undo;
    QVector<Snapshot> m_redo;
    Snapshot m_baseline;
};
