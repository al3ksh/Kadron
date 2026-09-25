#include "EditorProject.h"
#include "ExportController.h"
#include "ThumbnailStrip.h"
#include "ToolsClient.h"
#include "LocalMediaTools.h"
#include "LocalDownload.h"
#include "LocalPdfTools.h"
#include "LocalQr.h"
#include "WindowChrome.h"

#include <QGuiApplication>
#include <QStyleHints>
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

int main(int argc, char *argv[])
{
    if (qEnvironmentVariableIsSet("KADRON_LOG_FILE"))
        qInstallMessageHandler(fileMessageHandler);
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("Kadron"));
    app.setApplicationName(QStringLiteral("Kadron"));
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
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("editorProject", &project);
    engine.rootContext()->setContextProperty("exporter", &exporter);
    engine.rootContext()->setContextProperty("thumbnails", &thumbnails);
    engine.rootContext()->setContextProperty("toolsClient", &toolsClient);
    engine.rootContext()->setContextProperty("localTools", &localTools);
    engine.rootContext()->setContextProperty("localDownload", &localDownload);
    engine.rootContext()->setContextProperty("localPdf", &localPdf);
    engine.rootContext()->setContextProperty("localQr", &localQr);
    engine.addImageProvider(QStringLiteral("qr"), new QrImageProvider(&localQr));
    engine.loadFromModule("Kadron", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    applyWindowChrome(qobject_cast<QWindow *>(engine.rootObjects().first()));

    const auto arguments = app.arguments();
    if (arguments.size() > 1 && !arguments.at(1).startsWith("--")) {
        const auto input = QUrl::fromLocalFile(QFileInfo(arguments.at(1)).absoluteFilePath());
        if (QFileInfo(arguments.at(1)).suffix().compare("kadr", Qt::CaseInsensitive) == 0)
            project.openProject(input);
        else
            project.importMedia(input);
    }

    const auto screenshotPath = qEnvironmentVariable("KADRON_SCREENSHOT");
    if (!screenshotPath.isEmpty()) {
        const auto dimensions = qEnvironmentVariable("KADRON_SCREENSHOT_SIZE").split('x');
        if (dimensions.size() == 2) {
            if (auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
                window->setWidth(dimensions.at(0).toInt());
                window->setHeight(dimensions.at(1).toInt());
            }
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_PUBLISH"))
            engine.rootObjects().first()->setProperty("inspectorMode", 1);
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_WORKSPACE"))
            engine.rootObjects().first()->setProperty("workspace", qEnvironmentVariableIntValue("KADRON_SCREENSHOT_WORKSPACE"));
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_SEQUENCE_PREVIEW")) {
            QTimer::singleShot(500, &app, [&engine] {
                QMetaObject::invokeMethod(engine.rootObjects().first(), "previewSequence");
            });
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_SEEK_MS")) {
            const auto position = qEnvironmentVariableIntValue("KADRON_SCREENSHOT_SEEK_MS");
            QTimer::singleShot(650, &app, [&engine, position] {
                if (auto *player = engine.rootObjects().first()->findChild<QObject *>("editorPlayer"))
                    player->setProperty("position", position);
            });
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_CLOSE")) {
            QTimer::singleShot(400, &app, [&engine] {
                if (auto *dialog = engine.rootObjects().first()->findChild<QObject *>("quitDialog"))
                    QMetaObject::invokeMethod(dialog, "open");
            });
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_TEXT")) {
            const auto text = qEnvironmentVariable("KADRON_SCREENSHOT_TEXT");
            QTimer::singleShot(300, &app, [&engine, text] {
                if (auto *tools = engine.rootObjects().first()->findChild<QObject *>("toolsArea"))
                    QMetaObject::invokeMethod(tools, "fillText", Q_ARG(QVariant, text));
            });
        }
        if (qEnvironmentVariableIsSet("KADRON_SCREENSHOT_GIF_SOURCE")) {
            const auto source = QUrl::fromLocalFile(QFileInfo(qEnvironmentVariable("KADRON_SCREENSHOT_GIF_SOURCE")).absoluteFilePath());
            QTimer::singleShot(300, &app, [&engine, source] {
                if (auto *tools = engine.rootObjects().first()->findChild<QObject *>("toolsArea"))
                    tools->setProperty("sourceUrl", source);
            });
        }
        const auto screenshotDelay = qEnvironmentVariableIntValue("KADRON_SCREENSHOT_DELAY_MS");
        QTimer::singleShot(screenshotDelay > 0 ? screenshotDelay : 1500, &app, [&app, &engine, screenshotPath] {
            if (auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
                window->grabWindow().save(screenshotPath);
                window->setProperty("forceClose", true);
            }
            app.quit();
        });
    }
    return app.exec();
}
