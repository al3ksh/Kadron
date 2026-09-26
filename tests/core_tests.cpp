#include "AppUpdater.h"
#include "EditorProject.h"
#include "ExportController.h"
#include "ThumbnailStrip.h"
#include "ToolsClient.h"
#include "LocalMediaTools.h"
#include "RemoteJobsClient.h"
#include "MediaTools.h"
#include "LocalPdfTools.h"
#include "LocalDownload.h"
#include "LocalQr.h"

#include <QCryptographicHash>
#include <QFile>
#include <QStandardPaths>
#include <QImage>
#include <QImageReader>
#include <QFileInfo>
#include <QDir>
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
    void sequenceExport();
    void remoteWorkflow();
    void localMediaOperations();
    void remoteJobWorkflow();
    void localPdfOperations();
    void localDownloadWorkflow();
    void localQrWorkflow();
    void ytDlpDiagnostics();
    void editHistory();
    void appUpdates();
};

void CoreTests::editHistory()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto media = QUrl::fromLocalFile(directory.path() + "/clip.mp4");
    QFile file(media.toLocalFile());
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write("x");
    file.close();

    EditorProject project;
    QVERIFY(project.importMedia(media));
    project.setDurationMs(10000);
    QVERIFY2(!project.canUndo(), "discovering the duration is not an edit");

    QVERIFY(project.setClipRange(0, 1000, 8000));
    QVERIFY(project.splitAt(4000));
    QCOMPARE(project.clipCount(), 2);
    QVERIFY(project.canUndo());

    QVERIFY(project.undo());
    QCOMPARE(project.clipCount(), 1);
    QCOMPARE(project.inMs(), 1000);
    QCOMPARE(project.outMs(), 8000);
    QVERIFY(project.undo());
    QCOMPARE(project.inMs(), 0);
    QCOMPARE(project.outMs(), 10000);
    QVERIFY(!project.canUndo());

    QVERIFY(project.redo());
    QCOMPARE(project.outMs(), 8000);
    QVERIFY(project.redo());
    QCOMPARE(project.clipCount(), 2);
    QVERIFY(!project.canRedo());

    // A new edit after undo discards the redo branch.
    QVERIFY(project.undo());
    QVERIFY(project.canRedo());
    project.setOutMs(7000);
    QVERIFY(!project.canRedo());

    // Importing starts a fresh history.
    QVERIFY(project.importMedia(media));
    QVERIFY(!project.canUndo());
}

void CoreTests::ytDlpDiagnostics()
{
    QCOMPARE(LocalDownload::versionDate("2025.09.26"), QDate(2025, 9, 26));
    QCOMPARE(LocalDownload::versionDate("2026.01.02.1\n"), QDate(2026, 1, 2));
    QVERIFY(!LocalDownload::versionDate("nightly").isValid());
    const auto stderrText = QStringLiteral(
        "WARNING: You are using an outdated version of yt-dlp (older than 90 days)\n"
        "WARNING: [youtube] abc: nsig extraction failed\n"
        "ERROR: [youtube] abc: Requested format is not available\n");
    QCOMPARE(LocalDownload::summarizeError(stderrText), QString("[youtube] abc: Requested format is not available"));
    QCOMPARE(LocalDownload::summarizeError("WARNING: only a warning\nplain failure"), QString("plain failure"));

    QCOMPARE(LocalDownload::youtubeId("https://www.youtube.com/watch?v=jNQXAC9IVRw&t=3"), QString("jNQXAC9IVRw"));
    QCOMPARE(LocalDownload::youtubeId("https://youtu.be/jNQXAC9IVRw"), QString("jNQXAC9IVRw"));
    QCOMPARE(LocalDownload::youtubeId("https://youtube.com/shorts/abcdefghijk"), QString("abcdefghijk"));
    QVERIFY(LocalDownload::youtubeId("https://vimeo.com/123").isEmpty());
    QCOMPARE(LocalDownload::safeFileName("A/B: C*? <clip>."), QString("A B C clip"));
    const auto meta = LocalDownload::pageMetadata(
        QStringLiteral("<meta content='/img/t.jpg' property='og:image'><meta property=\"og:title\" content=\"Tom &amp; Jerry\">"),
        QUrl("https://example.com/watch/1"));
    QCOMPARE(meta.value("thumbnail").toString(), QString("https://example.com/img/t.jpg"));
    QCOMPARE(meta.value("title").toString(), QString("Tom & Jerry"));
}

