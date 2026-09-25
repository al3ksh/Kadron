#include "ToolsClient.h"

#include <QFileInfo>
#include <QSaveFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QUuid>

namespace {
constexpr qint64 ChunkBytes = 4 * 1024 * 1024;
constexpr qint64 GuestDropBytes = 50 * 1024 * 1024;
constexpr qint64 GuestClipBytes = 200 * 1024 * 1024;
}

ToolsClient::ToolsClient(QObject *parent) : QObject(parent)
{
    QSettings settings;
    m_serverUrl = settings.value("tools/serverUrl").toString();
    m_sessionId = settings.value("tools/sessionId").toString();
    if (m_sessionId.isEmpty()) {
        m_sessionId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        settings.setValue("tools/sessionId", m_sessionId);
    }
    m_pollTimer.setInterval(2000);
    connect(&m_pollTimer, &QTimer::timeout, this, &ToolsClient::pollJob);
}

QString ToolsClient::serverUrl() const { return m_serverUrl; }
QString ToolsClient::sessionId() const { return m_sessionId; }
bool ToolsClient::busy() const { return m_operation != Operation::None; }
bool ToolsClient::connected() const { return m_connected; }
QString ToolsClient::stage() const { return m_stage; }
QString ToolsClient::errorText() const { return m_errorText; }
int ToolsClient::progress() const { return m_progress; }
QUrl ToolsClient::resultUrl() const { return m_resultUrl; }
QUrl ToolsClient::qrPreviewUrl() const { return m_qrPreviewUrl; }

void ToolsClient::setServerUrl(const QString &value)
{
    const auto trimmed = value.trimmed();
    const QUrl parsed(trimmed);
    if (!trimmed.isEmpty() && (!parsed.isValid() || (parsed.scheme() != "http" && parsed.scheme() != "https")
        || parsed.host().isEmpty() || !parsed.userInfo().isEmpty() || !parsed.query().isEmpty()
        || !parsed.fragment().isEmpty() || (parsed.path() != "/" && !parsed.path().isEmpty()))) {
        m_errorText = QStringLiteral("Enter a server origin, for example https://tools.example.com.");
        emit changed();
        return;
    }
    if (busy()) {
        m_errorText = QStringLiteral("Wait for the current operation before changing servers.");
        emit changed();
        return;
    }
    const auto normalized = trimmed.endsWith('/') ? trimmed.left(trimmed.size() - 1) : trimmed;
    if (m_serverUrl == normalized)
        return;
    m_serverUrl = normalized;
    m_connected = false;
    m_errorText.clear();
    m_resultUrl = QUrl();
    QSettings().setValue("tools/serverUrl", m_serverUrl);
    emit changed();
}

QUrl ToolsClient::endpoint(const QString &path) const { return QUrl(m_serverUrl + path); }

QNetworkRequest ToolsClient::request(const QString &path) const
{
    QNetworkRequest result(endpoint(path));
    result.setTransferTimeout(120000);
    return result;
}

QNetworkReply *ToolsClient::postJson(const QString &path, const QJsonObject &body)
{
    auto req = request(path);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    m_reply = m_network.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    return m_reply;
}

bool ToolsClient::begin(Operation operation)
{
    if (busy())
        return false;
    if (m_serverUrl.isEmpty()) {
        m_errorText = QStringLiteral("Set your Tools server address first.");
        emit changed();
        return false;
    }
    m_operation = operation;
    m_errorText.clear();
    m_resultUrl = QUrl();
    m_progress = 0;
    m_jobId.clear();
    emit changed();
    return true;
}

QString ToolsClient::responseError(QNetworkReply *reply) const
{
    const auto body = QJsonDocument::fromJson(reply->readAll()).object();
    const auto serverError = body.value("error").toString();
    if (!serverError.isEmpty())
        return serverError;
    return reply->error() == QNetworkReply::NoError
        ? QStringLiteral("The server returned an unexpected response.") : reply->errorString();
}

void ToolsClient::fail(const QString &message)
{
    m_pollTimer.stop();
    m_file.close();
    m_reply = nullptr;
    m_operation = Operation::None;
    m_stage = QStringLiteral("Failed");
    m_errorText = message;
    emit changed();
}

