#include "EditorProject.h"
#include "ExportController.h"
#include "ThumbnailStrip.h"
#include "ToolsClient.h"

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
    void mediaExport();
    void remoteWorkflow();
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
    QVERIFY2(errors.isEmpty(), qPrintable(errors.join("; ")));
    QCOMPARE(requests.size(), 9);
}

QTEST_GUILESS_MAIN(CoreTests)
#include "core_tests.moc"
