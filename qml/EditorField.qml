import QtQuick
import QtQuick.Controls

TextField {
    id: field
    implicitHeight: 36
    color: "#e9ebea"
    placeholderTextColor: "#7f898a"
    selectionColor: "#6baeb3"
    selectedTextColor: "#142224"
    font.family: "Segoe UI"
    font.pixelSize: 12
    padding: 9
    background: Rectangle {
        radius: 4
        color: field.enabled ? "#202526" : "#242728"
        border.width: field.activeFocus ? 2 : 1
        border.color: field.activeFocus ? "#8bc9cb" : "#3a4244"
    }
}
