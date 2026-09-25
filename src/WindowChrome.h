#pragma once

class QWindow;

// Paints the native window caption to match the app. The caption and text
// colors are read from the window's `captionColor` / `captionTextColor`
// properties so QML's Theme stays the single source of truth. No-op outside
// Windows; on Windows 10 only the dark-mode flag applies.
void applyWindowChrome(QWindow *window);
