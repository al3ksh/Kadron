#include "RemoteJobsClient.h"
#include "ToolsClient.h"

#include <QFile>
#include <QFileInfo>
#include <QHttpMultiPart>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QRegularExpression>

RemoteJobsClient::RemoteJobsClient(ToolsClient *tools, QObject *parent) : QObject(parent), m_tools(tools)
{
    m_pollTimer.setInterval(2000);
    connect(&m_pollTimer, &QTimer::timeout, this, &RemoteJobsClient::pollJob);
}

bool RemoteJobsClient::busy() const { return m_operation != Operation::None; }
bool RemoteJobsClient::resultAvailable() const { return !m_jobId.isEmpty() && !m_outputFilename.isEmpty(); }
QString RemoteJobsClient::stage() const { return m_stage; }
QString RemoteJobsClient::errorText() const { return m_errorText; }
int RemoteJobsClient::progress() const { return m_progress; }
QString RemoteJobsClient::outputFilename() const { return m_outputFilename; }
qint64 RemoteJobsClient::outputBytes() const { return m_outputBytes; }
bool RemoteJobsClient::overTarget() const { return m_overTarget; }
QUrl RemoteJobsClient::savedUrl() const { return m_savedUrl; }

QNetworkRequest RemoteJobsClient::request(const QString &path) const
{
    QNetworkRequest result(QUrl(m_serverUrl + path));
    result.setTransferTimeout(120000);
    result.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    return result;
}

bool RemoteJobsClient::begin(Operation operation)
{
    if (busy())
        return false;
    if (m_tools->serverUrl().isEmpty()) {
        m_errorText = QStringLiteral("Set your Tools server address in Publish first.");
        emit changed();
        return false;
    }
    m_operation = operation;
    m_serverUrl = m_tools->serverUrl();
    m_sessionId = m_tools->sessionId();
    m_errorText.clear();
    m_outputFilename.clear();
    m_jobId.clear();
    m_outputBytes = 0;
    m_overTarget = false;
    m_savedUrl = QUrl();
    m_progress = 0;
    m_pollCount = 0;
    emit changed();
    return true;
}

QString RemoteJobsClient::responseError(QNetworkReply *reply) const
{
    const auto body = QJsonDocument::fromJson(reply->readAll()).object();
    const auto message = body.value("error").toString();
    return !message.isEmpty() ? message : reply->error() == QNetworkReply::NoError
        ? QStringLiteral("Unexpected response from the server.") : reply->errorString();
}

void RemoteJobsClient::fail(const QString &message)
{
    m_pollTimer.stop();
    if (m_saveFile) {
        m_saveFile->cancelWriting();
        m_saveFile.reset();
    }
    m_reply = nullptr;
    m_operation = Operation::None;
    m_stage = QStringLiteral("Failed");
    m_errorText = message;
    emit changed();
}

bool RemoteJobsClient::download(const QString &url, const QString &preset, double gifStart,
                                double gifDuration, int gifFps, int gifWidth, double gifTargetMB)
{
    if (busy())
        return false;
    const auto target = QUrl(url.trimmed());
    const QStringList presets{
        "VIDEO_MP4_BEST", "VIDEO_MP4_720P", "VIDEO_MP4_DISCORD", "VIDEO_GIF_SOCIAL",
        "AUDIO_MP3_320", "AUDIO_MP3_192", "AUDIO_FLAC_BEST", "AUDIO_WAV_BEST",
        "AUDIO_OPUS_96", "AUDIO_OPUS_BEST"
    };
    if (!target.isValid() || (target.scheme() != "http" && target.scheme() != "https")
        || target.host().isEmpty() || !presets.contains(preset)) {
        m_errorText = QStringLiteral("Enter a valid URL and download format.");
        emit changed();
        return false;
    }
    if (!begin(Operation::Download))
        return false;
    QJsonObject body{{"url", target.toString()}, {"preset", preset}, {"sessionId", m_sessionId}};
    if (preset == "VIDEO_GIF_SOCIAL") {
        body.insert("gifStart", qMax(0.0, gifStart));
        body.insert("gifDuration", qBound(1.0, gifDuration, 20.0));
        body.insert("gifFps", qBound(5, gifFps, 15));
        body.insert("gifWidth", qBound(160, gifWidth, 720));
        body.insert("gifTargetMB", qBound(1.0, gifTargetMB, 25.0));
    }
    auto req = request("/api/downloader");
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    m_stage = QStringLiteral("Submitting download");
    m_reply = m_network.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    auto *reply = m_reply.data();
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const bool current = m_reply == reply;
        if (current) m_reply = nullptr;
        reply->deleteLater();
        if (current && m_operation == Operation::Download)
            acceptedJob(reply);
    });
    emit changed();
    return true;
}

