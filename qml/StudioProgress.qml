import QtQuick

Rectangle {
    id: track
    property real value: 0
    implicitHeight: 5
    radius: 3
    color: Theme.line

    Rectangle {
        height: parent.height
        width: parent.width * Math.max(0, Math.min(1, track.value))
        radius: 3
        color: Theme.accent
        Behavior on width { NumberAnimation { duration: Theme.reveal; easing.type: Easing.OutCubic } }
    }
}
