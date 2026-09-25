import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    property bool subtle: false
    property bool danger: false
    property string iconName: ""

    readonly property color inkColor: !control.enabled ? Theme.textDisabled : control.primary ? Theme.accentInk : control.danger ? Theme.danger : Theme.text

    implicitHeight: 38
    implicitWidth: Math.max(control.text ? 78 : 38, (control.iconName ? 23 : 0) + (control.text ? label.implicitWidth + 30 : 18))
    padding: 0
    activeFocusOnTab: true
    scale: control.down && control.enabled ? 0.96 : 1
    Behavior on scale { SnapSpring {} }

    contentItem: Item {
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 7
            ToolIcon {
                visible: control.iconName.length > 0
                name: control.iconName
                tint: control.inkColor
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: label
                visible: text.length > 0
                width: Math.min(implicitWidth, control.width - 24 - (control.iconName ? 23 : 0))
                text: control.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: control.primary ? Font.DemiBold : Font.Medium
                color: control.inkColor
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: Theme.fadeFast } }
            }
        }
    }

    background: Rectangle {
        radius: Theme.radius
        color: !control.enabled ? Theme.disabled
             : control.primary ? (control.down ? Theme.accentPressed : control.hovered ? Theme.accentHover : Theme.accent)
             : control.subtle ? (control.hovered || control.down ? Theme.hover : "transparent")
             : control.down ? Theme.pressed : control.hovered ? Theme.hover : Theme.control
        border.width: control.activeFocus ? 2 : control.primary || control.subtle ? 0 : 1
        border.color: control.activeFocus ? Theme.accentFocus : Theme.lineStrong
        Behavior on color { ColorAnimation { duration: Theme.fade; easing.type: Easing.OutCubic } }
    }
}
