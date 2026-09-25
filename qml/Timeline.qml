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

    // Seeking has its own lane; the playhead grip has a separate, larger hit area.
    Rectangle {
        id: seekLane
        x: 0
        y: 0
        width: parent.width
        height: 36
        radius: 7
        color: "#272e34"
        border.width: 1
        border.color: "#3b454b"

        Repeater {
            model: 11
            delegate: Rectangle {
                x: index / 10 * (seekLane.width - 1)
                y: 23
                width: 1
                height: index % 5 === 0 ? 9 : 5
                color: "#77858c"
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
    }

    Repeater {
        model: 6
        delegate: Text {
            x: index / 5 * (timeline.width - implicitWidth)
            y: 41
            text: timeline.timeLabel(timeline.durationMs * index / 5)
            color: "#aab5bc"
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
        radius: 7
        color: "#282f34"
        border.color: "#3b454b"
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
            color: "#5d768941"
            border.width: 1
            border.color: "#c9f27a"
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
                radius: 6
                visible: width >= 30 && (timeline.inMs > 0 || timeline.outMs < timeline.durationMs)
                color: "#303b30"
                border.color: "#a6cd68"
                Text {
                    anchors.centerIn: parent
                    text: "MOVE"
                    color: "#e6f8c8"
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
            radius: 4
            color: "#eaf2e2"
            visible: timeline.durationMs > 0
            Text { anchors.centerIn: parent; text: "I"; color: "#2d3c21"; font.pixelSize: 11; font.weight: Font.Bold }
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
            radius: 4
            color: "#eaf2e2"
            visible: timeline.durationMs > 0
            Text { anchors.centerIn: parent; text: "O"; color: "#2d3c21"; font.pixelSize: 11; font.weight: Font.Bold }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeHorCursor
                onPositionChanged: function(mouse) {
                    if (pressed) timeline.outRequested(timeline.atX(outHandle.mapToItem(timeline, mouse.x, 0).x))
                }
            }
        }
    }

    Rectangle {
        x: Math.round(timeline.fraction(timeline.playheadMs) * timeline.width) - width / 2
        y: 30
        width: 2
        height: trimLane.y + trimLane.height - y
        color: "#eebd86"
        opacity: 0.9
        visible: timeline.durationMs > 0
        z: 2
    }

    Item {
        id: playheadGrip
        x: Math.max(0, Math.min(timeline.width - width, timeline.fraction(timeline.playheadMs) * timeline.width - width / 2))
        y: 0
        width: 36
        height: 36
        visible: timeline.durationMs > 0
        activeFocusOnTab: true
        z: 3

        Keys.onPressed: function(event) {
            var step = event.modifiers & Qt.ShiftModifier ? 100 : 1000
            if (event.key === Qt.Key_Left) {
                timeline.seekRequested(Math.max(0, timeline.playheadMs - step))
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                timeline.seekRequested(Math.min(timeline.durationMs, timeline.playheadMs + step))
                event.accepted = true
            }
        }

        Rectangle {
            x: 13
            y: 21
            width: 10
            height: 10
            rotation: 45
            color: "#eebd86"
        }
        Rectangle {
            x: 6
            y: 2
            width: 24
            height: 24
            radius: 5
            color: gripMouse.pressed ? "#ffd4a1" : gripMouse.containsMouse ? "#f9c98f" : "#eebd86"
            border.width: playheadGrip.activeFocus ? 2 : 1
            border.color: playheadGrip.activeFocus ? "#fff3dd" : "#bc814f"
            Behavior on color { ColorAnimation { duration: 100 } }
            Row {
                anchors.centerIn: parent
                spacing: 3
                Repeater {
                    model: 2
                    Rectangle { width: 2; height: 10; radius: 1; color: "#65472d" }
                }
            }
        }
        MouseArea {
            id: gripMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor
            property real startX: 0
            property real startMs: 0
            onPressed: function(mouse) {
                playheadGrip.forceActiveFocus()
                startX = playheadGrip.mapToItem(timeline, mouse.x, 0).x
                startMs = timeline.playheadMs
            }
            onPositionChanged: function(mouse) {
                if (!pressed) return
                var currentX = playheadGrip.mapToItem(timeline, mouse.x, 0).x
                var nextMs = startMs + (currentX - startX) / timeline.width * timeline.durationMs
                timeline.seekRequested(Math.max(0, Math.min(timeline.durationMs, nextMs)))
            }
        }
    }

    Text {
        x: 0
        y: 126
        text: "IN  " + timeLabel(inMs)
        color: "#c8dbba"
        font.pixelSize: 11
        font.family: "Segoe UI"
    }
    Text {
        anchors.right: parent.right
        y: 126
        text: "OUT  " + timeLabel(outMs)
        color: "#c8dbba"
        font.pixelSize: 11
        font.family: "Segoe UI"
    }
}
