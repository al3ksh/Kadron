import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Filmstrip or waveform with a selectable range: drag the handles to set start
// and end, drag inside the range to move it, click elsewhere to seek.
Item {
    id: strip
    property var frames: []
    // When set, the lane shows this waveform image instead of frames; the
    // selected part is drawn in the accent color.
    property string waveform: ""
    readonly property bool waveMode: waveform.length > 0 || waveLoading
    property bool waveLoading: false
    property real durationMs: 0
    property real startMs: 0
    property real endMs: 0
    property real positionMs: 0
    property real minimumMs: 100
    signal rangeRequested(real startMs, real endMs)
    signal seekRequested(real milliseconds)

    // Space under the lane for the playhead pin.
    readonly property real pinSpace: 24
    // While the pin is dragged it shows the pointer, not the (lagging) player.
    property real dragMs: 0
    readonly property bool scrubbing: pinMouse.pressed || lineMouse.pressed
    readonly property real shownMs: scrubbing ? dragMs : positionMs
    signal scrubFinished()

    implicitHeight: 72 + pinSpace

    function xAt(ms) { return durationMs > 0 ? Math.max(0, Math.min(1, ms / durationMs)) * width : 0 }
    function msAt(x) { return width > 0 ? Math.max(0, Math.min(durationMs, x / width * durationMs)) : 0 }
    function label(ms) {
        if (durationMs < 60000) return (ms / 1000).toFixed(2) + " s"
        var seconds = ms / 1000
        return Math.floor(seconds / 60) + ":" + (seconds % 60).toFixed(1).padStart(4, "0")
    }

    Rectangle {
        id: lane
        y: 18
        width: parent.width
        height: parent.height - 18 - strip.pinSpace
        radius: Theme.radiusSmall
        color: Theme.card
        clip: true
        Row {
            anchors.fill: parent
            visible: !strip.waveMode
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
        SkeletonBlock { anchors.fill: parent; radius: 0; visible: strip.waveLoading && strip.waveform.length === 0 }
        Image {
            id: waveImage
            anchors.fill: parent
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            visible: strip.waveform.length > 0
            source: strip.waveform
            fillMode: Image.Stretch
            smooth: true
            opacity: 0.4
        }
        Item {
            visible: strip.waveform.length > 0
            x: strip.xAt(strip.startMs)
            width: strip.xAt(strip.endMs) - x
            height: parent.height
            clip: true
            Image {
                x: -parent.x
                y: waveImage.y
                width: waveImage.width
                height: waveImage.height
                source: strip.waveform
                fillMode: Image.Stretch
                smooth: true
                layer.enabled: true
                layer.effect: MultiEffect { colorization: 1; colorizationColor: Theme.accent }
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
            height: lane.y + lane.height
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

    // Playhead: a line through the lane with a pin under it. Both the pin and
    // the line can be grabbed; the range handles keep priority on their edges.
    Item {
        id: playhead
        visible: strip.durationMs > 0
        x: Math.round(strip.xAt(strip.shownMs))
        y: lane.y - 2
        height: strip.height - y
        z: 1.5

        function scrubTo(item, mouseX) {
            strip.dragMs = strip.msAt(item.mapToItem(strip, mouseX, 0).x)
            strip.seekRequested(strip.dragMs)
        }

        Rectangle { x: -1; width: 2; height: lane.height + 4; color: Theme.playhead }
        MouseArea {
            id: lineMouse
            x: -5
            width: 10
            height: lane.height + 4
            z: -1
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.SizeHorCursor
            onPressed: function(mouse) { playhead.scrubTo(this, mouse.x) }
            onPositionChanged: function(mouse) { if (pressed) playhead.scrubTo(this, mouse.x) }
            onReleased: strip.scrubFinished()
        }

        Item {
            id: pin
            readonly property real pinWidth: pinLabel.implicitWidth + 16
            // Kept inside the strip at the edges; the tip still points at the playhead.
            x: Math.max(-playhead.x, Math.min(strip.width - playhead.x - pinWidth, -pinWidth / 2))
            y: lane.height + 2
            width: pinWidth
            height: strip.pinSpace
            readonly property real tip: -x
            scale: pinMouse.pressed ? 1.06 : 1
            transformOrigin: Item.Top
            Behavior on scale { SnapSpring {} }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: pinMouse.pressed ? Theme.playheadPressed : pinMouse.containsMouse || lineMouse.containsMouse ? Theme.playheadHover : Theme.playheadWash
                    strokeColor: Theme.playhead
                    strokeWidth: 1
                    joinStyle: ShapePath.RoundJoin
                    PathSvg {
                        readonly property real w: pin.width - 0.5
                        readonly property real h: pin.height - 0.5
                        readonly property real t: Math.max(1, Math.min(pin.width - 1, pin.tip))
                        path: "M" + Math.max(0.5, t - 5) + " 6 L" + t + " 0.5 L" + Math.min(w, t + 5) + " 6 H" + (w - 4)
                              + " Q" + w + " 6 " + w + " 10 V" + (h - 4) + " Q" + w + " " + h + " " + (w - 4) + " " + h
                              + " H4.5 Q0.5 " + h + " 0.5 " + (h - 4) + " V10 Q0.5 6 4.5 6 Z"
                    }
                }
            }
            Text {
                id: pinLabel
                y: 6
                width: parent.width
                height: parent.height - 6
                text: strip.label(strip.shownMs)
                color: Theme.playheadInk
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            MouseArea {
                id: pinMouse
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real grabOffset: 0
                onPressed: function(mouse) {
                    // Grabbing the pin off-center must not make it jump.
                    grabOffset = mapToItem(strip, mouse.x, 0).x - strip.xAt(strip.positionMs)
                    strip.dragMs = strip.positionMs
                }
                onPositionChanged: function(mouse) {
                    if (!pressed) return
                    strip.dragMs = strip.msAt(mapToItem(strip, mouse.x, 0).x - grabOffset)
                    strip.seekRequested(strip.dragMs)
                }
                onReleased: strip.scrubFinished()
            }
        }
    }
}
