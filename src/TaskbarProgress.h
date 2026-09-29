#pragma once

#include <QObject>

// Progress on the window's taskbar button and a flash when a job ends while
// Kadron is in the background. Windows only; no-op elsewhere.
class TaskbarProgress : public QObject
{
    Q_OBJECT
public:
    explicit TaskbarProgress(QObject *parent = nullptr);
    ~TaskbarProgress() override;

    // percent 0-100 shows a bar; -2 shows a moving bar for work of unknown
    // length; any other negative value clears it. error paints it red.
    Q_INVOKABLE void setProgress(QObject *window, int percent, bool error = false);
    // Flashes the taskbar button until the window is activated, unless it already is.
    Q_INVOKABLE void flash(QObject *window);

private:
    void *m_taskbar = nullptr;
    bool m_triedCreate = false;
};
