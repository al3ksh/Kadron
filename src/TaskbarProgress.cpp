#include "TaskbarProgress.h"

#include <QWindow>

#ifdef Q_OS_WIN
#include <windows.h>
#include <shobjidl.h>
#endif

TaskbarProgress::TaskbarProgress(QObject *parent) : QObject(parent) {}

TaskbarProgress::~TaskbarProgress()
{
#ifdef Q_OS_WIN
    if (m_taskbar)
        static_cast<ITaskbarList3 *>(m_taskbar)->Release();
#endif
}

void TaskbarProgress::setProgress(QObject *window, int percent, bool error)
{
#ifdef Q_OS_WIN
    const auto qwindow = qobject_cast<QWindow *>(window);
    if (!qwindow)
        return;
    if (!m_taskbar && !m_triedCreate) {
        m_triedCreate = true;
        ITaskbarList3 *taskbar = nullptr;
        if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER, IID_ITaskbarList3,
                                       reinterpret_cast<void **>(&taskbar)))
            && SUCCEEDED(taskbar->HrInit()))
            m_taskbar = taskbar;
        else if (taskbar)
            taskbar->Release();
    }
    if (!m_taskbar)
        return;
    const auto taskbar = static_cast<ITaskbarList3 *>(m_taskbar);
    const auto hwnd = reinterpret_cast<HWND>(qwindow->winId());
    if (percent < 0) {
        taskbar->SetProgressState(hwnd, TBPF_NOPROGRESS);
        return;
    }
    taskbar->SetProgressState(hwnd, error ? TBPF_ERROR : TBPF_NORMAL);
    taskbar->SetProgressValue(hwnd, qBound(0, percent, 100), 100);
#else
    Q_UNUSED(window) Q_UNUSED(percent) Q_UNUSED(error)
#endif
}

void TaskbarProgress::flash(QObject *window)
{
#ifdef Q_OS_WIN
    const auto qwindow = qobject_cast<QWindow *>(window);
    if (!qwindow || !qwindow->isVisible() || qwindow->isActive())
        return;
    FLASHWINFO info{sizeof(FLASHWINFO), reinterpret_cast<HWND>(qwindow->winId()), FLASHW_TRAY | FLASHW_TIMERNOFG, 0, 0};
    FlashWindowEx(&info);
#else
    Q_UNUSED(window)
#endif
}
