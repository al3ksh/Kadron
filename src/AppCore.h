#pragma once

#include "AppUpdater.h"
#include "EditorProject.h"
#include "ExportController.h"
#include "LocalDownload.h"
#include "LocalImageTools.h"
#include "LocalMediaTools.h"
#include "LocalPdfTools.h"
#include "LocalQr.h"
#include "ShellIntegration.h"
#include "TaskbarProgress.h"
#include "ThumbnailStrip.h"
#include "ToolsClient.h"
#include "TrayIcon.h"

#include <QObject>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// The application's C++ services as one typed QML singleton, `Core`, so the
// interface reaches them as Core.editorProject and so on, and qmllint and the
// QML compiler know every property and method. main() (or a test) fills the
// pointers before the first QML file loads; the objects stay owned by C++.
class AppCore final : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Core)
    QML_SINGLETON
    Q_PROPERTY(EditorProject *editorProject MEMBER editorProject CONSTANT)
    Q_PROPERTY(ExportController *exporter MEMBER exporter CONSTANT)
    Q_PROPERTY(ThumbnailStrip *thumbnails MEMBER thumbnails CONSTANT)
    Q_PROPERTY(ToolsClient *toolsClient MEMBER toolsClient CONSTANT)
    Q_PROPERTY(LocalMediaTools *localTools MEMBER localTools CONSTANT)
    Q_PROPERTY(LocalMediaTools *localReframe MEMBER localReframe CONSTANT)
    Q_PROPERTY(LocalDownload *localDownload MEMBER localDownload CONSTANT)
    Q_PROPERTY(LocalPdfTools *localPdf MEMBER localPdf CONSTANT)
    Q_PROPERTY(LocalQr *localQr MEMBER localQr CONSTANT)
    Q_PROPERTY(LocalImageTools *localImages MEMBER localImages CONSTANT)
    Q_PROPERTY(AppUpdater *appUpdater MEMBER appUpdater CONSTANT)
    Q_PROPERTY(ShellIntegration *shellIntegration MEMBER shellIntegration CONSTANT)
    Q_PROPERTY(TrayIcon *trayIcon MEMBER trayIcon CONSTANT)
    Q_PROPERTY(TaskbarProgress *taskbar MEMBER taskbar CONSTANT)
    // The startup intro plays over the window at launch.
    Q_PROPERTY(bool startupIntroActive MEMBER startupIntroActive CONSTANT)
public:
    static AppCore *instance();
    static AppCore *create(QQmlEngine *, QJSEngine *);

    EditorProject *editorProject = nullptr;
    ExportController *exporter = nullptr;
    ThumbnailStrip *thumbnails = nullptr;
    ToolsClient *toolsClient = nullptr;
    LocalMediaTools *localTools = nullptr;
    LocalMediaTools *localReframe = nullptr;
    LocalDownload *localDownload = nullptr;
    LocalPdfTools *localPdf = nullptr;
    LocalQr *localQr = nullptr;
    LocalImageTools *localImages = nullptr;
    AppUpdater *appUpdater = nullptr;
    ShellIntegration *shellIntegration = nullptr;
    TrayIcon *trayIcon = nullptr;
    TaskbarProgress *taskbar = nullptr;
    bool startupIntroActive = false;

private:
    // Only instance() makes one, so the engine always gets the same object.
    AppCore() = default;
};
