import QtQuick
import QtQuick.Controls

TextField {
    id: field
    implicitHeight: 39
    color: Theme.text
    placeholderTextColor: Theme.textFaint
    selectionColor: Theme.accent
    selectedTextColor: Theme.accentInk
    font.family: Theme.fontFamily
    font.pixelSize: 12
    padding: 9
    background: Rectangle {
        radius: 8
        color: field.enabled ? Theme.field : Theme.disabled
        border.width: field.activeFocus ? 2 : 1
        border.color: field.activeFocus ? Theme.accent : Theme.lineStrong
        Behavior on border.color { ColorAnimation { duration: Theme.fade } }
    }
}
