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
        radius: 5
        x: 0
        y: (control.height - height) / 2
        color: control.checked ? "#c9f27a" : "#20262b"
        border.color: control.checked ? "#c9f27a" : "#77818a"
        Text {
            anchors.centerIn: parent
            text: "\u2713"
            color: "#19220f"
            font.pixelSize: 14
            font.weight: Font.Bold
            visible: control.checked
        }
    }
    contentItem: Text {
        leftPadding: 27
        text: control.text
        color: control.enabled ? "#e3e8e5" : "#8b949b"
        font: control.font
        verticalAlignment: Text.AlignVCenter
    }
}
