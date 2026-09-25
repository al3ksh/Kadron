#pragma once

#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QObject>
#include <QPointer>
#include <QSaveFile>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <memory>

class QNetworkReply;
class QHttpMultiPart;
class ToolsClient;

class RemoteJobsClient final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool resultAvailable READ resultAvailable NOTIFY changed)
    Q_PROPERTY(QString stage READ stage NOTIFY changed)
    Q_PROPERTY(QString errorText READ errorText NOTIFY changed)
    Q_PROPERTY(int progress READ progress NOTIFY changed)
    Q_PROPERTY(QString outputFilename READ outputFilename NOTIFY changed)
    Q_PROPERTY(qint64 outputBytes READ outputBytes NOTIFY changed)
    Q_PROPERTY(bool overTarget READ overTarget NOTIFY changed)
    Q_PROPERTY(QUrl savedUrl READ savedUrl NOTIFY changed)

public:
    explicit RemoteJobsClient(ToolsClient *tools, QObject *parent = nullptr);
    bool busy() const;
    bool resultAvailable() const;
    QString stage() const;
    QString errorText() const;
    int progress() const;
    QString outputFilename() const;
    qint64 outputBytes() const;
    bool overTarget() const;
    QUrl savedUrl() const;

    Q_INVOKABLE bool download(const QString &url, const QString &preset, double gifStart,
                              double gifDuration, int gifFps, int gifWidth, double gifTargetMB);
    Q_INVOKABLE bool pdfAction(const QString &action, const QVariantList &files,
                               const QString &pages, int rotation);
    Q_INVOKABLE bool saveResult(const QUrl &destination);
    Q_INVOKABLE void cancel();

signals:
    void changed();

private:
    enum class Operation { None, Download, Pdf, Saving };
    bool begin(Operation operation);
    QNetworkRequest request(const QString &path) const;
    void acceptedJob(QNetworkReply *reply);
    void pollJob();
    void fail(const QString &message);
    QString responseError(QNetworkReply *reply) const;
    void appendFormField(QHttpMultiPart *multipart, const QString &name, const QByteArray &value);

    ToolsClient *m_tools;
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_reply;
    QTimer m_pollTimer;
    std::unique_ptr<QSaveFile> m_saveFile;
    QString m_jobId;
    QString m_serverUrl;
    QString m_sessionId;
    QString m_outputFilename;
    QString m_stage;
    QString m_errorText;
    QUrl m_savedUrl;
    Operation m_operation = Operation::None;
    qint64 m_outputBytes = 0;
    bool m_overTarget = false;
    int m_progress = 0;
    int m_pollCount = 0;
};
