#include "AppCore.h"

#include <QJSEngine>

AppCore *AppCore::instance()
{
    static AppCore core;
    return &core;
}

AppCore *AppCore::create(QQmlEngine *, QJSEngine *)
{
    auto *core = instance();
    QJSEngine::setObjectOwnership(core, QJSEngine::CppOwnership);
    return core;
}
