import QtQuick
import QtQuick.Controls

// Slider in the app's style (the same track and handle as VolumeControl).
Slider {
    id: slider
    implicitHeight: 28
    background: Rectangle {
        x: slider.leftPadding
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        width: slider.availableWidth
        height: 3
        radius: 2
        color: Theme.lineStrong
        Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 2; color: slider.enabled ? Theme.accent : Theme.textDisabled }
    }
    handle: Rectangle {
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + slider.availableHeight / 2 - height / 2
        width: 14
        height: 14
        radius: 7
        color: slider.enabled ? Theme.accentSoft : Theme.disabled
        border.color: slider.activeFocus ? Theme.accentFocus : slider.enabled ? Theme.accentEdge : Theme.line
        border.width: slider.activeFocus ? 2 : 1
    }
}