void RemoteJobsClient::appendFormField(QHttpMultiPart *multipart, const QString &name, const QByteArray &value)
{
    QHttpPart part;
    part.setHeader(QNetworkRequest::ContentDispositionHeader, QString("form-data; name=\"%1\"").arg(name));
    part.setBody(value);
    multipart->append(part);
}

bool RemoteJobsClient::pdfAction(const QString &action, const QVariantList &files,
                                  const QString &pages, int rotation)
{
    if (busy())
        return false;
    const QStringList actions{"merge", "split", "rotate", "remove-pages", "images-to-pdf", "reorder"};
    if (!actions.contains(action) || files.isEmpty()
        || (action == "merge" && files.size() < 2)
        || (action != "merge" && action != "images-to-pdf" && files.size() != 1)) {
        m_errorText = QStringLiteral("Choose the required PDF files for this operation.");
        emit changed();
        return false;
    }
    QList<QFileInfo> selected;
    qint64 totalBytes = 0;
    for (const auto &entry : files) {
        const auto url = entry.toUrl();
        const QFileInfo info(url.toLocalFile());
        const auto suffix = info.suffix().toLower();
        if (!url.isLocalFile() || !info.isFile()
            || (action == "images-to-pdf" ? !QStringList{"jpg", "jpeg", "png"}.contains(suffix) : suffix != "pdf")) {
            m_errorText = QStringLiteral("Choose local PDF files, or JPG/PNG images for images to PDF.");
            emit changed();
            return false;
        }
        selected.append(info);
        totalBytes += info.size();
    }
    if (totalBytes > 49 * 1024 * 1024) {
        m_errorText = QStringLiteral("Guest PDF upload is limited to 50 MB including form data.");
        emit changed();
        return false;
    }

    QJsonArray pageArray;
    if (action != "merge" && action != "images-to-pdf") {
        const QRegularExpression pagePattern("^(\\d+)(?:-(\\d+))?$");
        for (const auto &part : pages.split(',', Qt::SkipEmptyParts)) {
            const auto match = pagePattern.match(part.trimmed());
            if (!match.hasMatch()) {
                m_errorText = QStringLiteral("Use page numbers like 1,3-5.");
                emit changed();
                return false;
            }
            const auto first = match.captured(1).toInt();
            const auto last = match.captured(2).isEmpty() ? first : match.captured(2).toInt();
            if (first < 1 || last < first || last > 10000 || pageArray.size() + last - first > 10000) {
                m_errorText = QStringLiteral("Page range is invalid or too large.");
                emit changed();
                return false;
            }
            for (int page = first; page <= last; ++page)
                pageArray.append(page);
        }
        if (pageArray.isEmpty() || (action == "rotate" && rotation % 90 != 0)) {
            m_errorText = QStringLiteral("Enter pages and a rotation in 90-degree steps.");
            emit changed();
            return false;
        }
    }
    if (!begin(Operation::Pdf))
        return false;

    auto *multipart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
    const auto field = action == "merge" ? "files" : action == "images-to-pdf" ? "images" : "file";
    for (const auto &info : selected) {
        auto *file = new QFile(info.absoluteFilePath(), multipart);
        if (!file->open(QIODevice::ReadOnly)) {
            delete multipart;
            fail(QStringLiteral("Could not read %1.").arg(info.fileName()));
            return false;
        }
        QHttpPart part;
        part.setHeader(QNetworkRequest::ContentDispositionHeader,
                       QString("form-data; name=\"%1\"; filename=\"%2\"").arg(field, info.fileName()));
        part.setHeader(QNetworkRequest::ContentTypeHeader,
                       action != "images-to-pdf" ? "application/pdf"
                       : info.suffix().toLower() == "png" ? "image/png" : "image/jpeg");
        part.setBodyDevice(file);
        multipart->append(part);
    }
    appendFormField(multipart, "sessionId", m_sessionId.toUtf8());
    if (action == "rotate") {
        QJsonObject rotations;
        for (const auto &page : pageArray)
            rotations.insert(QString::number(page.toInt()), rotation);
        appendFormField(multipart, "rotations", QJsonDocument(rotations).toJson(QJsonDocument::Compact));
    } else if (action == "split" || action == "remove-pages") {
        appendFormField(multipart, "pages", QJsonDocument(pageArray).toJson(QJsonDocument::Compact));
    } else if (action == "reorder") {
        appendFormField(multipart, "order", QJsonDocument(pageArray).toJson(QJsonDocument::Compact));
    }

    m_stage = QStringLiteral("Uploading documents");
    m_reply = m_network.post(request("/api/pdf/" + action), multipart);
    multipart->setParent(m_reply);
    auto *reply = m_reply.data();
    connect(reply, &QNetworkReply::uploadProgress, this, [this, reply](qint64 sent, qint64 total) {
        if (m_reply == reply && total > 0) {
            m_progress = qBound(0, static_cast<int>(sent * 30 / total), 30);
            emit changed();
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const bool current = m_reply == reply;
        if (current) m_reply = nullptr;
        reply->deleteLater();
        if (current && m_operation == Operation::Pdf)
            acceptedJob(reply);
    });
    emit changed();
    return true;
}

void RemoteJobsClient::acceptedJob(QNetworkReply *reply)
{
    if (reply->error() != QNetworkReply::NoError) {
        fail(responseError(reply));
        return;
    }
    m_jobId = QJsonDocument::fromJson(reply->readAll()).object().value("jobId").toString();
    if (m_jobId.isEmpty()) {
        fail(QStringLiteral("The server did not create a job."));
        return;
    }
    m_stage = QStringLiteral("Queued");
    m_pollTimer.start();
    emit changed();
    pollJob();
}

void RemoteJobsClient::pollJob()
{
    if ((m_operation != Operation::Download && m_operation != Operation::Pdf) || m_reply)
        return;
    if (++m_pollCount > 900) {
        fail(QStringLiteral("Job timed out. Check the Tools server for its final status."));
        return;
    }
    m_reply = m_network.get(request("/api/jobs/" + m_jobId + "?sessionId=" + m_sessionId));
    auto *reply = m_reply.data();
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const bool current = m_reply == reply;
        if (current) m_reply = nullptr;
        reply->deleteLater();
        if (!current || (m_operation != Operation::Download && m_operation != Operation::Pdf))
            return;
        if (reply->error() != QNetworkReply::NoError) {
            fail(responseError(reply));
            return;
        }
        const auto job = QJsonDocument::fromJson(reply->readAll()).object();
        const auto status = job.value("status").toString();
        if (status == "done") {
            const auto files = job.value("outputJson").toObject().value("files").toArray();
            if (files.isEmpty()) {
                fail(QStringLiteral("Job finished without a downloadable file."));
                return;
            }
            const auto file = files.first().toObject();
            m_outputFilename = QFileInfo(file.value("filename").toString()).fileName();
            m_outputBytes = file.value("size").toInteger();
            m_overTarget = job.value("outputJson").toObject().value("gif").toObject().value("overTarget").toBool();
            if (m_outputFilename.isEmpty()) {
                fail(QStringLiteral("Job returned an invalid output filename."));
                return;
            }
            m_operation = Operation::None;
            m_pollTimer.stop();
            m_stage = QStringLiteral("Ready to save");
            m_progress = 100;
            emit changed();
        } else if (status == "failed" || status == "expired") {
            fail(job.value("error").toString(QStringLiteral("Job failed on the server.")));
        } else if (status == "queued") {
            const auto position = job.value("queuePosition").toInt();
            m_stage = position > 0 ? QStringLiteral("Queued (%1 ahead)").arg(position - 1) : QStringLiteral("Queued");
            emit changed();
        } else if (status == "running") {
            const auto serverProgress = qBound(0, job.value("progress").toInt(), 100);
            m_stage = m_operation == Operation::Pdf ? QStringLiteral("Processing PDF")
                : serverProgress >= 60 && job.value("inputJson").toObject().value("preset").toString() == "VIDEO_GIF_SOCIAL"
                    ? QStringLiteral("Encoding GIF") : QStringLiteral("Downloading source");
            m_progress = m_operation == Operation::Pdf ? 30 + serverProgress * 65 / 100 : qMin(serverProgress, 95);
            emit changed();
        } else {
            fail(QStringLiteral("The server returned an unknown job status."));
        }
    });
}