void CoreTests::localQrWorkflow()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    LocalQr qr;
    if (!qr.available()) QSKIP("qrencode is not installed");
    qr.update("https://example.com/kadron", "M");
    QTRY_VERIFY_WITH_TIMEOUT(!qr.busy(), 10000);
    QVERIFY2(qr.errorText().isEmpty(), qPrintable(qr.errorText()));
    QCOMPARE(qr.modules(), 25);

    const auto image = qr.render(290, Qt::black, Qt::white);
    QCOMPARE(image.size(), QSize(290, 290));
    // Finder pattern: top-left module (inside the 2-module margin) is dark, the margin is light.
    QCOMPARE(image.pixelColor(10 * 2 + 5, 10 * 2 + 5), QColor(Qt::black));
    QCOMPARE(image.pixelColor(5, 5), QColor(Qt::white));

    const auto png = QUrl::fromLocalFile(directory.path() + "/code.png");
    QVERIFY(qr.save(png, 512, QColor("#1a5fb4"), Qt::white));
    QImageReader reader(png.toLocalFile());
    QCOMPARE(reader.size(), QSize(512, 512));
    QVERIFY(!qr.save(png, 512, Qt::black, Qt::white));
    QVERIFY(qr.errorText().contains("never overwritten"));

    const auto svg = QUrl::fromLocalFile(directory.path() + "/code.svg");
    QVERIFY(qr.save(svg, 512, Qt::black, Qt::white));
    QFile svgFile(svg.toLocalFile());
    QVERIFY(svgFile.open(QIODevice::ReadOnly));
    QVERIFY(svgFile.readAll().startsWith("<svg"));

    qr.update("", "M");
    QCOMPARE(qr.modules(), 0);
}

void CoreTests::localDownloadWorkflow()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto source = directory.path() + "/source.mp4";
    QProcess generator;
    generator.start(ffmpegExecutable(), {"-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=10",
        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
        "-t", "2", "-c:v", "libx264", "-c:a", "aac", source});
    QVERIFY(generator.waitForFinished(30000));
    QCOMPARE(generator.exitCode(), 0);
    QFile file(source);
    QVERIFY(file.open(QIODevice::ReadOnly));
    const auto media = file.readAll();

    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost));
    connect(&server, &QTcpServer::newConnection, &server, [&server, media] {
        while (auto *socket = server.nextPendingConnection()) {
            QObject::connect(socket, &QTcpSocket::readyRead, socket, [socket, media] {
                const auto request = socket->readAll();
                if (!request.contains("\r\n\r\n")) return;
                const auto header = QByteArray("HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nContent-Length: ")
                    + QByteArray::number(media.size()) + "\r\nConnection: close\r\n\r\n";
                socket->write(header);
                if (!request.startsWith("HEAD ")) socket->write(media);
                socket->disconnectFromHost();
            });
            QObject::connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        }
    });
    const auto url = QStringLiteral("http://127.0.0.1:%1/source.mp4").arg(server.serverPort());
    LocalDownload download;
    if (!download.available()) QSKIP("yt-dlp or FFmpeg is not installed");
    const auto mp4 = QUrl::fromLocalFile(directory.path() + "/download.mp4");
    QVERIFY(download.download(url, "VIDEO_MP4_BEST", mp4, 0, 1, 10, 120, 0));
    QTRY_VERIFY_WITH_TIMEOUT(!download.busy(), 60000);
    QVERIFY2(download.errorText().isEmpty(), qPrintable(download.errorText()));
    QVERIFY(QFileInfo(mp4.toLocalFile()).size() > 100);

    const auto mp3 = QUrl::fromLocalFile(directory.path() + "/download.mp3");
    QVERIFY(download.download(url, "AUDIO_MP3_192", mp3, 0, 1, 10, 120, 0));
    QTRY_VERIFY_WITH_TIMEOUT(!download.busy(), 60000);
    QVERIFY2(download.errorText().isEmpty(), qPrintable(download.errorText()));
    QVERIFY(QFileInfo(mp3.toLocalFile()).size() > 100);

    const auto gif = QUrl::fromLocalFile(directory.path() + "/download.gif");
    QVERIFY(download.download(url, "VIDEO_GIF_SOCIAL", gif, 0, 1, 10, 120, 0));
    QTRY_VERIFY_WITH_TIMEOUT(!download.busy(), 60000);
    QVERIFY2(download.errorText().isEmpty(), qPrintable(download.errorText()));
    QVERIFY(QFileInfo(gif.toLocalFile()).size() > 100);
    QImageReader reader(gif.toLocalFile());
    QVERIFY(reader.canRead());
}

