#pragma once

#include <QFile>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QUrl>
#include <QJsonObject>
#include <QTemporaryDir>

class QNetworkReply;

class ToolsClient final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString serverUrl READ serverUrl WRITE setServerUrl NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool connected READ connected NOTIFY changed)
    Q_PROPERTY(QString stage READ stage NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY changed)
    Q_PROPERTY(int progress READ progress NOTIFY changed)
    Q_PROPERTY(QUrl resultUrl READ resultUrl NOTIFY changed)
    Q_PROPERTY(QUrl qrPreviewUrl READ qrPreviewUrl NOTIFY changed)

public:
    explicit ToolsClient(QObject *parent = nullptr);
    QString serverUrl() const;
    QString sessionId() const;
    void setServerUrl(const QString &value);
    bool busy() const;
    bool connected() const;
    QString stage() const;
    QString errorText() const;
    int progress() const;
    QUrl resultUrl() const;
    QUrl qrPreviewUrl() const;

    Q_INVOKABLE void testConnection();
    Q_INVOKABLE void shorten(const QString &url, const QString &slug);
    Q_INVOKABLE void publishDrop(const QUrl &fileUrl);
    Q_INVOKABLE void publishClip(const QUrl &fileUrl);
    Q_INVOKABLE void generateQr(const QString &content, int size);
    Q_INVOKABLE bool saveQr(const QUrl &destination);
    Q_INVOKABLE void cancel();

signals:
    void changed();

private:
    enum class Operation { None, Health, Shorten, Drop, Clip, Qr };
    QUrl endpoint(const QString &path) const;
    QNetworkRequest request(const QString &path) const;
    QNetworkReply *postJson(const QString &path, const QJsonObject &body);
    bool begin(Operation operation);
    void fail(const QString &message);
    void finish(const QUrl &url);
    void beginUpload(const QUrl &fileUrl, Operation operation);
    void sendChunk();
    void finalizeUpload();
    void pollJob();
    QString responseError(QNetworkReply *reply) const;

    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_reply;
    QTimer m_pollTimer;
    QFile m_file;
    QString m_serverUrl;
    QString m_sessionId;
    QString m_uploadId;
    QString m_jobId;
    QString m_stage;
    QString m_errorText;
    QUrl m_resultUrl;
    QUrl m_qrPreviewUrl;
    QByteArray m_qrBytes;
    QTemporaryDir m_qrDirectory;
    Operation m_operation = Operation::None;
    qint64 m_offset = 0;
    int m_progress = 0;
    int m_pollCount = 0;
    bool m_connected = false;
};
