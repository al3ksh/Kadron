#pragma once

#include <QObject>
#include <QUrl>

class EditorProject final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl mediaUrl READ mediaUrl NOTIFY changed)
    Q_PROPERTY(QString mediaName READ mediaName NOTIFY changed)
    Q_PROPERTY(QUrl projectUrl READ projectUrl NOTIFY changed)
    Q_PROPERTY(qint64 durationMs READ durationMs NOTIFY changed)
    Q_PROPERTY(qint64 inMs READ inMs NOTIFY changed)
    Q_PROPERTY(qint64 outMs READ outMs NOTIFY changed)
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
    bool hasMedia() const;
    bool dirty() const;
    QString errorText() const;

    Q_INVOKABLE bool importMedia(const QUrl &url);
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
    void setError(const QString &message);
    void markChanged();

    QUrl m_mediaUrl;
    QUrl m_projectUrl;
    qint64 m_durationMs = 0;
    qint64 m_inMs = 0;
    qint64 m_outMs = 0;
    bool m_dirty = false;
    QString m_errorText;
};