void CoreTests::localPdfOperations()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto firstImage = directory.path() + "/first.png";
    const auto secondImage = directory.path() + "/second.png";
    QImage image(120, 80, QImage::Format_RGB32);
    image.fill(Qt::red);
    QVERIFY(image.save(firstImage));
    image.fill(Qt::blue);
    QVERIFY(image.save(secondImage));

    LocalPdfTools pdf;
    const auto firstPdf = directory.path() + "/first.pdf";
    const auto secondPdf = directory.path() + "/second.pdf";
    const auto pdfUrl = [](const QString &path) { return QUrl::fromLocalFile(path); };
    QVERIFY(pdf.process("images-to-pdf", {pdfUrl(firstImage)}, "", 90, pdfUrl(firstPdf)));
    QTRY_VERIFY_WITH_TIMEOUT(!pdf.busy(), 30000);
    QVERIFY2(pdf.errorText().isEmpty(), qPrintable(pdf.errorText()));
    QVERIFY(QFileInfo(firstPdf).size() > 100);
    QVERIFY(pdf.process("images-to-pdf", {pdfUrl(secondImage)}, "", 90, pdfUrl(secondPdf)));
    QTRY_VERIFY_WITH_TIMEOUT(!pdf.busy(), 30000);
    QVERIFY2(pdf.errorText().isEmpty(), qPrintable(pdf.errorText()));

    if (!pdf.qpdfAvailable()) QSKIP("qpdf is not installed");
    const auto merged = directory.path() + "/merged.pdf";
    QVERIFY(pdf.process("merge", {pdfUrl(firstPdf), pdfUrl(secondPdf)}, "", 90, pdfUrl(merged)));
    QTRY_VERIFY_WITH_TIMEOUT(!pdf.busy(), 30000);
    QVERIFY2(pdf.errorText().isEmpty(), qPrintable(pdf.errorText()));
    QProcess pages;
    pages.start(qpdfExecutable(), {"--show-npages", merged});
    QVERIFY(pages.waitForFinished(30000));
    QCOMPARE(QString::fromUtf8(pages.readAllStandardOutput()).trimmed(), QStringLiteral("2"));

    for (const auto &operation : QStringList{"split", "rotate", "remove-pages", "reorder"}) {
        const auto output = directory.path() + "/" + operation + ".pdf";
        const auto range = operation == "reorder" ? QStringLiteral("2,1") : QStringLiteral("1");
        QVERIFY(pdf.process(operation, {pdfUrl(merged)}, range, 90, pdfUrl(output)));
        QTRY_VERIFY_WITH_TIMEOUT(!pdf.busy(), 30000);
        QVERIFY2(pdf.errorText().isEmpty(), qPrintable(pdf.errorText()));
        QVERIFY(QFileInfo(output).size() > 100);
        QProcess count;
        count.start(qpdfExecutable(), {"--show-npages", output});
        QVERIFY(count.waitForFinished(30000));
        QCOMPARE(QString::fromUtf8(count.readAllStandardOutput()).trimmed(),
                 operation == "rotate" || operation == "reorder" ? QStringLiteral("2") : QStringLiteral("1"));
    }

    const QVariantList order{QVariantMap{{"page", 2}, {"rotation", 0}}, QVariantMap{{"page", 1}, {"rotation", -90}}};
    QCOMPARE(LocalPdfTools::composeArguments("in.pdf", order, "out.pdf"),
             (QStringList{"--empty", "--pages", "in.pdf", "2,1", "--", "--rotate=+270:2", "out.pdf"}));

    if (!pdf.pagesAvailable()) QSKIP("pdftoppm is not installed");
    pdf.loadPages(pdfUrl(merged));
    QVERIFY(pdf.loadingPages());
    QTRY_VERIFY_WITH_TIMEOUT(!pdf.loadingPages(), 30000);
    QVERIFY2(pdf.pagesError().isEmpty(), qPrintable(pdf.pagesError()));
    QCOMPARE(pdf.pageImages().size(), 2);
    QVERIFY(!QImage(QUrl(pdf.pageImages().first()).toLocalFile()).isNull());

    QSignalSpy preview(&pdf, &LocalPdfTools::pagePreviewReady);
    pdf.renderPreview(2);
    QTRY_COMPARE_WITH_TIMEOUT(preview.size(), 1, 30000);
    QCOMPARE(preview.first().at(0).toInt(), 2);

    const auto composed = directory.path() + "/composed.pdf";
    QVERIFY(pdf.compose({QVariantMap{{"page", 2}, {"rotation", 90}}}, pdfUrl(composed)));
    QTRY_VERIFY_WITH_TIMEOUT(!pdf.busy(), 30000);
    QVERIFY2(pdf.errorText().isEmpty(), qPrintable(pdf.errorText()));
    QProcess count;
    count.start(qpdfExecutable(), {"--show-npages", composed});
    QVERIFY(count.waitForFinished(30000));
    QCOMPARE(QString::fromUtf8(count.readAllStandardOutput()).trimmed(), QStringLiteral("1"));
    QVERIFY(!pdf.compose({QVariantMap{{"page", 1}, {"rotation", 0}}}, pdfUrl(composed)));
    QVERIFY(!pdf.compose({QVariantMap{{"page", 9}, {"rotation", 0}}}, pdfUrl(directory.path() + "/bad.pdf")));
}

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
    QCOMPARE(reopened.projectUrl().toLocalFile(), projectPath);
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
    QVERIFY(thumbnails.frames().size() >= 10);
    QVERIFY(!thumbnails.frames().first().isEmpty());
    thumbnails.waveformFor(QUrl::fromLocalFile(sourcePath));
    QTRY_VERIFY_WITH_TIMEOUT(!thumbnails.waveformFor(QUrl::fromLocalFile(sourcePath)).isEmpty(), 30000);

    ExportController exporter;
    QVERIFY(exporter.available());
    QVERIFY(exporter.start(QUrl::fromLocalFile(sourcePath), QUrl::fromLocalFile(outputPath), 1000, 3000));
    QTRY_VERIFY_WITH_TIMEOUT(!exporter.busy(), 60000);
    QCOMPARE(exporter.errorText(), QString());
    QCOMPARE(exporter.progress(), 100);
    QVERIFY(QFileInfo(outputPath).size() > 0);
    QCOMPARE(exporter.outputUrl().toLocalFile(), outputPath);

    const auto ffprobe = ffprobeExecutable();
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