void ToolsClient::finish(const QUrl &url)
{
    m_pollTimer.stop();
    m_file.close();
    m_reply = nullptr;
    m_operation = Operation::None;
    m_resultUrl = url;
    m_stage = QStringLiteral("Ready");
    m_progress = 100;
    emit changed();
}

void ToolsClient::testConnection()
{
    if (!begin(Operation::Health))
        return;
    m_stage = QStringLiteral("Connecting");
    m_reply = m_network.get(request("/api/health"));
    auto *reply = m_reply.data();
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const bool current = m_reply == reply;
        if (current) m_reply = nullptr;
        reply->deleteLater();
        if (!current || m_operation != Operation::Health)
            return;
        const auto body = QJsonDocument::fromJson(reply->readAll()).object();
        if (reply->error() != QNetworkReply::NoError || body.value("status") != "ok") {
            m_connected = false;
            fail(reply->error() == QNetworkReply::NoError ? QStringLiteral("This server is not ready.") : reply->errorString());
            return;
        }
        m_connected = true;
        finish(QUrl());
    });
    emit changed();
}

void ToolsClient::shorten(const QString &url, const QString &slug)
{
    const QUrl target(url.trimmed());
    if (!target.isValid() || (target.scheme() != "http" && target.scheme() != "https") || target.host().isEmpty()) {
        m_errorText = QStringLiteral("Enter a complete http or https link.");
        emit changed();
        return;
    }
    if (!begin(Operation::Shorten))
        return;
    m_stage = QStringLiteral("Creating link");
    auto *reply = postJson("/api/shorten", {{"url", target.toString()}, {"slug", slug.trimmed()}, {"sessionId", m_sessionId}});
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const bool current = m_reply == reply;
        if (current) m_reply = nullptr;
        reply->deleteLater();
        if (!current || m_operation != Operation::Shorten)
            return;
        if (reply->error() != QNetworkReply::NoError) {
            fail(responseError(reply));
            return;
        }
        const auto result = QJsonDocument::fromJson(reply->readAll()).object().value("shortUrl").toString();
        if (result.isEmpty()) {
            fail(QStringLiteral("The server did not return a short link."));
            return;
        }
        finish(QUrl(result));
    });
    emit changed();
}

void ToolsClient::publishDrop(const QUrl &fileUrl) { beginUpload(fileUrl, Operation::Drop); }
void ToolsClient::publishClip(const QUrl &fileUrl) { beginUpload(fileUrl, Operation::Clip); }

void ToolsClient::generateQr(const QString &content, int size)
{
    if (content.trimmed().isEmpty() || content.size() > 4296 || size < 100 || size > 2000) {
        m_errorText = QStringLiteral("Enter text up to 4296 characters and a size from 100 to 2000 px.");
        emit changed();
        return;
    }
    if (!begin(Operation::Qr))
        return;
    m_qrBytes.clear();
    const auto previousPath = m_qrPreviewUrl.toLocalFile();
    m_qrPreviewUrl = QUrl();
    if (!previousPath.isEmpty())
        QFile::remove(previousPath);
    m_stage = QStringLiteral("Generating QR");
    auto *reply = postJson("/api/qr/generate", {{"text", content}, {"size", size}});
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const bool current = m_reply == reply;
        if (current) m_reply = nullptr;
        reply->deleteLater();
        if (!current || m_operation != Operation::Qr)
            return;
        if (reply->error() != QNetworkReply::NoError) {
            fail(responseError(reply));
            return;
        }
        const auto url = QJsonDocument::fromJson(reply->readAll()).object().value("dataUrl").toString();
        const auto separator = url.indexOf(',');
        if (!url.startsWith("data:image/png;base64,") || separator < 0) {
            fail(QStringLiteral("The server did not return a PNG QR code."));
            return;
        }
        m_qrBytes = QByteArray::fromBase64(url.mid(separator + 1).toLatin1());
        if (!m_qrBytes.startsWith("\x89PNG\r\n\x1a\n") || !m_qrDirectory.isValid()) {
            fail(QStringLiteral("The server returned an invalid QR image."));
            return;
        }
        const auto path = m_qrDirectory.path() + "/qr-" + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".png";
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly) || file.write(m_qrBytes) != m_qrBytes.size() || !file.commit()) {
            fail(QStringLiteral("Could not prepare the QR image."));
            return;
        }
        m_qrPreviewUrl = QUrl::fromLocalFile(path);
        finish(QUrl());
    });
    emit changed();
}

