#include "EditorProject.h"
#include "ExportController.h"
#include "ThumbnailStrip.h"
#include "ToolsClient.h"
#include "LocalMediaTools.h"
#include "RemoteJobsClient.h"

#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>
#include <QTemporaryDir>
#include <QtTest>

class CoreTests final : public QObject
{
    Q_OBJECT

private slots:
    void projectRoundTrip();
    void sequenceProject();
    void mediaExport();
    void remoteWorkflow();
    void localMediaOperations();
    void remoteJobWorkflow();
};

void CoreTests::projectRoundTrip()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto sourcePath = directory.path() + "/source.mp4";
    QFile source(sourcePath);
    QVERIFY(source.open(QIODevice::WriteOnly));
    QVERIFY(source.write("fixture") > 0);
    source.close();

    EditorProject project;
    QVERIFY(project.importMedia(QUrl::fromLocalFile(sourcePath)));
    project.setDurationMs(5000);
    project.setInMs(1000);
    project.setOutMs(4000);
    project.moveRange(500);
    QCOMPARE(project.inMs(), 1500);
    QCOMPARE(project.outMs(), 4500);

    const auto projectPath = directory.path() + "/edit.kadr";
    QVERIFY(project.saveProject(QUrl::fromLocalFile(projectPath)));
    QVERIFY(!project.dirty());

    EditorProject reopened;
    QVERIFY(reopened.openProject(QUrl::fromLocalFile(projectPath)));
    QCOMPARE(reopened.mediaUrl().toLocalFile(), sourcePath);
    QCOMPARE(reopened.durationMs(), 5000);
    QCOMPARE(reopened.inMs(), 1500);
    QCOMPARE(reopened.outMs(), 4500);
    QVERIFY(!reopened.dirty());

    QVERIFY(QFile::remove(sourcePath));
    QVERIFY(!reopened.openProject(QUrl::fromLocalFile(projectPath)));
    QCOMPARE(reopened.inMs(), 1500);
    QVERIFY(!reopened.errorText().isEmpty());

    QFile shortSource(sourcePath);
    QVERIFY(shortSource.open(QIODevice::WriteOnly));
    QVERIFY(shortSource.write("fixture") > 0);
    shortSource.close();
    QVERIFY(reopened.importMedia(QUrl::fromLocalFile(sourcePath)));
    reopened.setDurationMs(60);
    reopened.setOutMs(20);
    QCOMPARE(reopened.outMs(), 60);
}

void CoreTests::sequenceProject()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto firstPath = directory.path() + "/first.mp4";
    const auto secondPath = directory.path() + "/second.wav";
    for (const auto &path : {firstPath, secondPath}) {
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        QVERIFY(file.write("fixture") > 0);
    }

    EditorProject project;
    QVERIFY(project.importMedia(QUrl::fromLocalFile(firstPath)));
    project.setDurationMs(5000);
    project.setInMs(500);
    project.setOutMs(4000);
    QVERIFY(project.splitAt(2000));
    QCOMPARE(project.clipCount(), 2);
    QCOMPARE(project.activeClipIndex(), 1);
    QCOMPARE(project.inMs(), 2000);
    QCOMPARE(project.sequenceDurationMs(), 3500);
    QVERIFY(project.moveClip(1, -1));
    QCOMPARE(project.activeClipIndex(), 0);
    QVERIFY(project.appendMedia(QUrl::fromLocalFile(secondPath)));
    project.setDurationMs(3000);
    QCOMPARE(project.clipCount(), 3);
    QCOMPARE(project.sequenceDurationMs(), 6500);
    QVERIFY(project.canExport());

    const auto projectPath = directory.path() + "/sequence.kadr";
    QVERIFY(project.saveProject(QUrl::fromLocalFile(projectPath)));
    EditorProject reopened;
    QVERIFY(reopened.openProject(QUrl::fromLocalFile(projectPath)));
    QCOMPARE(reopened.clipCount(), 3);
    QCOMPARE(reopened.activeClipIndex(), 2);
    QCOMPARE(reopened.sequenceDurationMs(), 6500);
    QVERIFY(!reopened.dirty());
    QVERIFY(reopened.removeClip(1));
    QCOMPARE(reopened.clipCount(), 2);
    QVERIFY(reopened.dirty());
    QVERIFY(!reopened.splitAt(0));
    QCOMPARE(reopened.clipCount(), 2);

    const auto legacyPath = directory.path() + "/legacy.kadr";
    QFile legacy(legacyPath);
    QVERIFY(legacy.open(QIODevice::WriteOnly));
    QVERIFY(legacy.write(R"({"version":1,"media":"first.mp4","durationMs":5000,"inMs":1000,"outMs":4000})") > 0);
    legacy.close();
    QVERIFY(reopened.openProject(QUrl::fromLocalFile(legacyPath)));
    QCOMPARE(reopened.clipCount(), 1);
    QCOMPARE(reopened.inMs(), 1000);
    QCOMPARE(reopened.outMs(), 4000);
}

