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

    // Export sheet choices, kept for the next export.
    property string exportPreset: "source"
    property bool exportLoudnorm: false
}