bool ToolsClient::saveQr(const QUrl &destination)
{
    if (busy() || m_qrBytes.isEmpty() || !destination.isLocalFile())
        return false;
    if (QFileInfo(destination.toLocalFile()).exists()) {
        m_errorText = QStringLiteral("Output already exists. Choose a new name.");
        emit changed();
        return false;
    }
    QSaveFile file(destination.toLocalFile());
    if (!file.open(QIODevice::WriteOnly) || file.write(m_qrBytes) != m_qrBytes.size() || !file.commit()) {
        m_errorText = QStringLiteral("Could not save the QR image.");
        emit changed();
        return false;
    }
    m_errorText.clear();
    m_stage = QStringLiteral("Saved");
    emit changed();
    return true;
}

void ToolsClient::beginUpload(const QUrl &fileUrl, Operation operation)
{
    if (busy())
        return;
    const QFileInfo info(fileUrl.toLocalFile());
    if (!fileUrl.isLocalFile() || !info.isFile() || info.size() == 0) {
        m_errorText = QStringLiteral("Choose a non-empty local file to publish.");
        emit changed();
        return;
    }
    const auto limit = operation == Operation::Drop ? GuestDropBytes : GuestClipBytes;
    if (operation == Operation::Clip && !QStringList{"mp4", "mov", "mkv", "webm", "m4v", "avi"}.contains(info.suffix().toLower())) {
        m_errorText = QStringLiteral("Clips accepts video files. Choose a video or export MP4 first.");
        emit changed();
        return;
    }
    if (info.size() > limit) {
        m_errorText = operation == Operation::Drop
            ? QStringLiteral("Guest Drop limit is 50 MB. Export a smaller file or use the web admin account.")
            : QStringLiteral("Guest Clips limit is 200 MB. Export a smaller file or use the web admin account.");
        emit changed();
        return;
    }
    if (!begin(operation))
        return;
    m_file.setFileName(info.absoluteFilePath());
    if (!m_file.open(QIODevice::ReadOnly)) {
        fail(QStringLiteral("Could not read the file: %1").arg(m_file.errorString()));
        return;
    }
    m_uploadId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_offset = 0;
    m_stage = QStringLiteral("Uploading");
    emit changed();
    sendChunk();
}

void ToolsClient::sendChunk()
{
    if (m_offset >= m_file.size()) {
        finalizeUpload();
        return;
    }
    const auto chunk = m_file.read(ChunkBytes);
    if (chunk.isEmpty()) {
        fail(QStringLiteral("Could not read the next file chunk."));
        return;
    }
    const auto end = m_offset + chunk.size() - 1;
    auto req = request(m_operation == Operation::Drop ? "/api/drop/upload-chunk" : "/api/clip/upload-chunk");
    req.setRawHeader("X-Upload-Id", m_uploadId.toUtf8());
    req.setRawHeader("Content-Range", QString("bytes %1-%2/%3").arg(m_offset).arg(end).arg(m_file.size()).toUtf8());
    if (m_operation == Operation::Drop)
        req.setRawHeader("X-Session-Id", m_sessionId.toUtf8());
    m_reply = m_network.post(req, chunk);
    auto *reply = m_reply.data();
    connect(reply, &QNetworkReply::finished, this, [this, reply, end] {
        const bool current = m_reply == reply;
        if (current) m_reply = nullptr;
        reply->deleteLater();
        if (!current || (m_operation != Operation::Drop && m_operation != Operation::Clip))
            return;
        if (reply->error() != QNetworkReply::NoError) {
            fail(responseError(reply));
            return;
        }
        const auto body = QJsonDocument::fromJson(reply->readAll()).object();
        if (body.value("received").toInteger() != end - m_offset + 1) {
            fail(QStringLiteral("The server did not confirm this file chunk."));
            return;
        }
        m_offset = end + 1;
        m_progress = static_cast<int>(m_offset * 65 / m_file.size());
        emit changed();
        sendChunk();
    });
}

