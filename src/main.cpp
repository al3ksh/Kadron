#include "EditorProject.h"
#include "ExportController.h"
#include "ThumbnailStrip.h"
#include "ToolsClient.h"
#include "LocalMediaTools.h"
#include "LocalDownload.h"
#include "LocalPdfTools.h"
#include "LocalQr.h"
#include "WindowChrome.h"
#include "AppUpdater.h"

#include <QGuiApplication>
#include <QStyleHints>
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QFont>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlExtensionPlugin>
#include <QQmlContext>
#include <QQuickWindow>
#include <QQuickStyle>
#include <QTimer>
#include <QEventLoop>
#include <QScreen>
#include <QTemporaryDir>
#include <QSettings>
#include <QTextStream>

Q_IMPORT_QML_PLUGIN(KadronPlugin)

static void fileMessageHandler(QtMsgType, const QMessageLogContext &, const QString &message)
{
    QFile file(qEnvironmentVariable("KADRON_LOG_FILE"));
    if (file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QTextStream stream(&file);
        stream << message << '\n';
    }
}

// Where the app opens: centred on the primary screen at up to 1440x900, with
// room for the caption above the client area.
static QRect startupGeometry()
{
    const auto available = QGuiApplication::primaryScreen()->availableGeometry();
    const int caption = 32;
    const QSize size(qMin(1440, available.width() - 16), qMin(900, available.height() - caption - 16));
    return QRect(available.x() + (available.width() - size.width()) / 2,
                 available.y() + caption + (available.height() - caption - size.height()) / 2,
                 size.width(), size.height());
}