void CoreTests::sequenceExport()
{
    const auto ffmpeg = qEnvironmentVariable("KADRON_FFMPEG", "ffmpeg");
    const auto ffprobe = ffprobeExecutable();
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto videoPath = directory.path() + "/video.mp4";
    const auto audioPath = directory.path() + "/audio.wav";
    const auto silentPath = directory.path() + "/silent.mp4";
    QProcess generator;
    generator.start(ffmpeg, {"-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                             "testsrc2=size=320x180:rate=15", "-f", "lavfi", "-i",
                             "sine=frequency=440:sample_rate=48000", "-t", "2", "-c:v", "libx264",
                             "-c:a", "aac", videoPath});
    QVERIFY(generator.waitForFinished(30000));
    QCOMPARE(generator.exitCode(), 0);
    generator.start(ffmpeg, {"-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                             "sine=frequency=660:sample_rate=48000", "-t", "2", audioPath});
    QVERIFY(generator.waitForFinished(30000));
    QCOMPARE(generator.exitCode(), 0);
    generator.start(ffmpeg, {"-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                             "testsrc2=size=480x270:rate=24", "-t", "2", "-c:v", "libx264", silentPath});
    QVERIFY(generator.waitForFinished(30000));
    QCOMPARE(generator.exitCode(), 0);

    EditorProject project;
    QVERIFY(project.importMedia(QUrl::fromLocalFile(videoPath)));
    project.setDurationMs(2000);
    project.setOutMs(1200);
    QVERIFY(project.appendMedia(QUrl::fromLocalFile(audioPath)));
    project.setDurationMs(2000);
    project.setOutMs(1300);
    QVERIFY(project.appendMedia(QUrl::fromLocalFile(silentPath)));
    project.setDurationMs(2000);
    project.setOutMs(1400);
    QVERIFY(project.canExport());

    ExportController exporter;
    const auto outputPath = directory.path() + "/sequence.mp4";
    QVERIFY(exporter.startSequence(project.clips(), QUrl::fromLocalFile(outputPath)));
    QTRY_VERIFY_WITH_TIMEOUT(!exporter.busy(), 120000);
    QVERIFY2(exporter.errorText().isEmpty(), qPrintable(exporter.errorText()));
    QCOMPARE(exporter.progress(), 100);
    QVERIFY(QFileInfo(outputPath).size() > 0);

    QProcess probe;
    probe.start(ffprobe, {"-v", "error", "-show_entries", "format=duration:stream=codec_type,width,height",
                          "-of", "json", outputPath});
    QVERIFY(probe.waitForFinished(30000));
    QCOMPARE(probe.exitCode(), 0);
    const auto metadata = QJsonDocument::fromJson(probe.readAllStandardOutput()).object();
    const auto duration = metadata.value("format").toObject().value("duration").toString().toDouble();
    QVERIFY2(duration > 3.4 && duration < 4.3, qPrintable(QString("Unexpected sequence duration: %1").arg(duration)));
    const auto streams = metadata.value("streams").toArray();
    bool hasVideo = false;
    bool hasAudio = false;
    for (const auto &entry : streams) {
        const auto stream = entry.toObject();
        if (stream.value("codec_type") == "video") {
            hasVideo = true;
            QCOMPARE(stream.value("width").toInt(), 320);
            QCOMPARE(stream.value("height").toInt(), 180);
        }
        if (stream.value("codec_type") == "audio") hasAudio = true;
    }
    QVERIFY(hasVideo);
    QVERIFY(hasAudio);
    QDir outputDirectory(directory.path());
    QVERIFY(outputDirectory.entryList({".kadron-sequence-*"}, QDir::Dirs | QDir::Hidden | QDir::NoDotAndDotDot).isEmpty());
    QVERIFY(outputDirectory.entryList({"*.part.mp4"}, QDir::Files | QDir::Hidden).isEmpty());

    const auto cancelledPath = directory.path() + "/cancelled.mp4";
    QVERIFY(exporter.startSequence(project.clips(), QUrl::fromLocalFile(cancelledPath)));
    exporter.cancel();
    QTRY_VERIFY_WITH_TIMEOUT(!exporter.busy(), 10000);
    QCOMPARE(exporter.stage(), QString("Cancelled"));
    QVERIFY(!QFileInfo(cancelledPath).exists());
    QVERIFY(outputDirectory.entryList({".kadron-sequence-*"}, QDir::Dirs | QDir::Hidden | QDir::NoDotAndDotDot).isEmpty());
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

void CoreTests::appUpdates()
{
    const QByteArray release = R"({"tag_name":"v0.2.0","html_url":"https://example.org/r/v0.2.0","draft":false,"prerelease":false,
        "assets":[{"name":"Kadron-0.2.0-win64-portable.zip","browser_download_url":"https://example.org/zip","size":5},
                  {"name":"Kadron-0.2.0-setup.exe","browser_download_url":"https://example.org/setup","size":42,
                   "digest":"sha256:ABCDEF0123"}]})";
    const auto parsed = AppUpdater::parseRelease(release);
    QCOMPARE(parsed.value("version").toString(), QString("0.2.0"));
    QCOMPARE(parsed.value("page").toUrl(), QUrl("https://example.org/r/v0.2.0"));
    QCOMPARE(parsed.value("assetName").toString(), QString("Kadron-0.2.0-setup.exe"));
    QCOMPARE(parsed.value("asset").toUrl(), QUrl("https://example.org/setup"));
    QCOMPARE(parsed.value("size").toLongLong(), 42);
    QCOMPARE(parsed.value("sha256").toString(), QString("abcdef0123"));
    QVERIFY(AppUpdater::parseRelease(R"({"tag_name":"v0.3.0","draft":true})").isEmpty());
    QVERIFY(AppUpdater::parseRelease(R"({"tag_name":"nightly"})").isEmpty());
    QVERIFY(AppUpdater::parseRelease("not json").isEmpty());

    QVERIFY(AppUpdater::isNewer("v0.2.0", "0.1.0"));
    QVERIFY(AppUpdater::isNewer("0.1.10", "0.1.9"));
    QVERIFY(!AppUpdater::isNewer("0.1.0", "0.1.0"));
    QVERIFY(!AppUpdater::isNewer("0.0.9", "0.1.0"));
    QVERIFY(!AppUpdater::isNewer("", "0.1.0"));

    // check() against a local stand-in for the GitHub API.
    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost));
    const auto origin = QString("http://127.0.0.1:%1").arg(server.serverPort());
    QByteArray status = "200 OK";
    QByteArray latest = release;
    const QByteArray installer(4096, 'k');
    QByteArray served = installer;
    connect(&server, &QTcpServer::newConnection, &server, [&] {
        auto *socket = server.nextPendingConnection();
        connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
            const auto request = socket->readAll();
            const QByteArray payload = !status.startsWith("200") ? QByteArray(R"({"message":"Not Found"})")
                                       : request.startsWith("GET /setup") ? served : latest;
            socket->write("HTTP/1.1 " + status + "\r\nContent-Type: application/json\r\nContent-Length: "
                          + QByteArray::number(payload.size()) + "\r\nConnection: close\r\n\r\n" + payload);
            socket->disconnectFromHost();
        });
    });
    qputenv("KADRON_UPDATE_URL", QString("http://127.0.0.1:%1/latest").arg(server.serverPort()).toUtf8());
    QCoreApplication::setApplicationVersion("0.1.0");

    AppUpdater updater;
    updater.check();
    QVERIFY(updater.checking());
    QTRY_VERIFY_WITH_TIMEOUT(!updater.checking(), 10000);
    QVERIFY(updater.updateAvailable());
    QCOMPARE(updater.latestVersion(), QString("0.2.0"));
    QCOMPARE(updater.statusText(), QString("Kadron 0.2.0 is available"));
    QCOMPARE(updater.releaseUrl(), QUrl("https://example.org/r/v0.2.0"));
    // The test binary has no uninstaller beside it, like a portable copy.
    QVERIFY(!updater.canInstall());
    updater.install();
    QVERIFY(!updater.downloading());
    QCOMPARE(updater.statusText(), QString("Download Kadron 0.2.0 from the release page"));

    // No published release yet.
    status = "404 Not Found";
    AppUpdater fresh;
    fresh.check();
    QTRY_VERIFY_WITH_TIMEOUT(!fresh.checking(), 10000);
    QVERIFY(!fresh.updateAvailable());
    QCOMPARE(fresh.statusText(), QString("Kadron 0.1.0 is up to date"));

    // An installed copy (uninstaller beside the executable) downloads the
    // setup and accepts it only if size and SHA-256 match the release.
    status = "200 OK";
    const auto hash = QCryptographicHash::hash(installer, QCryptographicHash::Sha256).toHex();
    latest = QString(R"({"tag_name":"v0.2.0","html_url":"https://example.org/r","assets":[{"name":"Kadron-0.2.0-setup.exe",
        "browser_download_url":"%1/setup","size":%2,"digest":"sha256:%3"}]})")
                 .arg(origin).arg(installer.size()).arg(QString::fromLatin1(hash)).toUtf8();
    const auto marker = QCoreApplication::applicationDirPath() + "/uninstall.exe";
    QFile markerFile(marker);
    QVERIFY(markerFile.open(QIODevice::WriteOnly));
    markerFile.close();
    const auto downloaded = QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation)).filePath("Kadron-0.2.0-setup.exe");
    QFile::remove(downloaded);
    {
        AppUpdater installed;
        QVERIFY(installed.canInstall());
        installed.check();
        QTRY_VERIFY_WITH_TIMEOUT(installed.updateAvailable(), 10000);
        served = installer;
        served[100] = 'x';
        installed.install();
        QVERIFY(installed.downloading());
        QTRY_VERIFY_WITH_TIMEOUT(!installed.downloading(), 10000);
        QVERIFY(!installed.ready());
        QCOMPARE(installed.statusText(), QString("The downloaded update did not match the release; nothing was installed."));
        QVERIFY(!QFileInfo::exists(downloaded));

        served = installer.left(1000);
        installed.install();
        QTRY_VERIFY_WITH_TIMEOUT(!installed.downloading(), 10000);
        QVERIFY(!installed.ready());

        served = installer;
        installed.install();
        QTRY_VERIFY_WITH_TIMEOUT(!installed.downloading(), 10000);
        QVERIFY(installed.ready());
        QCOMPARE(installed.progress(), 1.0);
        QCOMPARE(installed.statusText(), QString("Kadron 0.2.0 is ready to install"));
        QFile file(downloaded);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), installer);
        // A ready update is not downloaded again or re-checked.
        installed.check();
        QVERIFY(!installed.checking());
        // Destroying the updater drops its aboutToQuit hook, so the fake
        // installer is never started.
    }
    QFile::remove(downloaded);
    QFile::remove(marker);
    qunsetenv("KADRON_UPDATE_URL");
}

QTEST_GUILESS_MAIN(CoreTests)
#include "core_tests.moc"
