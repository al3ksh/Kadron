#include "WindowChrome.h"

#include <QColor>
#include <QMetaMethod>
#include <QMetaProperty>
#include <QVariant>
#include <QWindow>

#ifdef Q_OS_WIN
#include <windows.h>
#include <dwmapi.h>

namespace {
// Declared here because older SDK / MinGW headers lack them.
constexpr DWORD kUseImmersiveDarkMode = 20;
constexpr DWORD kBorderColor = 34;
constexpr DWORD kCaptionColor = 35;
constexpr DWORD kTextColor = 36;

COLORREF toColorRef(const QColor &color)
{
    return RGB(color.red(), color.green(), color.blue());
}
}
#endif

void applyWindowChrome(QWindow *window)
{
#ifdef Q_OS_WIN
    if (!window)
        return;
    const auto hwnd = reinterpret_cast<HWND>(window->winId());
    const auto darkProperty = window->property("captionDark");
    const BOOL dark = darkProperty.isValid() ? darkProperty.toBool() : TRUE;
    DwmSetWindowAttribute(hwnd, kUseImmersiveDarkMode, &dark, sizeof dark);
    const auto caption = window->property("captionColor").value<QColor>();
    if (caption.isValid()) {
        const auto value = toColorRef(caption);
        DwmSetWindowAttribute(hwnd, kCaptionColor, &value, sizeof value);
        DwmSetWindowAttribute(hwnd, kBorderColor, &value, sizeof value);
    }
    const auto text = window->property("captionTextColor").value<QColor>();
    if (text.isValid()) {
        const auto value = toColorRef(text);
        DwmSetWindowAttribute(hwnd, kTextColor, &value, sizeof value);
    }
#else
    Q_UNUSED(window);
#endif
}

WindowChromeWatcher::WindowChromeWatcher(QWindow *window)
    : QObject(window)
    , m_window(window)
{
    if (!window)
        return;
    const auto *meta = window->metaObject();
    const auto slot = metaObject()->method(metaObject()->indexOfSlot("apply()"));
    for (const char *name : {"captionColor", "captionTextColor", "captionDark"}) {
        const int index = meta->indexOfProperty(name);
        if (index >= 0 && meta->property(index).hasNotifySignal())
            connect(window, meta->property(index).notifySignal(), this, slot);
    }
    apply();
}

void WindowChromeWatcher::apply()
{
    applyWindowChrome(m_window);
}