void CoreTests::mediaExport()
{
    const auto ffmpeg = qEnvironmentVariable("KADRON_FFMPEG", "ffmpeg");
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto sourcePath = directory.path() + "/source.mp4";
    const auto outputPath = directory.path() + "/trimmed.mp4";

    QProcess generator;
    generator.start(ffmpeg, {
        "-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=15",
        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
        "-t", "4", "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-c:a", "aac", sourcePath
    });
    QVERIFY(generator.waitForFinished(30000));
    QCOMPARE(generator.exitCode(), 0);
    QVERIFY(QFileInfo(sourcePath).size() > 0);

    ThumbnailStrip thumbnails;
    thumbnails.generate(QUrl::fromLocalFile(sourcePath), 4000);
    QTRY_VERIFY_WITH_TIMEOUT(!thumbnails.busy(), 30000);
    QCOMPARE(thumbnails.frames().size(), 12);
    QVERIFY(!thumbnails.frames().first().isEmpty());

    ExportController exporter;
    QVERIFY(exporter.available());
    QVERIFY(exporter.start(QUrl::fromLocalFile(sourcePath), QUrl::fromLocalFile(outputPath), 1000, 3000));
    QTRY_VERIFY_WITH_TIMEOUT(!exporter.busy(), 60000);
    QCOMPARE(exporter.errorText(), QString());
    QCOMPARE(exporter.progress(), 100);
    QVERIFY(QFileInfo(outputPath).size() > 0);
    QCOMPARE(exporter.outputUrl().toLocalFile(), outputPath);

    auto ffprobe = QFileInfo(ffmpeg).absolutePath() + "/ffprobe";
#ifdef Q_OS_WIN
    ffprobe += ".exe";
#endif
    QProcess probe;
    probe.start(ffprobe, {
        "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", outputPath
    });
    QVERIFY(probe.waitForFinished(30000));
    QCOMPARE(probe.exitCode(), 0);
    bool durationValid = false;
    const auto duration = QString::fromUtf8(probe.readAllStandardOutput()).trimmed().toDouble(&durationValid);
    QVERIFY(durationValid);
    QVERIFY2(duration > 1.7 && duration < 2.3, qPrintable(QString("Unexpected duration: %1").arg(duration)));
    QVERIFY(!exporter.start(QUrl::fromLocalFile(sourcePath), QUrl::fromLocalFile(outputPath), 1000, 3000));
    QVERIFY(exporter.errorText().contains("already exists"));
}

