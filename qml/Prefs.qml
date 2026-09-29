pragma Singleton
import QtCore

// User preferences that outlive the session: appearance and preview volume.
Settings {
    category: "preferences"

    // "dark", "light" or "system" (follows Windows' app mode).
    property string themeMode: "dark"
    property string accent: "#c9f27a"

    // One level for every preview, so nothing starts at full volume.
    property real previewVolume: 0.7
    property bool previewMuted: false

    // The animated intro while the app starts (read by main.cpp at launch).
    property bool startupIntro: true

    // Background checks for Kadron and yt-dlp releases (read by AppUpdater and LocalDownload).
    property bool autoUpdateCheck: true

    // Closing the window hides Kadron to the tray instead of quitting.
    property bool closeToTray: true
    property bool trayHintShown: false

    // A Windows notification when an export or download ends in the background.
    property bool notifications: true

    // Projects and media opened lately, newest first: a JSON list of {url, project}.
    property string recentFiles: "[]"

    // Finished downloads, newest first: a JSON list of {file, url, title, time}.
    property string downloadHistory: "[]"

    // Export sheet choices, kept for the next export.
    property string exportPreset: "source"
    property bool exportLoudnorm: false
}