bool RemoteJobsClient::saveResult(const QUrl &destination)
{
    if (busy() || !resultAvailable() || !destination.isLocalFile())
        return false;
    const QFileInfo output(destination.toLocalFile());
    if (output.exists()) {
        m_errorText = QStringLiteral("Output already exists. Choose another file name.");
        emit changed();
        return false;
    }
    m_saveFile = std::make_unique<QSaveFile>(output.absoluteFilePath());
    if (!m_saveFile->open(QIODevice::WriteOnly)) {
        fail(QStringLiteral("Could not create the output file: %1").arg(m_saveFile->errorString()));
        return false;
    }
    m_operation = Operation::Saving;
    m_stage = QStringLiteral("Saving file");
    m_progress = 0;
    m_errorText.clear();
    const auto encodedName = QString::fromUtf8(QUrl::toPercentEncoding(m_outputFilename));
    m_reply = m_network.get(request("/api/files/" + m_jobId + "/" + encodedName
                                    + "?sessionId=" + m_sessionId));
    auto *reply = m_reply.data();
    connect(reply, &QNetworkReply::readyRead, this, [this, reply] {
        if (m_reply == reply && m_saveFile && m_saveFile->write(reply->readAll()) < 0)
            reply->abort();
    });
    connect(reply, &QNetworkReply::downloadProgress, this, [this, reply](qint64 received, qint64 total) {
        if (m_reply == reply && total > 0) {
            m_progress = qBound(0, static_cast<int>(received * 100 / total), 99);
            emit changed();
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, output] {
        const bool current = m_reply == reply;
        if (current) m_reply = nullptr;
        reply->deleteLater();
        if (!current || m_operation != Operation::Saving)
            return;
        if (reply->error() != QNetworkReply::NoError) {
            fail(responseError(reply));
            return;
        }
        if (m_saveFile->write(reply->readAll()) < 0 || (m_outputBytes > 0 && m_saveFile->size() != m_outputBytes)
            || !m_saveFile->commit()) {
            fail(QStringLiteral("Could not finish saving the downloaded file."));
            return;
        }
        m_saveFile.reset();
        m_savedUrl = QUrl::fromLocalFile(output.absoluteFilePath());
        m_operation = Operation::None;
        m_stage = QStringLiteral("Saved");
        m_progress = 100;
        emit changed();
    });
    emit changed();
    return true;
}

void RemoteJobsClient::cancel()
{
    if (!busy())
        return;
    const auto activeJob = m_operation != Operation::Saving ? m_jobId : QString();
    m_operation = Operation::None;
    m_pollTimer.stop();
    if (m_reply) m_reply->abort();
    m_reply = nullptr;
    if (m_saveFile) {
        m_saveFile->cancelWriting();
        m_saveFile.reset();
    }
    if (!activeJob.isEmpty()) {
        auto *cancelReply = m_network.post(request("/api/jobs/" + activeJob
                                                   + "/cancel?sessionId=" + m_sessionId), QByteArray());
        connect(cancelReply, &QNetworkReply::finished, cancelReply, &QNetworkReply::deleteLater);
    }
    m_stage = activeJob.isEmpty() ? QStringLiteral("Cancelled") : QStringLiteral("Cancellation requested");
    m_errorText.clear();
    emit changed();
}
