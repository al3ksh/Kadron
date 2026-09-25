import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    property bool subtle: false
    property bool danger: false

    implicitHeight: 38
    implicitWidth: Math.max(78, label.implicitWidth + 30)
    padding: 0
    activeFocusOnTab: true

    contentItem: Text {
        id: label
        text: control.text
        font.family: "Segoe UI"
        font.pixelSize: 12
        font.weight: control.primary ? Font.DemiBold : Font.Medium
        color: !control.enabled ? "#727a82" : control.primary ? "#17200e" : control.danger ? "#f2a5a1" : "#ebefed"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 8
        color: !control.enabled ? "#252a2e"
             : control.primary ? (control.down ? "#a8d84f" : control.hovered ? "#daf99a" : "#c9f27a")
             : control.subtle ? (control.hovered || control.down ? "#2a3136" : "transparent")
             : control.down ? "#353d43" : control.hovered ? "#323a40" : "#292f35"
        border.width: control.activeFocus ? 2 : control.primary || control.subtle ? 0 : 1
        border.color: control.activeFocus ? "#e5ffb3" : "#3d454d"
        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }
}
