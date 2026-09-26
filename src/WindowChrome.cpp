#include "WindowChrome.h"

#include <QColor>
#include <QMetaMethod>
#include <QMetaProperty>
#include <QVariant>
#include <QQuickWindow>
#include <QTimer>
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
constexpr DWORD kCloak = 13;
constexpr DWORD kWindowCornerPreference = 33;
constexpr DWORD kCornerRound = 2;

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

void roundWindowCorners(QWindow *window)
{
#ifdef Q_OS_WIN
    if (!window)
        return;
    const DWORD preference = kCornerRound;
    DwmSetWindowAttribute(reinterpret_cast<HWND>(window->winId()), kWindowCornerPreference, &preference, sizeof preference);
#else
    Q_UNUSED(window);
#endif
}

void setWindowCloaked(QWindow *window, bool cloaked)
{
#ifdef Q_OS_WIN
    if (!window)
        return;
    const BOOL value = cloaked ? TRUE : FALSE;
    DwmSetWindowAttribute(reinterpret_cast<HWND>(window->winId()), kCloak, &value, sizeof value);
#else
    Q_UNUSED(window);
    Q_UNUSED(cloaked);
#endif
}

IntroHandoff::IntroHandoff(QWindow *intro, QWindow *mainWindow)
    : QObject(mainWindow)
    , m_intro(intro)
    , m_main(mainWindow)
{
}

void IntroHandoff::prepare()
{
    if (!m_main)
        return;
    if (auto *quick = qobject_cast<QQuickWindow *>(m_main.data())) {
        connect(quick, &QQuickWindow::frameSwapped, this, [this] {
            m_drawn = true;
            if (m_finishing)
                uncover();
        }, Qt::QueuedConnection);
    }
    m_main->create();
    setWindowCloaked(m_main, true);
    m_main->show();
    // Keys still go to the intro (to skip it), not to the hidden app.
    if (m_intro)
        m_intro->requestActivate();
}

void IntroHandoff::finish()
{
    m_finishing = true;
    if (m_drawn)
        uncover();
    else
        // Never leave the app invisible if no frame arrives.
        QTimer::singleShot(1500, this, &IntroHandoff::uncover);
}

void IntroHandoff::uncover()
{
    if (m_uncovered)
        return;
    m_uncovered = true;
    setWindowCloaked(m_main, false);
    m_main->requestActivate();
    QTimer::singleShot(80, this, [this] {
        if (m_intro) {
            m_intro->close();
            m_intro->deleteLater();
        }
    });
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