int main(int argc, char *argv[])
{
    if (qEnvironmentVariableIsSet("KADRON_LOG_FILE"))
        qInstallMessageHandler(fileMessageHandler);
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("Kadron"));
    app.setOrganizationDomain(QStringLiteral("aleksh.xyz"));
    app.setApplicationName(QStringLiteral("Kadron"));
    app.setApplicationVersion(QStringLiteral(KADRON_VERSION));
    // Bundled tools live in bin/ and share the DLLs next to kadron.exe; child
    // processes inherit PATH, so they find them without a second copy.
    qputenv("PATH", QDir::toNativeSeparators(QCoreApplication::applicationDirPath()).toLocal8Bit()
                        + QDir::listSeparator().toLatin1() + qgetenv("PATH"));
    app.setFont(QFont(QStringLiteral("Segoe UI"), 10));
    app.setWindowIcon(QIcon(QStringLiteral(":/assets/kadron-mark.png")));
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    app.styleHints()->setColorScheme(Qt::ColorScheme::Dark);

    EditorProject project;
    ExportController exporter;
    ThumbnailStrip thumbnails;
    ToolsClient toolsClient;
    LocalMediaTools localTools;
    LocalDownload localDownload;
    LocalPdfTools localPdf;
    LocalQr localQr;
    AppUpdater appUpdater;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("editorProject", &project);
    engine.rootContext()->setContextProperty("exporter", &exporter);
    engine.rootContext()->setContextProperty("thumbnails", &thumbnails);
    engine.rootContext()->setContextProperty("toolsClient", &toolsClient);
    engine.rootContext()->setContextProperty("localTools", &localTools);
    engine.rootContext()->setContextProperty("localDownload", &localDownload);
    engine.rootContext()->setContextProperty("localPdf", &localPdf);
    engine.rootContext()->setContextProperty("localQr", &localQr);
    engine.rootContext()->setContextProperty("appUpdater", &appUpdater);
    engine.addImageProvider(QStringLiteral("qr"), new QrImageProvider(&localQr));
    QTemporaryDir screenshotSettings;
    const auto screenshotPath = qEnvironmentVariable("KADRON_SCREENSHOT");
    const bool playIntro = screenshotPath.isEmpty() && !qEnvironmentVariableIsSet("KADRON_NO_INTRO")
                           && QSettings().value(QStringLiteral("preferences/startupIntro"), true).toBool();
    engine.rootContext()->setContextProperty("startupIntroActive", playIntro);
    // Screenshot runs keep their preferences in a throwaway store and can pick
    // the appearance, so they never change the user's own settings.
    if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT")) {
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, screenshotSettings.path());
        if (auto *prefs = engine.singletonInstance<QObject *>("Kadron", "Prefs")) {
            if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_THEME"))
                prefs->setProperty("themeMode", qEnvironmentVariable("KADRON_SCREENSHOT_THEME"));
            if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_ACCENT"))
                prefs->setProperty("accent", qEnvironmentVariable("KADRON_SCREENSHOT_ACCENT"));
        }
    }
    // KADRON_SCREENSHOT_INTRO=<seconds> grabs that moment of the intro instead of the app.
    if (!screenshotPath.isEmpty() && qEnvironmentVariableIsSet("KADRON_SCREENSHOT_INTRO")) {
        engine.loadFromModule("Kadron", "Intro");
        auto *shot = qobject_cast<QQuickWindow *>(engine.rootObjects().value(0));
        if (!shot)
            return 1;
        shot->setProperty("frozenAt", qEnvironmentVariable("KADRON_SCREENSHOT_INTRO").toDouble());
        const auto dimensions = qEnvironmentVariable("KADRON_SCREENSHOT_SIZE", "1440x900").split('x');
        shot->resize(dimensions.value(0).toInt(), dimensions.value(1).toInt());
        shot->show();
        QTimer::singleShot(800, &app, [&app, shot, screenshotPath] {
            shot->grabWindow().save(screenshotPath);
            app.quit();
        });
        return app.exec();
    }
    // The intro goes up first and animates on the render thread while the
    // main window (and QtMultimedia behind it) loads on this one.
    QQuickWindow *intro = nullptr;
    if (playIntro) {
        engine.loadFromModule("Kadron", "Intro");
        intro = qobject_cast<QQuickWindow *>(engine.rootObjects().value(0));
    }
    if (intro) {
        intro->setGeometry(startupGeometry());
        roundWindowCorners(intro);
        intro->show();
        QEventLoop firstFrame;
        QObject::connect(intro, &QQuickWindow::frameSwapped, &firstFrame, &QEventLoop::quit, Qt::QueuedConnection);
        QTimer::singleShot(700, &firstFrame, &QEventLoop::quit);
        firstFrame.exec();
    }

    engine.loadFromModule("Kadron", "Main");
    auto *mainWindow = qobject_cast<QQuickWindow *>(engine.rootObjects().value(intro ? 1 : 0));
    if (!mainWindow)
        return 1;
    new WindowChromeWatcher(mainWindow);

    if (intro) {
        // Same client area as the intro, so the app appears exactly where it played.
        mainWindow->setGeometry(intro->geometry());
        auto *handoff = new IntroHandoff(intro, mainWindow);
        QObject::connect(intro, SIGNAL(finished()), handoff, SLOT(finish()));
        handoff->prepare();
        QObject::connect(intro, SIGNAL(finished()), mainWindow, SLOT(revealAfterIntro()));
        intro->setProperty("appReady", true);
    }

    const auto arguments = app.arguments();
    if (arguments.size() > 1 && !arguments.at(1).startsWith("--")) {
        const auto input = QUrl::fromLocalFile(QFileInfo(arguments.at(1)).absoluteFilePath());
        if (QFileInfo(arguments.at(1)).suffix().compare("kadr", Qt::CaseInsensitive) == 0)
            project.openProject(input);
        else
            project.importMedia(input);
    }

    // Look for a new release shortly after startup, at most once a day.
    // Screenshots only check against an explicit KADRON_UPDATE_URL.
    // Which GPU encoders actually work here; takes a few seconds, off the UI thread.
    if (screenshotPath.isEmpty())
        QTimer::singleShot(1500, &exporter, &ExportController::detectEncoders);
    if (screenshotPath.isEmpty() && !qEnvironmentVariableIsSet("KADRON_NO_UPDATE_CHECK"))
        QTimer::singleShot(4000, &appUpdater, &AppUpdater::checkDaily);
    else if (!screenshotPath.isEmpty() && qEnvironmentVariableIsSet("KADRON_UPDATE_URL"))
        appUpdater.check();
    if (!screenshotPath.isEmpty()) {
        const auto dimensions = qEnvironmentVariable("KADRON_SCREENSHOT_SIZE").split('x');
        if (dimensions.size() == 2) {
            mainWindow->setWidth(dimensions.at(0).toInt());
            mainWindow->setHeight(dimensions.at(1).toInt());
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_PUBLISH"))
            mainWindow->setProperty("inspectorMode", 1);
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_WORKSPACE"))
            mainWindow->setProperty("workspace", qEnvironmentVariableIntValue("KADRON_SCREENSHOT_WORKSPACE"));
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_SEQUENCE_PREVIEW")) {
            QTimer::singleShot(500, &app, [mainWindow] {
                QMetaObject::invokeMethod(mainWindow, "previewSequence");
            });
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_SEEK_MS")) {
            const auto position = qEnvironmentVariableIntValue("KADRON_SCREENSHOT_SEEK_MS");
            QTimer::singleShot(650, &app, [mainWindow, position] {
                if (auto *player = mainWindow->findChild<QObject *>("editorPlayer"))
                    player->setProperty("position", position);
            });
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_APPEARANCE")) {
            QTimer::singleShot(400, &app, [mainWindow] {
                if (auto *popup = mainWindow->findChild<QObject *>("appearancePopup"))
                    QMetaObject::invokeMethod(popup, "open");
            });
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_CLOSE")) {
            QTimer::singleShot(400, &app, [mainWindow] {
                if (auto *dialog = mainWindow->findChild<QObject *>("quitDialog"))
                    QMetaObject::invokeMethod(dialog, "open");
            });
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_TEXT")) {
            const auto text = qEnvironmentVariable("KADRON_SCREENSHOT_TEXT");
            QTimer::singleShot(300, &app, [mainWindow, text] {
                if (auto *tools = mainWindow->findChild<QObject *>("toolsArea"))
                    QMetaObject::invokeMethod(tools, "fillText", Q_ARG(QVariant, text));
            });
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_PDF_MODE")) {
            const auto mode = qEnvironmentVariable("KADRON_SCREENSHOT_PDF_MODE");
            QVariantList files;
            for (const auto &path : qEnvironmentVariable("KADRON_SCREENSHOT_PDF_FILES").split(';', Qt::SkipEmptyParts))
                files << QUrl::fromLocalFile(QFileInfo(path).absoluteFilePath());
            QTimer::singleShot(300, &app, [mainWindow, mode, files] {
                if (auto *tools = mainWindow->findChild<QObject *>("toolsArea")) {
                    QMetaObject::invokeMethod(tools, "setPdfMode", Q_ARG(QVariant, mode));
                    QMetaObject::invokeMethod(tools, "takePdfFiles", Q_ARG(QVariant, QVariant(files)));
                }
            });
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_GIF_SOURCE")) {
            const auto source = QUrl::fromLocalFile(QFileInfo(qEnvironmentVariable("KADRON_SCREENSHOT_GIF_SOURCE")).absoluteFilePath());
            QTimer::singleShot(300, &app, [mainWindow, source] {
                if (auto *tools = mainWindow->findChild<QObject *>("toolsArea"))
                    tools->setProperty("sourceUrl", source);
            });
        }
        const auto screenshotDelay = qEnvironmentVariableIntValue("KADRON_SCREENSHOT_DELAY_MS");
        QTimer::singleShot(screenshotDelay > 0 ? screenshotDelay : 1500, &app, [&app, mainWindow, screenshotPath] {
            mainWindow->grabWindow().save(screenshotPath);
            mainWindow->setProperty("forceClose", true);
            app.quit();
        });
    }
    return app.exec();
}
