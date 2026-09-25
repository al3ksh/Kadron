import QtQuick

Rectangle {
    id: track
    property real value: 0
    implicitHeight: 5
    radius: 3
    color: "#353e43"

    Rectangle {
        height: parent.height
        width: parent.width * Math.max(0, Math.min(1, track.value))
        radius: 3
        color: "#c9f27a"
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
}