void CoreTests::remoteWorkflow()
{
    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost));
    const auto origin = QString("http://127.0.0.1:%1").arg(server.serverPort());
    QStringList requests;
    QStringList errors;

    connect(&server, &QTcpServer::newConnection, &server, [&] {
        auto *socket = server.nextPendingConnection();
        connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
            auto pending = socket->property("pending").toByteArray() + socket->readAll();
            const auto headerEnd = pending.indexOf("\r\n\r\n");
            if (headerEnd < 0) {
                socket->setProperty("pending", pending);
                return;
            }
            const auto header = pending.left(headerEnd);
            qint64 length = 0;
            for (const auto &line : header.split('\n')) {
                if (line.trimmed().toLower().startsWith("content-length:"))
                    length = line.trimmed().mid(15).trimmed().toLongLong();
            }
            const auto body = pending.mid(headerEnd + 4);
            if (body.size() < length) {
                socket->setProperty("pending", pending);
                return;
            }
            const auto path = header.split(' ').value(1);
            requests.append(QString::fromUtf8(path));
            QJsonObject response;
            if (path == "/api/health") {
                response = {{"status", "ok"}};
            } else if (path == "/api/shorten") {
                const auto slug = QJsonDocument::fromJson(body).object().value("slug").toString();
                response = {{"shortUrl", origin + "/s/" + slug}};
            } else if (path == "/api/qr/generate") {
                response = {{"dataUrl", "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lS8AAAAASUVORK5CYII="}};
            } else if (path == "/api/drop/upload-chunk" || path == "/api/clip/upload-chunk") {
                if (!header.contains("Content-Range: bytes ") && !header.contains("content-range: bytes "))
                    errors.append("Missing Content-Range");
                if (path == "/api/drop/upload-chunk" && !header.toLower().contains("x-session-id:"))
                    errors.append("Missing Drop session id");
                response = {{"received", body.size()}};
            } else if (path == "/api/drop/finalize") {
                response = {{"url", origin + "/d/demo"}};
            } else if (path == "/api/clip/finalize") {
                response = {{"jobId", "job-demo"}};
            } else if (path.startsWith("/api/jobs/job-demo?")) {
                response = {{"status", "done"}, {"outputJson", QJsonObject{{"clip", QJsonObject{{"url", "/c/demo"}}}}}};
            } else {
                errors.append(QStringLiteral("Unexpected request: %1").arg(QString::fromUtf8(path)));
                response = {{"error", "Unexpected request"}};
            }
            const auto payload = QJsonDocument(response).toJson(QJsonDocument::Compact);
            const auto respond = [socket, payload] {
                if (socket->state() == QAbstractSocket::UnconnectedState)
                    return;
                socket->write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: "
                              + QByteArray::number(payload.size()) + "\r\nConnection: close\r\n\r\n" + payload);
                socket->disconnectFromHost();
            };
            if (path == "/api/shorten" && body.contains("\"slow\""))
                QTimer::singleShot(200, socket, respond);
            else
                respond();
        });
    });

    ToolsClient client;
    client.setServerUrl(origin);
    client.testConnection();
    QTRY_VERIFY_WITH_TIMEOUT(!client.busy(), 10000);
    QVERIFY(client.connected());

    client.shorten("https://example.org/video", "demo");
    QTRY_VERIFY_WITH_TIMEOUT(!client.busy(), 10000);
    QCOMPARE(client.resultUrl().toString(), origin + "/s/demo");

    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto filePath = directory.path() + "/source.mp4";
    QFile file(filePath);
    QVERIFY(file.open(QIODevice::WriteOnly));
    QCOMPARE(file.write(QByteArray(1024 * 1024, 'x')), 1024 * 1024);
    file.close();

    client.publishDrop(QUrl::fromLocalFile(filePath));
    QTRY_VERIFY_WITH_TIMEOUT(!client.busy(), 10000);
    QCOMPARE(client.resultUrl().toString(), origin + "/d/demo");

    client.publishClip(QUrl::fromLocalFile(filePath));
    QTRY_VERIFY_WITH_TIMEOUT(!client.busy(), 10000);
    QCOMPARE(client.resultUrl().toString(), origin + "/c/demo");

    client.shorten("https://example.org/video", "slow");
    QTRY_COMPARE_WITH_TIMEOUT(requests.count("/api/shorten"), 2, 5000);
    client.cancel();
    client.shorten("https://example.org/video", "fast");
    QTRY_VERIFY_WITH_TIMEOUT(!client.busy(), 10000);
    QCOMPARE(client.resultUrl().toString(), origin + "/s/fast");
    QTest::qWait(250);
    QCOMPARE(client.resultUrl().toString(), origin + "/s/fast");
    client.generateQr("https://example.org/video", 512);
    QTRY_VERIFY_WITH_TIMEOUT(!client.busy(), 10000);
    QVERIFY(client.qrPreviewUrl().isLocalFile());
    const auto qrPath = directory.path() + "/qr.png";
    QVERIFY(client.saveQr(QUrl::fromLocalFile(qrPath)));
    QVERIFY(QFileInfo(qrPath).size() > 8);
    QVERIFY2(errors.isEmpty(), qPrintable(errors.join("; ")));
    QCOMPARE(requests.size(), 10);
}

