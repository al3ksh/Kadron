import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Mute toggle and level for previews. Every preview shares one remembered
// level from Prefs, so the editor and the tools never start at full volume.
// Bind an AudioOutput's `volume` to `effectiveVolume`.
RowLayout {
    id: control
    property bool compact: false
    readonly property real effectiveVolume: Prefs.previewMuted ? 0 : Prefs.previewVolume
    readonly property bool silent: Prefs.previewMuted || Prefs.previewVolume <= 0.001
    spacing: 4

    ToolButton {
        id: muteButton
        implicitWidth: 28
        implicitHeight: 28
        focusPolicy: Qt.TabFocus
        Accessible.name: control.silent ? "Unmute preview" : "Mute preview"
        ToolTip.visible: hovered
        ToolTip.delay: 500
        ToolTip.text: control.silent ? "Unmute" : "Mute"
        onClicked: {
            if (Prefs.previewVolume <= 0.001) {
                Prefs.previewVolume = 0.7
                Prefs.previewMuted = false
            } else {
                Prefs.previewMuted = !Prefs.previewMuted
            }
        }
        contentItem: ToolIcon {
            name: control.silent ? "mute" : Prefs.previewVolume < 0.5 ? "volumeLow" : "volume"
            tint: muteButton.hovered ? Theme.text : Theme.textMuted
        }
        background: Rectangle {
            radius: Theme.radiusSmall
            color: muteButton.down ? Theme.pressed : muteButton.hovered ? Theme.hover : "transparent"
            border.width: muteButton.activeFocus ? 2 : 0
            border.color: Theme.accentFocus
        }
    }

    Slider {
        id: slider
        from: 0
        to: 1
        value: control.silent ? 0 : Prefs.previewVolume
        Layout.preferredWidth: control.compact ? 56 : 90
        Accessible.name: "Preview volume"
        onMoved: {
            Prefs.previewVolume = value
            Prefs.previewMuted = false
        }
        ToolTip.visible: pressed || hovered
        ToolTip.delay: pressed ? 0 : 500
        ToolTip.text: Math.round(value * 100) + "%"
        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: 3
            radius: 2
            color: Theme.lineStrong
            Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 2; color: Theme.accent }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: 14
            height: 14
            radius: 7
            color: Theme.accentSoft
            border.color: slider.activeFocus ? Theme.accentFocus : Theme.accentEdge
            border.width: slider.activeFocus ? 2 : 1
        }
    }
}
