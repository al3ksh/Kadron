import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    property bool subtle: false

    implicitHeight: 36
    implicitWidth: Math.max(82, label.implicitWidth + 30)
    padding: 0
    activeFocusOnTab: true

    contentItem: Text {
        id: label
        text: control.text
        font.family: "Segoe UI"
        font.pixelSize: 13
        font.weight: control.primary ? Font.DemiBold : Font.Medium
        color: !control.enabled ? "#707781" : control.primary ? "#101d18" : "#e5e9ed"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: 6
        color: !control.enabled ? "#242a2e"
             : control.primary ? (control.down ? "#7cc4a7" : control.hovered ? "#a9dfc9" : "#94d2b7")
             : control.subtle ? (control.hovered || control.down ? "#263034" : "transparent")
             : control.down ? "#303a40" : control.hovered ? "#354047" : "#283137"
        border.width: control.activeFocus ? 2 : control.primary || control.subtle ? 0 : 1
        border.color: control.activeFocus ? "#b7e7d1" : "#3d474c"
    }
}