void CoreTests::localMediaOperations()
{
    const auto ffmpeg = qEnvironmentVariable("KADRON_FFMPEG", "ffmpeg");
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto source = directory.path() + "/source.mp4";
    QProcess generator;
    generator.start(ffmpeg, {
        "-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=15",
        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
        "-t", "3", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", source
    });
    QVERIFY(generator.waitForFinished(30000));
    QCOMPARE(generator.exitCode(), 0);

    LocalMediaTools tools;
    QVERIFY(tools.available());
    const auto audio = directory.path() + "/audio.mp3";
    QVERIFY(tools.convertAudio(QUrl::fromLocalFile(source), QUrl::fromLocalFile(audio), "mp3", 192, true, 0.5, 2.0));
    QVERIFY(!tools.compress(QUrl::fromLocalFile(source), QUrl::fromLocalFile(directory.path() + "/other.mp4"), "bad", 70, 1, 320, false));
    QVERIFY(tools.busy());
    QTRY_VERIFY_WITH_TIMEOUT(!tools.busy(), 30000);
    QCOMPARE(tools.errorText(), QString());
    QVERIFY(QFileInfo(audio).size() > 0);

    const auto video = directory.path() + "/small.mp4";
    QVERIFY(tools.compress(QUrl::fromLocalFile(source), QUrl::fromLocalFile(video), "mp4", 60, 0.5, 240, true));
    QTRY_VERIFY_WITH_TIMEOUT(!tools.busy(), 30000);
    QCOMPARE(tools.errorText(), QString());
    QVERIFY(QFileInfo(video).size() > 0);
    QVERIFY(QFileInfo(video).size() <= 0.5 * 1024 * 1024);

    const auto gif = directory.path() + "/clip.gif";
    QVERIFY(tools.createGif(QUrl::fromLocalFile(source), QUrl::fromLocalFile(gif), 0.5, 1.0, 10, 160, 0.5));
    QTRY_VERIFY_WITH_TIMEOUT(!tools.busy(), 30000);
    QCOMPARE(tools.errorText(), QString());
    QVERIFY(QFileInfo(gif).size() > 0);
    QVERIFY(QFileInfo(gif).size() <= 0.5 * 1024 * 1024);

    const auto gifWithoutWidth = directory.path() + "/unlimited-width.gif";
    QVERIFY(tools.compress(QUrl::fromLocalFile(source), QUrl::fromLocalFile(gifWithoutWidth), "gif", 75, 0, 0, true));
    QTRY_VERIFY_WITH_TIMEOUT(!tools.busy(), 30000);
    QCOMPARE(tools.errorText(), QString());
    QVERIFY(QFileInfo(gifWithoutWidth).size() > 0);

    const auto imageSource = directory.path() + "/source.png";
    generator.start(ffmpeg, {
        "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
        "testsrc2=size=640x480:rate=1", "-frames:v", "1", imageSource
    });
    QVERIFY(generator.waitForFinished(30000));
    QCOMPARE(generator.exitCode(), 0);
    const auto image = directory.path() + "/small.webp";
    QVERIFY(tools.compress(QUrl::fromLocalFile(imageSource), QUrl::fromLocalFile(image), "webp", 65, 0.25, 320, false));
    QTRY_VERIFY_WITH_TIMEOUT(!tools.busy(), 30000);
    QCOMPARE(tools.errorText(), QString());
    QVERIFY(QFileInfo(image).size() > 0);
    QVERIFY(QFileInfo(image).size() <= 0.25 * 1024 * 1024);
}

