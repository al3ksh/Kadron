import QtQuick
import QtQuick.Controls

TextField {
    id: field
    implicitHeight: 39
    color: "#f1f4ef"
    placeholderTextColor: "#89939c"
    selectionColor: "#bde86b"
    selectedTextColor: "#1a2513"
    font.family: "Segoe UI"
    font.pixelSize: 12
    padding: 9
    background: Rectangle {
        radius: 8
        color: field.enabled ? "#20262b" : "#252a2e"
        border.width: field.activeFocus ? 2 : 1
        border.color: field.activeFocus ? "#c9f27a" : "#404950"
        Behavior on border.color { ColorAnimation { duration: 140 } }
    }
}
