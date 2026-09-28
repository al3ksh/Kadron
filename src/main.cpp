#include "EditorProject.h"
#include "ExportController.h"
#include "ThumbnailStrip.h"
#include "ToolsClient.h"
#include "LocalMediaTools.h"
#include "LocalDownload.h"
#include "LocalPdfTools.h"
#include "LocalQr.h"
#include "LocalImageTools.h"
#include "WindowChrome.h"
#include "AppUpdater.h"
#include "ShellIntegration.h"
#include "SingleInstance.h"

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
#include <QStandardPaths>
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

    // The installer adds and removes the Explorer menu through these.
    if (app.arguments().contains(QStringLiteral("--register-shell")))
        return ShellIntegration::install(QCoreApplication::applicationFilePath()) ? 0 : 1;
    if (app.arguments().contains(QStringLiteral("--unregister-shell"))) {
        ShellIntegration::uninstall();
        return 0;
    }
    // Files for a Kadron that is already open go to it; screenshot runs stay apart.
    const auto launch = SingleInstance::parse(app.arguments());
    SingleInstance instance;
    if (!qEnvironmentVariableIsSet("KADRON_SCREENSHOT") && !instance.claim()
        && !launch.files.isEmpty() && SingleInstance::forward(launch))
        return 0;

    EditorProject project;
    // Screenshot runs never leave or pick up a crash-recovery copy.
    if (!qEnvironmentVariableIsSet("KADRON_SCREENSHOT"))
        project.setRecoveryPath(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/recovery.kadr");
    QObject::connect(&app, &QCoreApplication::aboutToQuit, &project, &EditorProject::discardRecovery);
    ExportController exporter;
    ThumbnailStrip thumbnails;
    ToolsClient toolsClient;
    LocalMediaTools localTools;
    LocalMediaTools localReframe;
    LocalDownload localDownload;
    LocalPdfTools localPdf;
    LocalQr localQr;
    LocalImageTools localImages;
    AppUpdater appUpdater;
    ShellIntegration shellIntegration;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("editorProject", &project);
    engine.rootContext()->setContextProperty("exporter", &exporter);
    engine.rootContext()->setContextProperty("thumbnails", &thumbnails);
    engine.rootContext()->setContextProperty("toolsClient", &toolsClient);
    engine.rootContext()->setContextProperty("localTools", &localTools);
    engine.rootContext()->setContextProperty("localReframe", &localReframe);
    engine.rootContext()->setContextProperty("localDownload", &localDownload);
    engine.rootContext()->setContextProperty("localPdf", &localPdf);
    engine.rootContext()->setContextProperty("localQr", &localQr);
    engine.rootContext()->setContextProperty("localImages", &localImages);
    engine.rootContext()->setContextProperty("appUpdater", &appUpdater);
    engine.rootContext()->setContextProperty("shellIntegration", &shellIntegration);
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

    if (!launch.files.isEmpty())
        instance.take(launch, false);
    instance.attach(mainWindow);

    // Look for a new release shortly after startup and every 4 hours after.
    // Screenshots only check against an explicit KADRON_UPDATE_URL.
    // Which GPU encoders actually work here; takes a few seconds, off the UI thread.
    if (screenshotPath.isEmpty())
        QTimer::singleShot(1500, &exporter, &ExportController::detectEncoders);
    if (screenshotPath.isEmpty() && !qEnvironmentVariableIsSet("KADRON_NO_UPDATE_CHECK"))
        QTimer::singleShot(4000, &appUpdater, [&appUpdater] { appUpdater.startAutomaticChecks(4 * 60 * 60 * 1000); });
    else if (!screenshotPath.isEmpty() && qEnvironmentVariableIsSet("KADRON_UPDATE_URL"))
        appUpdater.check();
    // The newest yt-dlp, so the Download page can say whether it is current.
    if (screenshotPath.isEmpty() && !qEnvironmentVariableIsSet("KADRON_NO_UPDATE_CHECK"))
        QTimer::singleShot(6000, &localDownload, [&localDownload] { localDownload.startAutomaticChecks(6 * 60 * 60 * 1000); });
    else if (!screenshotPath.isEmpty() && qEnvironmentVariableIsSet("KADRON_YTDLP_RELEASE_URL"))
        localDownload.checkYtDlpRelease();
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
        // KADRON_SCREENSHOT_DIALOG=<objectName> opens that dialog or popup.
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_DIALOG")) {
            const auto name = qEnvironmentVariable("KADRON_SCREENSHOT_DIALOG");
            QTimer::singleShot(700, &app, [mainWindow, name] {
                if (auto *dialog = mainWindow->findChild<QObject *>(name))
                    QMetaObject::invokeMethod(dialog, "open");
            });
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_CLOSE_PROJECT")) {
            QTimer::singleShot(qEnvironmentVariableIntValue("KADRON_SCREENSHOT_CLOSE_PROJECT"), &app, [mainWindow] {
                QMetaObject::invokeMethod(mainWindow, "applyClose");
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
            // Opens the large page view once the pages are rendered.
            if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_PDF_PREVIEW")) {
                const auto index = qEnvironmentVariableIntValue("KADRON_SCREENSHOT_PDF_PREVIEW");
                QTimer::singleShot(2500, &app, [mainWindow, index] {
                    if (auto *tools = mainWindow->findChild<QObject *>("toolsArea"))
                        QMetaObject::invokeMethod(tools, "openPagePreview", Q_ARG(QVariant, index));
                });
            }
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_IMAGE_FILES")) {
            QVariantList files;
            for (const auto &path : qEnvironmentVariable("KADRON_SCREENSHOT_IMAGE_FILES").split(';', Qt::SkipEmptyParts))
                files << QUrl::fromLocalFile(QFileInfo(path).absoluteFilePath());
            QTimer::singleShot(300, &app, [mainWindow, files] {
                if (auto *images = mainWindow->findChild<QObject *>("imagesArea")) {
                    QMetaObject::invokeMethod(images, "addFiles", Q_ARG(QVariant, QVariant(files)));
                    if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_IMAGE_VIEW"))
                        images->setProperty("view", qEnvironmentVariable("KADRON_SCREENSHOT_IMAGE_VIEW"));
                }
            });
            // Edits once the images have been read: select, rotate, then pick a crop shape.
            QTimer::singleShot(1500, &app, [mainWindow] {
                auto *images = mainWindow->findChild<QObject *>("imagesArea");
                if (!images)
                    return;
                if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_IMAGE_SELECT"))
                    images->setProperty("selected", qEnvironmentVariableIntValue("KADRON_SCREENSHOT_IMAGE_SELECT"));
                if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_IMAGE_ROTATE"))
                    QMetaObject::invokeMethod(images, "rotateBy", Q_ARG(QVariant, qEnvironmentVariableIntValue("KADRON_SCREENSHOT_IMAGE_ROTATE")));
                if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_IMAGE_RESIZE"))
                    images->setProperty("resizeMode", qEnvironmentVariable("KADRON_SCREENSHOT_IMAGE_RESIZE"));
                if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_IMAGE_ASPECT"))
                    QMetaObject::invokeMethod(images, "setAspect", Q_ARG(QVariant, qEnvironmentVariable("KADRON_SCREENSHOT_IMAGE_ASPECT")));
            });
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_REFRAME_SOURCE")) {
            const auto source = QUrl::fromLocalFile(QFileInfo(qEnvironmentVariable("KADRON_SCREENSHOT_REFRAME_SOURCE")).absoluteFilePath());
            QTimer::singleShot(300, &app, [mainWindow, source] {
                if (auto *reframe = mainWindow->findChild<QObject *>("reframeArea")) {
                    QMetaObject::invokeMethod(reframe, "load", Q_ARG(QVariant, QVariant(source)));
                    if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_REFRAME_MODE"))
                        reframe->setProperty("mode", qEnvironmentVariable("KADRON_SCREENSHOT_REFRAME_MODE"));
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
