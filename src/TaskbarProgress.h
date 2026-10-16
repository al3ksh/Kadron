#pragma once

#include <QtQml/qqmlregistration.h>

#include <QObject>
#include <QVariantList>

// Progress on the window's taskbar button, a flash when a job ends while
// Kadron is in the background, and the button's jump list. Windows only;
// no-op elsewhere.
class TaskbarProgress : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS
public:
    explicit TaskbarProgress(QObject *parent = nullptr);
    ~TaskbarProgress() override;

    // percent 0-100 shows a bar; -2 shows a moving bar for work of unknown
    // length; any other negative value clears it. error paints it red.
    Q_INVOKABLE void setProgress(QObject *window, int percent, bool error = false);
    // Flashes the taskbar button until the window is activated, unless it already is.
    Q_INVOKABLE void flash(QObject *window);
    // Right-clicking the taskbar button lists the recent files (Main.qml's
    // recentFiles, {url, project}) and starts one of the tools.
    Q_INVOKABLE void setJumpList(const QVariantList &recent);

private:
    void *m_taskbar = nullptr;
    bool m_triedCreate = false;
};
