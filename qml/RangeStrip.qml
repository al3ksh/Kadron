import QtQuick

// Filmstrip with a selectable range: drag the handles to set start and end,
// drag inside the range to move it, click elsewhere to seek.
Item {
    id: strip
    property var frames: []
    property real durationMs: 0
    property real startMs: 0
    property real endMs: 0
    property real positionMs: 0
    property real minimumMs: 100
    signal rangeRequested(real startMs, real endMs)
    signal seekRequested(real milliseconds)

    implicitHeight: 72

    function xAt(ms) { return durationMs > 0 ? Math.max(0, Math.min(1, ms / durationMs)) * width : 0 }
    function msAt(x) { return width > 0 ? Math.max(0, Math.min(durationMs, x / width * durationMs)) : 0 }
    function label(ms) { return (ms / 1000).toFixed(2) + " s" }

    Rectangle {
        id: lane
        y: 18
        width: parent.width
        height: parent.height - 18
        radius: Theme.radiusSmall
        color: Theme.card
        clip: true
        Row {
            anchors.fill: parent
            Repeater {
                model: strip.frames.length
                delegate: Image {
                    required property int index
                    width: lane.width / strip.frames.length
                    height: lane.height
                    source: strip.frames[index]
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: 0.85
                }
            }
        }
        // Dim what falls outside the range.
        Rectangle { width: strip.xAt(strip.startMs); height: parent.height; color: Theme.scrim }
        Rectangle { x: strip.xAt(strip.endMs); width: parent.width - x; height: parent.height; color: Theme.scrim }
        MouseArea {
            anchors.fill: parent
            enabled: strip.durationMs > 0
            cursorShape: Qt.PointingHandCursor
            onPressed: function(mouse) { strip.seekRequested(strip.msAt(mouse.x)) }
            onPositionChanged: function(mouse) { if (pressed) strip.seekRequested(strip.msAt(mouse.x)) }
        }
    }

    // Selected range: move by dragging its body.
    Rectangle {
        id: range
        visible: strip.durationMs > 0
        x: strip.xAt(strip.startMs)
        y: lane.y
        width: Math.max(2, strip.xAt(strip.endMs) - x)
        height: lane.height
        color: "transparent"
        border.width: 2
        border.color: Theme.accent
        radius: 4
        MouseArea {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            preventStealing: true
            property real pressX: 0
            property real pressStart: 0
            property real moved: 0
            onPressed: function(mouse) {
                pressX = mapToItem(strip, mouse.x, 0).x
                pressStart = strip.startMs
                moved = 0
            }
            onPositionChanged: function(mouse) {
                if (!pressed) return
                var dx = mapToItem(strip, mouse.x, 0).x - pressX
                moved = Math.max(moved, Math.abs(dx))
                var length = strip.endMs - strip.startMs
                var start = Math.max(0, Math.min(strip.durationMs - length, pressStart + dx / Math.max(1, strip.width) * strip.durationMs))
                strip.rangeRequested(start, start + length)
            }
            onReleased: function(mouse) {
                if (moved < 3) strip.seekRequested(strip.msAt(mapToItem(strip, mouse.x, 0).x))
            }
        }
    }

    Repeater {
        model: 2
        delegate: Item {
            id: handle
            required property int index
            readonly property bool leading: index === 0
            visible: strip.durationMs > 0
            x: strip.xAt(leading ? strip.startMs : strip.endMs) - width / 2
            y: 0
            width: 20
            height: strip.height
            z: 2
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: lane.y
                width: 8
                height: lane.height
                radius: 3
                color: handleMouse.pressed ? Theme.accentFocus : Theme.accent
                scale: handleMouse.pressed || handleMouse.containsMouse ? 1.15 : 1
                Behavior on scale { SnapSpring {} }
                Rectangle { anchors.centerIn: parent; width: 2; height: 14; radius: 1; color: Theme.accentInk }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                text: strip.label(handle.leading ? strip.startMs : strip.endMs)
                color: Theme.accentSoft
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: handleMouse
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.SizeHorCursor
                onPositionChanged: function(mouse) {
                    if (!pressed) return
                    var ms = strip.msAt(mapToItem(strip, mouse.x, 0).x)
                    if (handle.leading) strip.rangeRequested(Math.min(ms, strip.endMs - strip.minimumMs), strip.endMs)
                    else strip.rangeRequested(strip.startMs, Math.max(ms, strip.startMs + strip.minimumMs))
                }
            }
        }
    }

    // Preview position.
    Rectangle {
        visible: strip.durationMs > 0
        x: Math.round(strip.xAt(strip.positionMs)) - 1
        y: lane.y - 2
        width: 2
        height: lane.height + 4
        color: Theme.playhead
        z: 1
    }
}
