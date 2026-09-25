import QtQuick
import QtQuick.Controls

CheckBox {
    id: control
    implicitHeight: 36
    font.family: "Segoe UI"
    font.pixelSize: 12
    indicator: Rectangle {
        width: 18
        height: 18
        radius: 3
        x: 0
        y: (control.height - height) / 2
        color: control.checked ? "#a9cfd0" : "#222829"
        border.color: control.checked ? "#a9cfd0" : "#697477"
        Text {
            anchors.centerIn: parent
            text: "\u2713"
            color: "#142629"
            font.pixelSize: 14
            font.weight: Font.Bold
            visible: control.checked
        }
    }
    contentItem: Text {
        leftPadding: 27
        text: control.text
        color: control.enabled ? "#d5dddb" : "#788483"
        font: control.font
        verticalAlignment: Text.AlignVCenter
    }
}