void ToolsClient::finalizeUpload()
{
    m_stage = QStringLiteral("Finalizing");
    emit changed();
    const auto isDrop = m_operation == Operation::Drop;
    auto *reply = postJson(isDrop ? "/api/drop/finalize" : "/api/clip/finalize", {
        {"uploadId", m_uploadId},
        {"filename", QFileInfo(m_file.fileName()).fileName()},
        {"sessionId", m_sessionId}
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, isDrop] {
        const bool current = m_reply == reply;
        if (current) m_reply = nullptr;
        reply->deleteLater();
        if (!current || (m_operation != Operation::Drop && m_operation != Operation::Clip))
            return;
        if (reply->error() != QNetworkReply::NoError) {
            fail(responseError(reply));
            return;
        }
        const auto body = QJsonDocument::fromJson(reply->readAll()).object();
        if (isDrop) {
            const auto url = QUrl(body.value("url").toString());
            if (url.isValid() && !url.isEmpty()) finish(url);
            else fail(QStringLiteral("The server did not return a Drop link."));
        } else {
            m_jobId = body.value("jobId").toString();
            if (m_jobId.isEmpty()) {
                fail(QStringLiteral("The server did not create a clip job."));
                return;
            }
            m_file.close();
            m_progress = 65;
            m_stage = QStringLiteral("Queued");
            m_pollCount = 0;
            m_pollTimer.start();
            emit changed();
            pollJob();
        }
    });
}

void ToolsClient::pollJob()
{
    if (m_operation != Operation::Clip || m_reply && m_reply->isRunning())
        return;
    if (++m_pollCount > 900) {
        fail(QStringLiteral("Clip processing is taking too long. Check the job on your Tools server."));
        return;
    }
    m_reply = m_network.get(request("/api/jobs/" + m_jobId + "?sessionId=" + m_sessionId));
    auto *reply = m_reply.data();
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const bool current = m_reply == reply;
        if (current) m_reply = nullptr;
        reply->deleteLater();
        if (!current || m_operation != Operation::Clip)
            return;
        if (reply->error() != QNetworkReply::NoError) {
            fail(responseError(reply));
            return;
        }
        const auto job = QJsonDocument::fromJson(reply->readAll()).object();
        const auto status = job.value("status").toString();
        if (status == "done") {
            const auto path = job.value("outputJson").toObject().value("clip").toObject().value("url").toString();
            if (path.isEmpty()) fail(QStringLiteral("Clip finished without a link."));
            else finish(endpoint(path));
        } else if (status == "failed" || status == "expired") {
            fail(job.value("error").toString(QStringLiteral("Clip processing failed on the server.")));
        } else if (status == "queued") {
            const auto position = job.value("queuePosition").toInt();
            m_stage = position > 0 ? QStringLiteral("Queued (%1 ahead)").arg(position - 1) : QStringLiteral("Queued");
            emit changed();
        } else if (status == "running") {
            m_stage = job.value("logsTail").toString(QStringLiteral("Processing clip"));
            m_progress = 65 + qBound(0, job.value("progress").toInt(), 100) * 34 / 100;
            emit changed();
        } else {
            fail(QStringLiteral("The server returned an unknown clip status."));
        }
    });
}

void ToolsClient::cancel()
{
    if (!busy())
        return;
    const auto activeJob = m_operation == Operation::Clip && !m_jobId.isEmpty() ? m_jobId : QString();
    m_operation = Operation::None;
    m_pollTimer.stop();
    if (m_reply)
        m_reply->abort();
    m_reply = nullptr;
    m_file.close();
    if (!activeJob.isEmpty()) {
        auto *cancelReply = m_network.post(request("/api/jobs/" + activeJob + "/cancel?sessionId=" + m_sessionId), QByteArray());
        connect(cancelReply, &QNetworkReply::finished, cancelReply, &QNetworkReply::deleteLater);
    }
    m_stage = activeJob.isEmpty() ? QStringLiteral("Cancelled") : QStringLiteral("Cancellation requested");
    m_errorText.clear();
    emit changed();
}
