pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Kadron.Backend

// App settings: appearance, editor and export defaults, general behaviour, the
// keyboard map and About.
// Every change applies immediately and is remembered through Prefs.
Dialog {
    id: dialog
    property int section: 0
    signal tutorialRequested()
    // The same step as the sidebar's update card: download, then restart.
    signal updateRequested()
    readonly property string repoUrl: "https://github.com/al3ksh/Kadron"
    readonly property string authorUrl: "https://aleksh.xyz"

    modal: true
    focus: true
    anchors.centerIn: parent
    width: Math.min(700, parent ? parent.width - 48 : 700)
    height: Math.min(540, parent ? parent.height - 48 : 540)
    padding: 0
    standardButtons: Dialog.NoButton
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function sameColor(a, b) { return Qt.colorEqual(a, b) }
    function show(page) { section = page === undefined ? section : page; open() }

    Overlay.modal: Rectangle {
        color: Theme.scrim
        Behavior on opacity { NumberAnimation { duration: Theme.reveal } }
    }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.reveal; easing.type: Easing.OutCubic }
            SnapSpring { property: "scale"; from: 0.94; to: 1 }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.fadeFast; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale"; to: 0.97; duration: Theme.fadeFast; easing.type: Easing.InCubic }
        }
    }
    background: Rectangle {
        color: Theme.card
        radius: Theme.radiusLarge
        border.color: Theme.lineStrong
    }

    FileDialog {
        id: watermarkPicker
        title: "Choose a logo"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"]
        onAccepted: { Prefs.watermarkPath = selectedFile.toString(); Prefs.watermarkEnabled = true }
    }

    ColorDialog {
        id: customAccent
        title: "Accent color"
        selectedColor: Prefs.accent
        onAccepted: Prefs.accent = selectedColor.toString()
    }

    component SectionLabel: Text {
        color: Theme.textFaint
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
        Layout.topMargin: 6
    }
    component Hint: Text {
        Layout.fillWidth: true
        color: Theme.textFaint
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
    component LinkRow: Rectangle {
        id: link
        property string title: ""
        property string detail: ""
        property string url: ""
        property string iconName: "link"
        Layout.fillWidth: true
        implicitHeight: 52
        radius: Theme.radius
        color: linkMouse.containsMouse ? Theme.hover : Theme.field
        border.color: Theme.line
        Accessible.role: Accessible.Link
        Accessible.name: title
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12
            ToolIcon { name: link.iconName; tint: Theme.accent }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: link.title; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text { Layout.fillWidth: true; text: link.detail; color: Theme.textMuted; font.pixelSize: 11; elide: Text.ElideRight }
            }
            ToolIcon { name: "external"; Layout.preferredWidth: 16; Layout.preferredHeight: 16; tint: linkMouse.containsMouse ? Theme.text : Theme.textFaint }
        }
        MouseArea {
            id: linkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(link.url)
        }
    }

    // One key as a small cap; "Ctrl+Shift+C" becomes three.
    component KeyCap: Rectangle {
        property alias label: capText.text
        implicitWidth: Math.max(22, capText.implicitWidth + 12)
        implicitHeight: 22
        radius: 5
        color: Theme.field
        border.color: Theme.lineStrong
        Text {
            id: capText
            anchors.centerIn: parent
            color: Theme.textSoft
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }
    // Everything the keyboard does, grouped as the app is laid out. Each row is
    // [what it does, [alternatives]], an alternative being keys joined by "+".
    readonly property var shortcutMap: [
        { group: "EVERYWHERE", rows: [
            ["Command palette", ["Ctrl+P"]],
            ["Settings", ["Ctrl+,"]],
            ["This keyboard map", ["Ctrl+/"]],
            ["Import media", ["Ctrl+O"]],
            ["Save project", ["Ctrl+S"]],
            ["Close project", ["Ctrl+W"]]
        ] },
        { group: "PLAYBACK", rows: [
            ["Play or pause", ["Space"]],
            ["Play · pause", ["L", "K"]],
            ["Back 5 seconds", ["J"]],
            ["Previous · next frame", [",", "."]],
            ["Back · forward 1 second", ["Shift+←", "Shift+→"]],
            ["Timeline focused: step 1 s, with Shift 0.1 s", ["←", "→"]],
            ["Timeline focused: start · end", ["Home", "End"]]
        ] },
        { group: "EDITING", rows: [
            ["Mark in · mark out", ["I", "O"]],
            ["Split at playhead", ["Ctrl+K"]],
            ["Undo", ["Ctrl+Z"]],
            ["Redo", ["Ctrl+Y", "Ctrl+Shift+Z"]],
            ["Remove the selected clip, text or sound", ["Delete"]],
            ["Cancel a trim in progress", ["Esc"]]
        ] },
        { group: "MARKERS & FRAMES", rows: [
            ["Add or remove a marker", ["N"]],
            ["Previous · next marker", ["[", "]"]],
            ["Save the frame as PNG", ["Ctrl+Shift+S"]],
            ["Copy the frame", ["Ctrl+Shift+C"]]
        ] },
        { group: "PREVIEW", rows: [
            ["Fullscreen preview (or double-click it)", ["F"]],
            ["Leave fullscreen", ["Esc"]],
            ["Mute", ["M"]],
            ["Volume up · down", ["↑", "↓"]],
            ["Zoom the timeline", ["Ctrl+Wheel"]]
        ] },
        { group: "TOOLS", rows: [
            ["Download: paste a link", ["Ctrl+V"]],
            ["PDF page preview: previous · next page", ["←", "→"]],
            ["PDF page preview: rotate right · left", ["R", "Shift+R"]],
            ["PDF page preview: remove the page", ["Delete"]]
        ] }
    ]

    contentItem: RowLayout {
        spacing: 0

        // Section rail.
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 188
            color: Theme.panel
            radius: Theme.radiusLarge
            Rectangle { anchors.right: parent.right; width: Theme.radiusLarge; height: parent.height; color: parent.color }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                anchors.topMargin: 20
                spacing: 2
                Text {
                    text: "Settings"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    Layout.leftMargin: 10
                    Layout.bottomMargin: 14
                }
                Repeater {
                    model: [["Appearance", "palette"], ["Editor & export", "edit"], ["General", "sliders"], ["Shortcuts", "keyboard"], ["About", "info"]]
                    delegate: NavItem {
                        required property var modelData
                        required property int index
                        objectName: "settingsSection" + index
                        Layout.fillWidth: true
                        implicitHeight: 38
                        title: modelData[0]
                        iconName: modelData[1]
                        active: dialog.section === index
                        onClicked: dialog.section = index
                        Rectangle {
                            anchors.fill: parent
                            z: -1
                            radius: 9
                            color: Theme.accentWash
                            visible: parent.active
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                Text {
                    text: "Kadron " + Core.appUpdater.currentVersion
                    color: Theme.textFaint
                    font.pixelSize: 10
                    Layout.leftMargin: 10
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 26
                Layout.rightMargin: 14
                Layout.topMargin: 14
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    text: ["Appearance", "Editor & export", "General", "Shortcuts", "About"][dialog.section]
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                ToolButton {
                    id: closeButton
                    objectName: "settingsClose"
                    implicitWidth: 32
                    implicitHeight: 32
                    Accessible.name: "Close settings"
                    onClicked: dialog.close()
                    contentItem: ToolIcon { name: "close"; tint: closeButton.hovered ? Theme.text : Theme.textMuted }
                    background: Rectangle { radius: Theme.radiusSmall; color: closeButton.hovered ? Theme.hover : Theme.hoverClear }
                }
            }

            ScrollView {
                id: scroller
                readonly property SoftBounds softBounds: SoftBounds { flickable: scroller.contentItem as Flickable }
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    x: 26
                    width: scroller.availableWidth - 52
                    spacing: 0

                    // Appearance
                    ColumnLayout {
                        visible: dialog.section === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Layout.bottomMargin: 26
                        spacing: 10
                        SectionLabel { text: "THEME" }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: [["dark", "Dark", "moon"], ["light", "Light", "sun"], ["system", "System", "edit"]]
                                delegate: EditorButton {
                                    required property var modelData
                                    objectName: "themeMode_" + modelData[0]
                                    Layout.fillWidth: true
                                    text: modelData[1]
                                    iconName: modelData[2]
                                    primary: Prefs.themeMode === modelData[0]
                                    subtle: Prefs.themeMode !== modelData[0]
                                    onClicked: Prefs.themeMode = modelData[0]
                                }
                            }
                        }
                        SectionLabel { text: "ACCENT" }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 10
                            Repeater {
                                model: Theme.accentPresets
                                delegate: Rectangle {
                                    id: swatch
                                    required property string modelData
                                    readonly property bool chosen: dialog.sameColor(Prefs.accent, modelData)
                                    width: 32
                                    height: 32
                                    radius: 16
                                    color: modelData
                                    border.width: chosen ? 3 : 1
                                    border.color: chosen ? Theme.text : Theme.lineStrong
                                    scale: swatchMouse.pressed ? 0.9 : swatchMouse.containsMouse ? 1.08 : 1
                                    Behavior on scale { SnapSpring {} }
                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: "Accent " + modelData
                                    MouseArea {
                                        id: swatchMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Prefs.accent = swatch.modelData
                                    }
                                }
                            }
                            Rectangle {
                                id: customSwatch
                                readonly property bool chosen: {
                                    for (var i = 0; i < Theme.accentPresets.length; i++)
                                        if (dialog.sameColor(Prefs.accent, Theme.accentPresets[i])) return false
                                    return true
                                }
                                width: 32
                                height: 32
                                radius: 16
                                color: chosen ? Prefs.accent : Theme.control
                                border.width: chosen ? 3 : 1
                                border.color: chosen ? Theme.text : Theme.lineStrong
                                ToolIcon { anchors.centerIn: parent; width: 16; height: 16; name: "palette"; tint: customSwatch.chosen ? Theme.accentInk : Theme.textMuted }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: customAccent.open()
                                }
                                ToolTip.visible: customHover.hovered
                                ToolTip.text: "Custom color"
                                HoverHandler { id: customHover }
                            }
                        }
                        Hint { text: "Previews and the timeline follow the accent. On light surfaces pale accents are deepened so text stays readable." }
                        EditorButton {
                            Layout.topMargin: 6
                            text: "Reset to Kadron defaults"
                            subtle: true
                            enabled: Prefs.themeMode !== "dark" || !dialog.sameColor(Prefs.accent, "#c9f27a")
                            onClicked: { Prefs.themeMode = "dark"; Prefs.accent = "#c9f27a" }
                        }
                    }

                    // Editor & export
                    ColumnLayout {
                        visible: dialog.section === 1
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Layout.bottomMargin: 26
                        spacing: 10
                        SectionLabel { text: "PREVIEW VOLUME" }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            ToolIcon { name: Prefs.previewMuted || Prefs.previewVolume === 0 ? "mute" : "volume" }
                            ToolSlider {
                                objectName: "settingsVolume"
                                Layout.fillWidth: true
                                from: 0
                                to: 1
                                value: Prefs.previewVolume
                                onMoved: { Prefs.previewVolume = value; Prefs.previewMuted = false }
                            }
                            Text {
                                text: Math.round(Prefs.previewVolume * 100) + "%"
                                color: Theme.textMuted
                                font.pixelSize: 12
                                font.features: { "tnum": 1 }
                                Layout.preferredWidth: 38
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                        Hint { text: "Every preview in Kadron starts at this level." }

                        SectionLabel { text: "DEFAULT EXPORT PRESET" }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 6
                            rowSpacing: 6
                            Repeater {
                                model: [["source", "Source quality"], ["1080p60", "1080p · 60 fps"], ["discord", "Discord · 10 MB"], ["vertical", "Vertical 9:16"]]
                                delegate: EditorButton {
                                    required property var modelData
                                    objectName: "settingsPreset_" + modelData[0]
                                    Layout.fillWidth: true
                                    text: modelData[1]
                                    primary: Prefs.exportPreset === modelData[0]
                                    subtle: Prefs.exportPreset !== modelData[0]
                                    onClicked: Prefs.exportPreset = modelData[0]
                                }
                            }
                        }
                        ToolCheck {
                            objectName: "settingsLoudnorm"
                            text: "Even out loudness on export (-16 LUFS)"
                            checked: Prefs.exportLoudnorm
                            onToggled: Prefs.exportLoudnorm = checked
                        }
                        Hint { text: "The export sheet opens with these choices; changing them there is remembered too." }

                        SectionLabel { text: "LOGO ON EXPORTS" }
                        ToolCheck {
                            objectName: "settingsWatermark"
                            text: "Stamp a logo on every editor export"
                            checked: Prefs.watermarkEnabled
                            enabled: Prefs.watermarkPath.length > 0
                            onToggled: Prefs.watermarkEnabled = checked
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            EditorButton {
                                objectName: "settingsWatermarkPick"
                                text: Prefs.watermarkPath.length ? "Change logo…" : "Choose logo…"
                                iconName: "image"
                                subtle: true
                                onClicked: watermarkPicker.open()
                            }
                            Text {
                                Layout.fillWidth: true
                                text: Prefs.watermarkPath.length ? decodeURIComponent(Prefs.watermarkPath.replace(/^.*[\/]/, "")) : "No logo chosen"
                                color: Theme.textMuted
                                font.pixelSize: 12
                                elide: Text.ElideMiddle
                            }
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            visible: Prefs.watermarkPath.length > 0
                            columns: 4
                            columnSpacing: 6
                            rowSpacing: 6
                            Repeater {
                                model: [["top-left", "Top left"], ["top-right", "Top right"], ["bottom-left", "Bottom left"], ["bottom-right", "Bottom right"]]
                                delegate: EditorButton {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData[1]
                                    primary: Prefs.watermarkCorner === modelData[0]
                                    subtle: Prefs.watermarkCorner !== modelData[0]
                                    onClicked: Prefs.watermarkCorner = modelData[0]
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: Prefs.watermarkPath.length > 0
                            spacing: 12
                            Text { text: "Size"; color: Theme.textMuted; font.pixelSize: 12; Layout.preferredWidth: 56 }
                            ToolSlider {
                                Layout.fillWidth: true
                                from: 0.05
                                to: 0.4
                                value: Prefs.watermarkSize
                                onMoved: Prefs.watermarkSize = value
                            }
                            Text { text: Math.round(Prefs.watermarkSize * 100) + "%"; color: Theme.textMuted; font.pixelSize: 12; font.features: { "tnum": 1 }; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: Prefs.watermarkPath.length > 0
                            spacing: 12
                            Text { text: "Opacity"; color: Theme.textMuted; font.pixelSize: 12; Layout.preferredWidth: 56 }
                            ToolSlider {
                                Layout.fillWidth: true
                                from: 0.1
                                to: 1
                                value: Prefs.watermarkOpacity
                                onMoved: Prefs.watermarkOpacity = value
                            }
                            Text { text: Math.round(Prefs.watermarkOpacity * 100) + "%"; color: Theme.textMuted; font.pixelSize: 12; font.features: { "tnum": 1 }; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight }
                        }
                        Hint { text: "Size is a share of the frame width. Lossless cuts skip the logo, since they don't re-encode." }
                    }

                    // General
                    ColumnLayout {
                        visible: dialog.section === 2
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Layout.bottomMargin: 26
                        spacing: 10
                        SectionLabel { text: "STARTUP" }
                        ToolCheck {
                            objectName: "startupIntroCheck"
                            text: "Play the intro when Kadron starts"
                            checked: Prefs.startupIntro
                            onToggled: Prefs.startupIntro = checked
                        }
                        EditorButton {
                            objectName: "showTutorialButton"
                            text: "Show the tutorial"
                            iconName: "info"
                            onClicked: {
                                dialog.close()
                                dialog.tutorialRequested()
                            }
                        }
                        SectionLabel { text: "UPDATES" }
                        ToolCheck {
                            objectName: "autoUpdateCheck"
                            text: "Check for Kadron and yt-dlp updates in the background"
                            checked: Prefs.autoUpdateCheck
                            onToggled: Prefs.autoUpdateCheck = checked
                        }
                        Hint { text: "Only asks GitHub for the newest release number. Nothing is downloaded until you choose to update." }
                        SectionLabel { text: "TOOLS" }
                        ToolCheck {
                            objectName: "rememberToolOptionsCheck"
                            text: "Remember tool options between runs"
                            checked: Prefs.rememberToolOptions
                            onToggled: Prefs.rememberToolOptions = checked
                        }
                        Hint { text: "Formats, quality, sizes and QR colors in Tools, Images and Reframe start as you left them." }
                        SectionLabel {
                            text: "WINDOWS"
                            visible: explorerCheck.available || trayCheck.available
                        }
                        ToolCheck {
                            id: explorerCheck
                            objectName: "explorerMenuCheck"
                            readonly property bool available: typeof Core.shellIntegration !== "undefined" && Core.shellIntegration.supported
                            visible: available
                            text: "Show Kadron in Explorer's right-click menu"
                            checked: available && Core.shellIntegration.enabled
                            onToggled: Core.shellIntegration.enabled = checked
                        }
                        ToolCheck {
                            id: trayCheck
                            objectName: "closeToTrayCheck"
                            readonly property bool available: typeof Core.trayIcon !== "undefined" && Core.trayIcon.supported
                            visible: available
                            text: "Keep Kadron running in the tray when the window is closed"
                            checked: Prefs.closeToTray
                            onToggled: Prefs.closeToTray = checked
                        }
                        Hint {
                            visible: trayCheck.available
                            text: "Exports and downloads carry on in the background. Quit from the tray icon's menu."
                        }
                        ToolCheck {
                            objectName: "notificationsCheck"
                            visible: trayCheck.available
                            text: "Show a Windows notification when a job finishes in the background"
                            checked: Prefs.notifications
                            onToggled: Prefs.notifications = checked
                        }
                    }

                    // Shortcuts
                    ColumnLayout {
                        visible: dialog.section === 3
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Layout.bottomMargin: 26
                        spacing: 4
                        Repeater {
                            model: dialog.shortcutMap
                            delegate: ColumnLayout {
                                id: keyGroup
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.topMargin: index > 0 ? 12 : 0
                                spacing: 2
                                SectionLabel { text: keyGroup.modelData.group; Layout.bottomMargin: 4 }
                                Repeater {
                                    model: keyGroup.modelData.rows
                                    delegate: RowLayout {
                                        id: keyRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.minimumHeight: 28
                                        spacing: 4
                                        Text {
                                            Layout.fillWidth: true
                                            text: keyRow.modelData[0]
                                            color: Theme.textSoft
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                        Repeater {
                                            model: keyRow.modelData[1]
                                            delegate: RowLayout {
                                                id: keyCombo
                                                required property string modelData
                                                required property int index
                                                spacing: 3
                                                Text { visible: keyCombo.index > 0; text: "/"; color: Theme.textFaint; font.pixelSize: 11; Layout.leftMargin: 3; Layout.rightMargin: 3 }
                                                Repeater {
                                                    model: keyCombo.modelData.split("+")
                                                    delegate: KeyCap { required property string modelData; label: modelData }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // About
                    ColumnLayout {
                        visible: dialog.section === 4
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Layout.bottomMargin: 26
                        spacing: 12
                        RowLayout {
                            spacing: 16
                            Rectangle {
                                implicitWidth: 64
                                implicitHeight: 64
                                radius: 16
                                color: Theme.field
                                border.color: Theme.line
                                BrandMark { anchors.centerIn: parent; width: 38; height: 38 }
                            }
                            ColumnLayout {
                                spacing: 3
                                Text { text: "Kadron"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 22; font.weight: Font.DemiBold }
                                Text { text: "Media studio · version " + Core.appUpdater.currentVersion; color: Theme.textMuted; font.pixelSize: 12 }
                            }
                        }
                        Hint {
                            color: Theme.textMuted
                            text: "A local editor and toolbox for video, audio, images and PDFs. Everything runs on your computer; nothing is uploaded unless you publish to your own Tools server."
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            EditorButton {
                                objectName: "aboutCheckUpdates"
                                text: Core.appUpdater.checking ? "Checking…" : "Check for updates"
                                iconName: "loop"
                                subtle: true
                                enabled: !Core.appUpdater.checking
                                onClicked: Core.appUpdater.check()
                            }
                            EditorButton {
                                id: aboutUpdateButton
                                objectName: "aboutUpdate"
                                visible: Core.appUpdater.updateAvailable
                                primary: true
                                enabled: !Core.appUpdater.downloading
                                iconName: Core.appUpdater.ready ? "rotateRight" : Core.appUpdater.canInstall ? "download" : "link"
                                text: Core.appUpdater.downloading ? "Downloading " + Math.round(Core.appUpdater.progress * 100) + "%"
                                      : Core.appUpdater.ready ? "Restart to update"
                                      : Core.appUpdater.canInstall ? "Update" : "Open release"
                                onClicked: dialog.updateRequested()
                                onVisibleChanged: if (visible) aboutFireworks.play()
                                // More every few seconds while the offer is on screen, as on the sidebar card.
                                Timer {
                                    interval: 2600
                                    repeat: true
                                    running: aboutUpdateButton.visible && !Core.appUpdater.downloading
                                    onTriggered: aboutFireworks.play()
                                }
                                Fireworks {
                                    id: aboutFireworks
                                    anchors.centerIn: parent
                                    width: parent.width + 90
                                    height: parent.height + 50
                                    bursts: 2
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: Core.appUpdater.statusText
                                color: Core.appUpdater.updateAvailable ? Theme.accent : Theme.textFaint
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                        LinkRow {
                            objectName: "aboutRepo"
                            Layout.topMargin: 4
                            title: "Source code"
                            detail: "github.com/al3ksh/Kadron · issues, releases and the changelog"
                            iconName: "file"
                            url: dialog.repoUrl
                        }
                        LinkRow {
                            objectName: "aboutAuthor"
                            title: "Made by al3ksh"
                            detail: "aleksh.xyz"
                            iconName: "link"
                            url: dialog.authorUrl
                        }
                        Hint { text: "Free software under the GNU GPL v3. Uses Qt, FFmpeg and yt-dlp." }
                    }
                }
            }
        }
    }
}
