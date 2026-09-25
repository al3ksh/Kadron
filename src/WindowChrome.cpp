#include "WindowChrome.h"

#include <QColor>
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
    const BOOL dark = TRUE;
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
