import QtQuick
import QtQuick.Controls

CheckBox {
    id: control
    implicitHeight: 36
    font.family: Theme.fontFamily
    font.pixelSize: 12
    indicator: Rectangle {
        width: 18
        height: 18
        radius: 5
        x: 0
        y: (control.height - height) / 2
        color: control.checked ? Theme.accent : Theme.field
        border.color: control.checked ? Theme.accent : Theme.textFaint
        Behavior on color { ColorAnimation { duration: Theme.fadeFast } }
        Text {
            anchors.centerIn: parent
            scale: control.checked ? 1 : 0.4
            Behavior on scale { SnapSpring {} }
            text: "\u2713"
            color: Theme.accentInk
            font.pixelSize: 14
            font.weight: Font.Bold
            opacity: control.checked ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fadeFast } }
        }
    }
    contentItem: Text {
        leftPadding: 27
        text: control.text
        color: control.enabled ? Theme.textSoft : Theme.textFaint
        font: control.font
        verticalAlignment: Text.AlignVCenter
    }
}