void CoreTests::remoteJobWorkflow()
{
    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost));
    const auto origin = QString("http://127.0.0.1:%1").arg(server.serverPort());
    QStringList requests;
    QStringList errors;
    connect(&server, &QTcpServer::newConnection, &server, [&] {
        auto *socket = server.nextPendingConnection();
        connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
            auto pending = socket->property("pending").toByteArray() + socket->readAll();
            const auto headerEnd = pending.indexOf("\r\n\r\n");
            if (headerEnd < 0) {
                socket->setProperty("pending", pending);
                return;
            }
            const auto header = pending.left(headerEnd);
            qint64 length = 0;
            for (const auto &line : header.split('\n')) {
                if (line.trimmed().toLower().startsWith("content-length:"))
                    length = line.trimmed().mid(15).trimmed().toLongLong();
            }
            const auto body = pending.mid(headerEnd + 4);
            if (body.size() < length) {
                socket->setProperty("pending", pending);
                return;
            }
            const auto path = header.split(' ').value(1);
            requests.append(QString::fromUtf8(path));
            QByteArray payload;
            if (path == "/api/downloader") {
                if (body.contains("VIDEO_GIF_SOCIAL"))
                    payload = R"({"jobId":"job-gif"})";
                else {
                    if (!body.contains("VIDEO_MP4_720P")) errors.append("Download preset missing");
                    payload = R"({"jobId":"job-download"})";
                }
            } else if (path == "/api/pdf/merge") {
                if (!body.contains("a.pdf") || !body.contains("b.pdf")) errors.append("PDF files missing");
                payload = R"({"jobId":"job-pdf"})";
            } else if (path.startsWith("/api/jobs/job-download?")) {
                payload = R"({"status":"done","outputJson":{"files":[{"filename":"remote.mp4","size":10}]}})";
            } else if (path.startsWith("/api/jobs/job-gif?")) {
                payload = R"({"status":"done","outputJson":{"files":[{"filename":"remote.gif","size":10}],"gif":{"overTarget":true}}})";
            } else if (path.startsWith("/api/jobs/job-pdf?")) {
                payload = R"({"status":"done","outputJson":{"files":[{"filename":"merged.pdf","size":8}]}})";
            } else if (path.startsWith("/api/files/job-download/")) {
                payload = "video-data";
            } else if (path.startsWith("/api/files/job-pdf/")) {
                payload = "pdf-data";
            } else {
                errors.append(QStringLiteral("Unexpected request: %1").arg(QString::fromUtf8(path)));
                payload = R"({"error":"Unexpected request"})";
            }
            socket->write("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: "
                          + QByteArray::number(payload.size()) + "\r\nConnection: close\r\n\r\n" + payload);
            socket->disconnectFromHost();
        });
    });

    ToolsClient tools;
    tools.setServerUrl(origin);
    RemoteJobsClient jobs(&tools);
    QVERIFY(jobs.download("https://example.org/watch?v=1", "VIDEO_MP4_720P", 0, 8, 10, 480, 8));
    QTRY_VERIFY_WITH_TIMEOUT(!jobs.busy(), 10000);
    QVERIFY(jobs.resultAvailable());
    QCOMPARE(jobs.outputFilename(), QString("remote.mp4"));
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto video = directory.path() + "/saved.mp4";
    QVERIFY(jobs.saveResult(QUrl::fromLocalFile(video)));
    QTRY_VERIFY_WITH_TIMEOUT(!jobs.busy(), 10000);
    QFile savedVideo(video);
    QVERIFY(savedVideo.open(QIODevice::ReadOnly));
    QCOMPARE(savedVideo.readAll(), QByteArray("video-data"));

    QVERIFY(jobs.download("https://example.org/watch?v=1", "VIDEO_GIF_SOCIAL", 0, 8, 10, 480, 1));
    QTRY_VERIFY_WITH_TIMEOUT(!jobs.busy(), 10000);
    QVERIFY(jobs.overTarget());
    QCOMPARE(jobs.outputFilename(), QString("remote.gif"));

    QVariantList files;
    for (const auto &name : {"a.pdf", "b.pdf"}) {
        const auto path = directory.path() + "/" + name;
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        QVERIFY(file.write("%PDF-1.4") > 0);
        file.close();
        files.append(QUrl::fromLocalFile(path));
    }
    QVERIFY(jobs.pdfAction("merge", files, "", 0));
    QTRY_VERIFY_WITH_TIMEOUT(!jobs.busy(), 10000);
    QCOMPARE(jobs.outputFilename(), QString("merged.pdf"));
    const auto pdf = directory.path() + "/saved.pdf";
    QVERIFY(jobs.saveResult(QUrl::fromLocalFile(pdf)));
    QTRY_VERIFY_WITH_TIMEOUT(!jobs.busy(), 10000);
    QFile savedPdf(pdf);
    QVERIFY(savedPdf.open(QIODevice::ReadOnly));
    QCOMPARE(savedPdf.readAll(), QByteArray("pdf-data"));
    QVERIFY2(errors.isEmpty(), qPrintable(errors.join("; ")));
    QCOMPARE(requests.size(), 8);
}

QTEST_GUILESS_MAIN(CoreTests)
#include "core_tests.moc"
