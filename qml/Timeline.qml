import QtQuick
import QtQuick.Controls

Item {
    id: timeline
    property real durationMs: 0
    property real inMs: 0
    property real outMs: 0
    property real playheadMs: 0
    property var frames: []
    signal seekRequested(real milliseconds)
    signal inRequested(real milliseconds)
    signal outRequested(real milliseconds)
    signal moveRequested(real deltaMilliseconds)

    implicitHeight: 146

    function fraction(milliseconds) {
        return durationMs > 0 ? Math.max(0, Math.min(1, milliseconds / durationMs)) : 0
    }
    function atX(position) {
        return durationMs > 0 ? Math.max(0, Math.min(durationMs, position / width * durationMs)) : 0
    }
    function timeLabel(milliseconds) {
        var total = Math.max(0, Math.floor(milliseconds / 1000))
        return Math.floor(total / 60) + ":" + (total % 60).toString().padStart(2, "0")
    }

    // Seeking has its own lane, so the playhead never sits below a trim handle.
    Rectangle {
        id: seekLane
        x: 0
        y: 0
        width: parent.width
        height: 36
        radius: 4
        color: "#292e30"
        border.width: 1
        border.color: "#434c4e"

        Repeater {
            model: 11
            delegate: Rectangle {
                x: index / 10 * (seekLane.width - 1)
                y: 23
                width: 1
                height: index % 5 === 0 ? 9 : 5
                color: "#899596"
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: timeline.durationMs > 0
            cursorShape: Qt.PointingHandCursor
            onPressed: function(mouse) { timeline.seekRequested(timeline.atX(mouse.x)) }
            onPositionChanged: function(mouse) {
                if (pressed) timeline.seekRequested(timeline.atX(mouse.x))
            }
        }
        Rectangle {
            x: Math.max(0, Math.min(seekLane.width - width, timeline.fraction(timeline.playheadMs) * seekLane.width - width / 2))
            y: 2
            width: 13
            height: 18
            radius: 3
            color: "#e8b57e"
            border.color: "#ad7548"
            Text {
                anchors.centerIn: parent
                text: "|"
                font.pixelSize: 12
                color: "#493625"
            }
        }
    }

    Repeater {
        model: 6
        delegate: Text {
            x: index / 5 * (timeline.width - implicitWidth)
            y: 41
            text: timeline.timeLabel(timeline.durationMs * index / 5)
            color: "#a6b0b0"
            font.family: "Segoe UI"
            font.pixelSize: 11
        }
    }

    Rectangle {
        id: trimLane
        x: 0
        y: 65
        width: parent.width
        height: 56
        radius: 4
        color: "#292d2e"
        border.color: "#454d4e"
        border.width: 1
        Repeater {
            model: timeline.frames.length
            delegate: Image {
                x: index * trimLane.width / timeline.frames.length
                width: trimLane.width / timeline.frames.length + 1
                height: trimLane.height
                source: timeline.frames[index]
                fillMode: Image.PreserveAspectCrop
                opacity: 0.76
                asynchronous: true
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: timeline.durationMs > 0
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) { timeline.seekRequested(timeline.atX(mouse.x)) }
        }

        Rectangle {
            id: selection
            x: timeline.fraction(timeline.inMs) * trimLane.width
            width: Math.max(0, timeline.fraction(timeline.outMs - timeline.inMs) * trimLane.width)
            height: parent.height
            radius: 3
            color: "#663a7a80"
            border.width: 1
            border.color: "#9bcdd0"
            opacity: timeline.durationMs > 0 ? 1 : 0

            MouseArea {
                anchors.fill: parent
                enabled: timeline.durationMs > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) { timeline.seekRequested(timeline.inMs + mouse.x / Math.max(1, selection.width) * (timeline.outMs - timeline.inMs)) }
            }
            Rectangle {
                id: moveGrip
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(64, Math.max(0, selection.width - 34))
                height: 20
                radius: 4
                visible: width >= 30 && (timeline.inMs > 0 || timeline.outMs < timeline.durationMs)
                color: "#25474b"
                border.color: "#82b8bb"
                Text {
                    anchors.centerIn: parent
                    text: "MOVE"
                    color: "#e4f1f1"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    property real pressX: 0
                    property real appliedMs: 0
                    onPressed: function(mouse) {
                        pressX = moveGrip.mapToItem(timeline, mouse.x, 0).x
                        appliedMs = 0
                    }
                    onPositionChanged: function(mouse) {
                        if (!pressed) return
                        var now = moveGrip.mapToItem(timeline, mouse.x, 0).x
                        var totalMs = (now - pressX) / timeline.width * timeline.durationMs
                        timeline.moveRequested(totalMs - appliedMs)
                        appliedMs = totalMs
                    }
                }
            }
        }

        Rectangle {
            id: inHandle
            x: Math.max(0, Math.min(trimLane.width - width, timeline.fraction(timeline.inMs) * trimLane.width - width / 2))
            width: 16
            height: parent.height
            radius: 3
            color: "#e4ebea"
            visible: timeline.durationMs > 0
            Text { anchors.centerIn: parent; text: "I"; color: "#2f5559"; font.pixelSize: 11; font.weight: Font.Bold }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeHorCursor
                onPositionChanged: function(mouse) {
                    if (pressed) timeline.inRequested(timeline.atX(inHandle.mapToItem(timeline, mouse.x, 0).x))
                }
            }
        }
        Rectangle {
            id: outHandle
            x: Math.max(0, Math.min(trimLane.width - width, timeline.fraction(timeline.outMs) * trimLane.width - width / 2))
            width: 16
            height: parent.height
            radius: 3
            color: "#e4ebea"
            visible: timeline.durationMs > 0
            Text { anchors.centerIn: parent; text: "O"; color: "#2f5559"; font.pixelSize: 11; font.weight: Font.Bold }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeHorCursor
                onPositionChanged: function(mouse) {
                    if (pressed) timeline.outRequested(timeline.atX(outHandle.mapToItem(timeline, mouse.x, 0).x))
                }
            }
        }
    }

    Text {
        x: 0
        y: 126
        text: "IN  " + timeLabel(inMs)
        color: "#b8d8d9"
        font.pixelSize: 11
        font.family: "Segoe UI"
    }
    Text {
        anchors.right: parent.right
        y: 126
        text: "OUT  " + timeLabel(outMs)
        color: "#b8d8d9"
        font.pixelSize: 11
        font.family: "Segoe UI"
    }
}
