#include "EditorProject.h"
#include "ExportController.h"
#include "ThumbnailStrip.h"

#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QTemporaryDir>
#include <QtTest>

class CoreTests final : public QObject
{
    Q_OBJECT

private slots:
    void projectRoundTrip();
    void mediaExport();
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
    QVERIFY(!thumbnails.frames().isEmpty());

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

QTEST_GUILESS_MAIN(CoreTests)
#include "core_tests.moc"
