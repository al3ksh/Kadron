import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// Theme and accent picker. Changes apply immediately and are remembered.
Popup {
    id: popup
    width: 300
    padding: 16
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    enter: Transition { ParallelAnimation { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.reveal } SnapSpring { property: "scale"; from: 0.96; to: 1 } } }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.fadeFast } }
    background: Rectangle {
        color: Theme.panel
        radius: Theme.radiusLarge
        border.color: Theme.lineStrong
    }

    function sameColor(a, b) { return Qt.colorEqual(a, b) }

    ColorDialog {
        id: customAccent
        title: "Accent color"
        selectedColor: Prefs.accent
        onAccepted: Prefs.accent = selectedColor.toString()
    }

    contentItem: ColumnLayout {
        spacing: 12

        Text { text: "Appearance"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold }

        Text { text: "THEME"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
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

        Text { text: "ACCENT"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: Theme.accentPresets
                delegate: Rectangle {
                    id: swatch
                    required property string modelData
                    readonly property bool chosen: popup.sameColor(Prefs.accent, modelData)
                    width: 28
                    height: 28
                    radius: 14
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
                        if (popup.sameColor(Prefs.accent, Theme.accentPresets[i])) return false
                    return true
                }
                width: 28
                height: 28
                radius: 14
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
                ToolTip.visible: customMouseHover.hovered
                ToolTip.text: "Custom color"
                HoverHandler { id: customMouseHover }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Previews and the timeline follow the accent. On light surfaces pale accents are deepened so text stays readable."
            color: Theme.textFaint
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        ToolCheck {
            objectName: "startupIntroCheck"
            text: "Play the intro when Kadron starts"
            checked: Prefs.startupIntro
            onToggled: Prefs.startupIntro = checked
        }

        EditorButton {
            text: "Reset to Kadron defaults"
            subtle: true
            enabled: Prefs.themeMode !== "dark" || !popup.sameColor(Prefs.accent, "#c9f27a")
            onClicked: { Prefs.themeMode = "dark"; Prefs.accent = "#c9f27a" }
        }
    }
}
