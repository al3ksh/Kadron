import QtQuick
import QtQuick.Controls

// Puts a finished file on the clipboard; the label reads "Copied" for a moment.
EditorButton {
    id: control
    property url file
    property bool compact: false
    property bool copied: false
    text: compact ? "" : copied ? "Copied" : "Copy"
    iconName: copied ? "check" : "copy"
    enabled: file.toString().length > 0
    ToolTip.visible: hovered
    ToolTip.delay: 500
    ToolTip.text: "Copy the file · paste it anywhere with Ctrl+V"
    onClicked: {
        if (!shellIntegration.copyFile(file)) return
        copied = true
        reset.restart()
    }
    onFileChanged: copied = false
    Timer { id: reset; interval: 1400; onTriggered: control.copied = false }
}
