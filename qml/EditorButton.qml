import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    property bool subtle: false
    property bool danger: false

    implicitHeight: 34
    implicitWidth: Math.max(72, label.implicitWidth + 28)
    padding: 0
    activeFocusOnTab: true

    contentItem: Text {
        id: label
        text: control.text
        font.family: "Segoe UI"
        font.pixelSize: 12
        font.weight: control.primary ? Font.DemiBold : Font.Medium
        color: !control.enabled ? "#71787a" : control.primary ? "#142629" : control.danger ? "#e6a9a3" : "#e5e8e7"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 4
        color: !control.enabled ? "#282b2c"
             : control.primary ? (control.down ? "#88b5b8" : control.hovered ? "#c0dddd" : "#a9cfd0")
             : control.subtle ? (control.hovered || control.down ? "#303537" : "transparent")
             : control.down ? "#303b3d" : control.hovered ? "#383f41" : "#2c3234"
        border.width: control.activeFocus ? 2 : control.primary || control.subtle ? 0 : 1
        border.color: control.activeFocus ? "#c4e7e8" : "#444c4e"
    }
}
