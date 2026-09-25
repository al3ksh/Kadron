#include "EditorProject.h"
#include "ExportController.h"
#include "ThumbnailStrip.h"
#include "ToolsClient.h"

#include <QGuiApplication>
#include <QFileInfo>
#include <QFont>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QQuickStyle>
#include <QTimer>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("Kadron"));
    app.setApplicationName(QStringLiteral("Kadron"));
    app.setFont(QFont(QStringLiteral("Segoe UI"), 10));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    EditorProject project;
    ExportController exporter;
    ThumbnailStrip thumbnails;
    ToolsClient toolsClient;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("editorProject", &project);
    engine.rootContext()->setContextProperty("exporter", &exporter);
    engine.rootContext()->setContextProperty("thumbnails", &thumbnails);
    engine.rootContext()->setContextProperty("toolsClient", &toolsClient);
    engine.loadFromModule("Kadron", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;

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
        QTimer::singleShot(1500, &app, [&app, &engine, screenshotPath] {
            if (auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
                window->grabWindow().save(screenshotPath);
                window->setProperty("forceClose", true);
            }
            app.quit();
        });
    }
    return app.exec();
}
