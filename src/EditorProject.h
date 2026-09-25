#pragma once

#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QVector>

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
    Q_PROPERTY(QString errorText READ errorText NOTIFY errorTextChanged)

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
    QString errorText() const;

    Q_INVOKABLE bool importMedia(const QUrl &url);
    Q_INVOKABLE bool appendMedia(const QUrl &url);
    Q_INVOKABLE bool selectClip(int index);
    Q_INVOKABLE bool splitAt(qint64 positionMs);
    Q_INVOKABLE bool moveClip(int index, int direction);
    Q_INVOKABLE bool removeClip(int index);
    Q_INVOKABLE bool openProject(const QUrl &url);
    Q_INVOKABLE bool saveProject(const QUrl &url = {});
    Q_INVOKABLE void setDurationMs(qint64 value);
    Q_INVOKABLE void setInMs(qint64 value);
    Q_INVOKABLE void setOutMs(qint64 value);
    Q_INVOKABLE void moveRange(qint64 deltaMs);
    Q_INVOKABLE void clearError();

signals:
    void changed();
    void errorTextChanged();

private:
    struct Clip {
        QUrl mediaUrl;
        qint64 durationMs = 0;
        qint64 inMs = 0;
        qint64 outMs = 0;
    };
    const Clip *active() const;
    Clip *active();
    bool validMedia(const QUrl &url);
    void setError(const QString &message);
    void markChanged();

    QVector<Clip> m_clips;
    int m_activeClipIndex = -1;
    QUrl m_projectUrl;
    bool m_dirty = false;
    QString m_errorText;
};
