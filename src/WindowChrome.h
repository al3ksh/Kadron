#pragma once

#include <QObject>
#include <QPointer>

class QWindow;

// Paints the native window caption to match the app. The caption and text
// colors are read from the window's `captionColor` / `captionTextColor`
// properties and the dark-mode flag from `captionDark`, so QML's Theme stays
// the single source of truth. No-op outside Windows; on Windows 10 only the
// dark-mode flag applies.
void applyWindowChrome(QWindow *window);

// For frameless splash windows: Windows 11 rounded corners.
void roundWindowCorners(QWindow *window);

// Hides a shown window from the screen while it keeps rendering (DWM
// cloaking), so it can draw its first frame before anyone sees it.
void setWindowCloaked(QWindow *window, bool cloaked);

// Swaps the startup intro for the main window. The main window is shown
// cloaked (rendering, but not on screen) as soon as it has loaded, so by the
// time the intro ends it has drawn its first frame; it is then uncloaked over
// the intro, with no white window or open animation, and the intro closes.
class IntroHandoff : public QObject
{
    Q_OBJECT
public:
    IntroHandoff(QWindow *intro, QWindow *mainWindow);
    void prepare();

public slots:
    void finish();

private:
    void uncover();

    QPointer<QWindow> m_intro;
    QPointer<QWindow> m_main;
    bool m_drawn = false;
    bool m_finishing = false;
    bool m_uncovered = false;
};

// Repaints the caption whenever those properties change (theme switches).
class WindowChromeWatcher : public QObject
{
    Q_OBJECT
public:
    explicit WindowChromeWatcher(QWindow *window);

public slots:
    void apply();

private:
    QPointer<QWindow> m_window;
};
