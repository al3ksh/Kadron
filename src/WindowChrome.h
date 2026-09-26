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
