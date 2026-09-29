import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// App settings: appearance, editor and export defaults, general behaviour and About.
// Every change applies immediately and is remembered through Prefs.
Dialog {
    id: dialog
    property int section: 0
    readonly property string repoUrl: "https://github.com/al3ksh/Kadron"
    readonly property string authorUrl: "https://github.com/al3ksh"

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
            ToolIcon { name: "external"; width: 16; height: 16; tint: linkMouse.containsMouse ? Theme.text : Theme.textFaint }
        }
        MouseArea {
            id: linkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(link.url)
        }
    }

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
                    model: [["Appearance", "palette"], ["Editor & export", "edit"], ["General", "sliders"], ["About", "info"]]
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
                    text: "Kadron " + appUpdater.currentVersion
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
                    text: ["Appearance", "Editor & export", "General", "About"][dialog.section]
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
                        SectionLabel { text: "UPDATES" }
                        ToolCheck {
                            objectName: "autoUpdateCheck"
                            text: "Check for Kadron and yt-dlp updates in the background"
                            checked: Prefs.autoUpdateCheck
                            onToggled: Prefs.autoUpdateCheck = checked
                        }
                        Hint { text: "Only asks GitHub for the newest release number. Nothing is downloaded until you choose to update." }
                        SectionLabel {
                            text: "WINDOWS"
                            visible: explorerCheck.available || trayCheck.available
                        }
                        ToolCheck {
                            id: explorerCheck
                            objectName: "explorerMenuCheck"
                            readonly property bool available: typeof shellIntegration !== "undefined" && shellIntegration.supported
                            visible: available
                            text: "Show Kadron in Explorer's right-click menu"
                            checked: available && shellIntegration.enabled
                            onToggled: shellIntegration.enabled = checked
                        }
                        ToolCheck {
                            id: trayCheck
                            objectName: "closeToTrayCheck"
                            readonly property bool available: typeof trayIcon !== "undefined" && trayIcon.supported
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

                    // About
                    ColumnLayout {
                        visible: dialog.section === 3
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
                                Text { text: "Media studio · version " + appUpdater.currentVersion; color: Theme.textMuted; font.pixelSize: 12 }
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
                                text: appUpdater.checking ? "Checking…" : "Check for updates"
                                iconName: "loop"
                                subtle: true
                                enabled: !appUpdater.checking
                                onClicked: appUpdater.check()
                            }
                            Text {
                                Layout.fillWidth: true
                                text: appUpdater.statusText
                                color: appUpdater.updateAvailable ? Theme.accent : Theme.textFaint
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
                            detail: "github.com/al3ksh"
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
