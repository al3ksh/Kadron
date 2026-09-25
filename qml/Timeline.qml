import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

// Whole-sequence timeline. Every clip is a block sized by its trimmed length,
// showing its filmstrip and waveform. Edges trim, bodies drag to reorder, the
// ruler scrubs. All positions here are in sequence time (ms from the start of
// the first clip); Main maps them back to clip/source positions.
FocusScope {
    id: timeline
    property var clips: []
    property int activeIndex: -1
    property real playheadMs: 0
    property bool playing: false
    property var thumbnailSource: null
    property real zoom: 1

    signal scrubRequested(real sequenceMs)
    signal scrubFinished()
    signal selectRequested(int index)
    signal trimRequested(int index, real inMs, real outMs, real previewMs)
    signal trimPreviewRequested(int index, real sourceMs)
    signal trimFinished()
    signal moveRequested(int from, int to)
    signal splitRequested()
    signal duplicateRequested(int index)
    signal removeRequested(int index)

    readonly property real totalMs: {
        var total = 0
        for (var i = 0; i < clips.length; i++) total += Math.max(0, clips[i].lengthMs)
        return total
    }
    readonly property var starts: {
        var result = [], acc = 0
        for (var i = 0; i < clips.length; i++) {
            result.push(acc)
            acc += Math.max(0, clips[i].lengthMs)
        }
        return result
    }

    // Reordering: the dragged block follows the pointer; the others make room.
    property int dragIndex: -1
    property int dropIndex: -1
    property real dragOffset: 0
    readonly property var layoutStarts: {
        if (dragIndex < 0) return starts
        var order = []
        for (var i = 0; i < clips.length; i++) if (i !== dragIndex) order.push(i)
        order.splice(dropIndex, 0, dragIndex)
        var result = [], acc = 0
        for (var k = 0; k < order.length; k++) {
            result[order[k]] = acc
            acc += Math.max(0, clips[order[k]].lengthMs)
        }
        return result
    }

    readonly property real fitPxPerMs: totalMs > 0 ? flick.width * zoom / totalMs : 0
    readonly property real pxPerMs: fitPxPerMs

    // Trimming is previewed: the sequence stays put while an edge is dragged and
    // the change is committed on release (Escape cancels).
    property int trimIndex: -1
    property bool trimLeading: false
    property real trimInMs: 0
    property real trimOutMs: 0
    function cancelTrim() { trimIndex = -1 }

    // The drawn playhead eases toward the requested position unless playback
    // is driving it, so scrubbing reads as one continuous motion.
    property real shownMs: playheadMs
    Behavior on shownMs { enabled: !timeline.playing; SmoothSpring { epsilon: 0.5; spring: 9; damping: 0.7 } }
    onShownMsChanged: {
        if (!playing || zoom <= 1) return
        var x = shownMs * pxPerMs
        if (x > flick.contentX + flick.width - 48 || x < flick.contentX)
            flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, x - 48))
    }

    implicitHeight: 150
    activeFocusOnTab: true

    function msAt(contentX) {
        return pxPerMs > 0 ? Math.max(0, Math.min(totalMs, contentX / pxPerMs)) : 0
    }
    function timeLabel(milliseconds, fine) {
        var total = Math.max(0, Math.floor(milliseconds / 1000))
        var label = Math.floor(total / 60) + ":" + (total % 60).toString().padStart(2, "0")
        return fine ? label + "." + Math.floor(milliseconds % 1000 / 100) : label
    }
    readonly property real tickMs: {
        var steps = [100, 250, 500, 1000, 2000, 5000, 10000, 15000, 30000, 60000, 120000, 300000, 600000, 1800000]
        for (var i = 0; i < steps.length; i++)
            if (steps[i] * pxPerMs >= 76) return steps[i]
        return steps[steps.length - 1]
    }
    function dropIndexFor(from, offset) {
        var len = Math.max(0, clips[from].lengthMs)
        var center = starts[from] + offset / Math.max(pxPerMs, 0.0001) + len / 2
        var acc = 0, slot = 0
        for (var i = 0; i < clips.length; i++) {
            if (i === from) continue
            var other = Math.max(0, clips[i].lengthMs)
            if (center < acc + other / 2) return slot
            acc += other
            slot++
        }
        return slot
    }
    function zoomAround(factor, viewX) {
        if (totalMs <= 0) return
        var anchorMs = (flick.contentX + viewX) / pxPerMs
        zoom = Math.max(1, Math.min(60, zoom * factor))
        flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, anchorMs * fitPxPerMs - viewX))
    }

    Keys.onPressed: function(event) {
        var step = event.modifiers & Qt.ShiftModifier ? 100 : 1000
        if (event.key === Qt.Key_Left) timeline.scrubRequested(Math.max(0, playheadMs - step))
        else if (event.key === Qt.Key_Right) timeline.scrubRequested(Math.min(totalMs, playheadMs + step))
        else if (event.key === Qt.Key_Home) timeline.scrubRequested(0)
        else if (event.key === Qt.Key_End) timeline.scrubRequested(totalMs)
        else if (event.key === Qt.Key_Escape && trimIndex >= 0) { cancelTrim(); event.accepted = true; return }
        else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && clips.length > 1) timeline.removeRequested(activeIndex)
        else return
        if (event.key !== Qt.Key_Delete && event.key !== Qt.Key_Backspace) timeline.scrubFinished()
        event.accepted = true
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
            var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
            if (event.modifiers & Qt.ControlModifier) timeline.zoomAround(delta > 0 ? 1.25 : 0.8, point.position.x)
            else flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - delta))
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.bottomMargin: 10
        interactive: false
        clip: true
        contentWidth: Math.max(width, timeline.totalMs * timeline.pxPerMs)
        contentHeight: height
        ScrollBar.horizontal: ScrollBar {
            parent: timeline
            x: 0
            y: timeline.height - height
            width: timeline.width
            height: 8
            policy: timeline.zoom > 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            contentItem: Rectangle { implicitHeight: 5; radius: 3; color: Theme.scrollThumb }
        }

        Item {
            id: content
            width: flick.contentWidth
            height: flick.height

            HoverHandler { id: hover }

            // Ruler and scrub lane.
            Rectangle {
                id: ruler
                width: parent.width
                height: 30
                radius: Theme.radiusSmall
                color: Theme.card
                border.color: Theme.line

                Repeater {
                    model: timeline.tickMs > 0 && timeline.pxPerMs > 0 ? Math.ceil(flick.width / (timeline.tickMs * timeline.pxPerMs)) + 2 : 0
                    delegate: Item {
                        required property int index
                        readonly property int tick: Math.floor(flick.contentX / (timeline.tickMs * timeline.pxPerMs)) + index
                        readonly property real ms: tick * timeline.tickMs
                        visible: ms <= timeline.totalMs + 1
                        x: ms * timeline.pxPerMs
                        height: ruler.height
                        Rectangle { y: 21; width: 1; height: 9; color: Theme.textFaint }
                        Rectangle { x: timeline.tickMs * timeline.pxPerMs / 2; y: 25; width: 1; height: 5; color: Theme.lineStrong }
                        Text {
                            x: 5
                            y: 5
                            text: timeline.timeLabel(parent.ms, timeline.tickMs < 1000)
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: timeline.totalMs > 0
                    cursorShape: Qt.IBeamCursor
                    preventStealing: true
                    onPressed: function(mouse) { timeline.forceActiveFocus(); timeline.scrubRequested(timeline.msAt(mouse.x)) }
                    onPositionChanged: function(mouse) { if (pressed) timeline.scrubRequested(timeline.msAt(mouse.x)) }
                    onReleased: timeline.scrubFinished()
                }
            }

            // Clip blocks.
            Item {
                id: track
                y: ruler.height + 6
                width: parent.width
                height: parent.height - y

                Repeater {
                    model: timeline.clips.length
                    delegate: Item {
                        id: block
                        required property int index
                        readonly property var clip: timeline.clips[index] || ({ url: "", name: "", durationMs: 0, inMs: 0, outMs: 0, lengthMs: 0 })
                        readonly property bool active: timeline.activeIndex === index
                        readonly property bool dragged: timeline.dragIndex === index
                        readonly property bool audioOnly: /\.(mp3|wav|flac|m4a|ogg|opus|aac)$/i.test(clip.url.toString())
                        readonly property var frames: timeline.thumbnailSource && timeline.thumbnailSource.revision >= 0 ? timeline.thumbnailSource.framesFor(clip.url, clip.durationMs) : []
                        readonly property string waveform: timeline.thumbnailSource && timeline.thumbnailSource.revision >= 0 ? timeline.thumbnailSource.waveformFor(clip.url) : ""

                        x: dragged ? timeline.starts[index] * timeline.pxPerMs + timeline.dragOffset
                                   : (timeline.layoutStarts[index] || 0) * timeline.pxPerMs
                        y: dragged ? -3 : 0
                        z: dragged ? 5 : active ? 2 : 1
                        width: Math.max(3, Math.max(0, clip.lengthMs) * timeline.pxPerMs)
                        height: track.height
                        Behavior on x { enabled: timeline.dragIndex >= 0 && !block.dragged; SmoothSpring {} }
                        Behavior on y { SnapSpring { epsilon: 0.1 } }

                        Rectangle {
                            id: body
                            anchors.fill: parent
                            anchors.rightMargin: 1
                            radius: Theme.radiusSmall
                            color: Theme.card
                            clip: true

                            // Filmstrip: tiles are chosen for the visible part only.
                            Item {
                                id: film
                                visible: !block.audioOnly
                                width: parent.width
                                height: block.audioOnly ? 0 : parent.height - wave.height
                                readonly property real tileWidth: Math.max(24, height * 16 / 9)
                                readonly property int firstTile: Math.max(0, Math.floor((flick.contentX - block.x) / tileWidth))
                                Repeater {
                                    model: block.frames.length > 0 && block.width > 0 ? Math.max(0, Math.min(Math.ceil(block.width / film.tileWidth) - film.firstTile, Math.ceil(flick.width / film.tileWidth) + 1)) : 0
                                    delegate: Image {
                                        required property int index
                                        readonly property int tile: film.firstTile + index
                                        readonly property real sourceMs: block.clip.inMs + (tile + 0.5) * film.tileWidth / Math.max(timeline.pxPerMs, 0.0001)
                                        x: tile * film.tileWidth
                                        width: film.tileWidth + 1
                                        height: film.height
                                        source: block.frames[Math.max(0, Math.min(block.frames.length - 1, Math.floor(sourceMs / Math.max(1, block.clip.durationMs) * block.frames.length)))]
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        opacity: block.active ? 0.95 : 0.7
                                    }
                                }
                            }
                            Rectangle {
                                id: wave
                                y: film.height
                                width: parent.width
                                height: block.audioOnly ? parent.height : 26
                                color: block.active ? Theme.waveActive : Theme.field
                                Image {
                                    x: -block.clip.inMs * timeline.pxPerMs
                                    width: block.clip.durationMs * timeline.pxPerMs
                                    height: parent.height - 4
                                    y: 2
                                    source: block.waveform
                                    fillMode: Image.Stretch
                                    smooth: true
                                    opacity: block.active ? 0.7 : 0.4
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radiusSmall
                                color: "transparent"
                                border.width: block.active ? 2 : 1
                                border.color: block.active ? Theme.accent : bodyMouse.containsMouse ? Theme.textFaint : Theme.lineStrong
                                Behavior on border.color { ColorAnimation { duration: Theme.fade } }
                            }
                            Rectangle {
                                x: 6
                                y: 6
                                visible: block.width > 46
                                width: Math.min(chip.implicitWidth + 12, block.width - 12)
                                height: 20
                                radius: 5
                                color: Theme.chipScrim
                                Text {
                                    id: chip
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 6
                                    width: parent.width - 12
                                    text: (block.index + 1).toString().padStart(2, "0") + "  " + block.clip.name + "  " + timeline.timeLabel(block.clip.lengthMs, true)
                                    color: block.active ? Theme.accentSoft : Theme.textSoft
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: bodyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            preventStealing: true
                            cursorShape: timeline.dragIndex === block.index ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            property real pressX: 0
                            onPressed: function(mouse) {
                                timeline.forceActiveFocus()
                                pressX = mapToItem(timeline, mouse.x, 0).x
                                if (!block.active) timeline.selectRequested(block.index)
                                if (mouse.button === Qt.RightButton) clipMenu.popup()
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed || !(pressedButtons & Qt.LeftButton) || timeline.clips.length < 2) return
                                var offset = mapToItem(timeline, mouse.x, 0).x - pressX
                                if (timeline.dragIndex < 0 && Math.abs(offset) < 6) return
                                timeline.dragIndex = block.index
                                timeline.dragOffset = offset
                                timeline.dropIndex = timeline.dropIndexFor(block.index, offset)
                            }
                            onReleased: function(mouse) {
                                if (mouse.button !== Qt.LeftButton) return
                                if (timeline.dragIndex === block.index) {
                                    var from = timeline.dragIndex, to = timeline.dropIndex
                                    timeline.dragIndex = -1
                                    timeline.dropIndex = -1
                                    timeline.dragOffset = 0
                                    if (from !== to) timeline.moveRequested(from, to)
                                } else {
                                    timeline.scrubRequested(timeline.starts[block.index] + mouse.x / Math.max(timeline.pxPerMs, 0.0001))
                                    timeline.scrubFinished()
                                }
                            }
                            onCanceled: {
                                timeline.dragIndex = -1
                                timeline.dropIndex = -1
                                timeline.dragOffset = 0
                            }
                        }

                        Item {
                            id: trimPreview
                            readonly property bool shown: timeline.trimIndex === block.index
                            readonly property real inX: (timeline.trimInMs - block.clip.inMs) * timeline.pxPerMs
                            readonly property real outX: (timeline.trimOutMs - block.clip.inMs) * timeline.pxPerMs
                            readonly property real edgeX: timeline.trimLeading ? inX : outX
                            readonly property real deltaMs: timeline.trimLeading ? block.clip.inMs - timeline.trimInMs : timeline.trimOutMs - block.clip.outMs
                            visible: shown
                            anchors.fill: parent
                            z: 4
                            // Removed part.
                            Rectangle {
                                x: timeline.trimLeading ? 0 : Math.min(trimPreview.outX, block.width)
                                width: Math.max(0, timeline.trimLeading ? Math.min(trimPreview.inX, block.width) : block.width - trimPreview.outX)
                                height: parent.height
                                radius: Theme.radiusSmall
                                color: Theme.scrim
                            }
                            // Added part, drawn over the neighbouring clip.
                            Rectangle {
                                x: timeline.trimLeading ? Math.min(0, trimPreview.inX) : block.width
                                width: Math.max(0, timeline.trimLeading ? -trimPreview.inX : trimPreview.outX - block.width)
                                height: parent.height
                                radius: Theme.radiusSmall
                                color: Theme.selectionFill
                                border.width: 1
                                border.color: Theme.accent
                            }
                            Rectangle {
                                x: trimPreview.edgeX - 1
                                width: 2
                                height: parent.height
                                color: Theme.accent
                            }
                            Rectangle {
                                x: Math.max(-block.x, trimPreview.edgeX - width / 2)
                                y: parent.height - height - 6
                                width: trimLabel.implicitWidth + 14
                                height: 20
                                radius: 5
                                color: Theme.accent
                                Text {
                                    id: trimLabel
                                    anchors.centerIn: parent
                                    text: (timeline.trimLeading ? "In " : "Out ") + timeline.timeLabel(timeline.trimLeading ? timeline.trimInMs : timeline.trimOutMs, true)
                                          + "  " + (trimPreview.deltaMs >= 0 ? "+" : "\u2212") + (Math.abs(trimPreview.deltaMs) / 1000).toFixed(2) + " s"
                                    color: Theme.accentInk
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Repeater {
                            model: 2
                            delegate: MouseArea {
                                id: edge
                                required property int index
                                readonly property bool leading: index === 0
                                x: leading ? 0 : block.width - width
                                width: Math.min(12, block.width / 3)
                                height: block.height
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: Qt.SizeHorCursor
                                property real pressX: 0
                                onPressed: function(mouse) {
                                    timeline.forceActiveFocus()
                                    if (!block.active) timeline.selectRequested(block.index)
                                    pressX = mapToItem(timeline, mouse.x, 0).x
                                    timeline.trimLeading = leading
                                    timeline.trimInMs = block.clip.inMs
                                    timeline.trimOutMs = block.clip.outMs
                                    timeline.trimIndex = block.index
                                }
                                onPositionChanged: function(mouse) {
                                    if (!pressed || timeline.trimIndex !== block.index) return
                                    var delta = (mapToItem(timeline, mouse.x, 0).x - pressX) / Math.max(timeline.pxPerMs, 0.0001)
                                    var minimum = Math.min(100, block.clip.durationMs)
                                    if (leading) {
                                        timeline.trimInMs = Math.round(Math.max(0, Math.min(block.clip.outMs - minimum, block.clip.inMs + delta)))
                                        timeline.trimPreviewRequested(block.index, timeline.trimInMs)
                                    } else {
                                        timeline.trimOutMs = Math.round(Math.max(block.clip.inMs + minimum, Math.min(block.clip.durationMs, block.clip.outMs + delta)))
                                        timeline.trimPreviewRequested(block.index, Math.max(block.clip.inMs, timeline.trimOutMs - 40))
                                    }
                                }
                                onReleased: {
                                    if (timeline.trimIndex === block.index) {
                                        var changed = timeline.trimInMs !== block.clip.inMs || timeline.trimOutMs !== block.clip.outMs
                                        var preview = leading ? timeline.trimInMs : Math.max(timeline.trimInMs, timeline.trimOutMs - 40)
                                        timeline.trimIndex = -1
                                        if (changed) timeline.trimRequested(block.index, timeline.trimInMs, timeline.trimOutMs, preview)
                                    }
                                    timeline.trimFinished()
                                }
                                onCanceled: timeline.cancelTrim()
                                // Notch: this edge hides trimmed media that can be dragged back out.
                                readonly property real hiddenMs: leading ? block.clip.inMs : block.clip.durationMs - block.clip.outMs
                                Rectangle {
                                    visible: edge.hiddenMs >= 50
                                    x: edge.leading ? 0 : parent.width - width
                                    y: 0
                                    width: 3
                                    height: parent.height
                                    color: Theme.accent
                                    opacity: edge.containsMouse || edge.pressed ? 0.9 : 0.45
                                }
                                ToolTip.visible: containsMouse && !pressed
                                ToolTip.delay: 500
                                ToolTip.text: hiddenMs >= 50 ? "Drag to trim · " + (hiddenMs / 1000).toFixed(2) + " s hidden beyond this edge" : "Drag to trim"
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: edge.leading ? 3 : parent.width - width - 3
                                    width: 4
                                    height: Math.min(30, block.height - 16)
                                    radius: 2
                                    color: edge.pressed ? Theme.accent : Theme.text
                                    opacity: edge.pressed || edge.containsMouse ? 1 : block.active ? 0.55 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.fadeFast } }
                                }
                            }
                        }
                    }
                }

                // Insertion marker while reordering.
                Rectangle {
                    visible: timeline.dragIndex >= 0
                    readonly property real slotMs: {
                        if (timeline.dragIndex < 0) return 0
                        return timeline.layoutStarts[timeline.dragIndex] || 0
                    }
                    x: slotMs * timeline.pxPerMs - 1
                    width: 3
                    height: track.height
                    radius: 2
                    color: Theme.accent
                    Behavior on x { SmoothSpring {} }
                }
            }

            // Pointer-following guide over the track.
            Rectangle {
                visible: hover.hovered && timeline.totalMs > 0 && timeline.dragIndex < 0 && hover.point.position.y > ruler.height
                x: Math.round(hover.point.position.x)
                y: ruler.height
                width: 1
                height: parent.height - ruler.height
                color: Theme.textSoft
                opacity: 0.35
            }

            // Playhead.
            Item {
                id: playhead
                visible: timeline.totalMs > 0
                x: Math.round(timeline.shownMs * timeline.pxPerMs)
                height: parent.height
                z: 10
                Rectangle { x: -1; y: 22; width: 2; height: parent.height - 22; color: Theme.playhead }
                Item {
                    id: flag
                    readonly property real flagWidth: 58
                    x: Math.max(-playhead.x, Math.min(content.width - playhead.x - flagWidth, -flagWidth / 2))
                    width: flagWidth
                    height: 30
                    readonly property real tip: -x
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: flagMouse.pressed ? Theme.playheadPressed : flagMouse.containsMouse ? Theme.playheadHover : Theme.playheadWash
                            strokeColor: timeline.activeFocus ? Theme.playheadInk : Theme.playhead
                            strokeWidth: 1
                            joinStyle: ShapePath.RoundJoin
                            PathSvg {
                                readonly property real w: flag.width - 0.5
                                readonly property real t: Math.max(1, Math.min(flag.width - 1, flag.tip))
                                path: "M5 0.5 H" + (w - 5) + " Q" + w + " 0.5 " + w + " 5 V19 H" + Math.min(w, t + 6)
                                      + " L" + t + " 27 L" + Math.max(0.5, t - 6) + " 19 H0.5 V5 Q0.5 0.5 5 0.5 Z"
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        height: 19
                        text: timeline.timeLabel(timeline.shownMs, true)
                        color: Theme.playheadInk
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    MouseArea {
                        id: flagMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: Qt.SizeHorCursor
                        property real startX: 0
                        property real startMs: 0
                        onPressed: function(mouse) {
                            timeline.forceActiveFocus()
                            startX = mapToItem(timeline, mouse.x, 0).x
                            startMs = timeline.playheadMs
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed) return
                            var next = startMs + (mapToItem(timeline, mouse.x, 0).x - startX) / Math.max(timeline.pxPerMs, 0.0001)
                            timeline.scrubRequested(Math.max(0, Math.min(timeline.totalMs, next)))
                        }
                        onReleased: timeline.scrubFinished()
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: flick
        visible: timeline.clips.length === 0
        text: "Import media to start a sequence"
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }

    Menu {
        id: clipMenu
        padding: 5
        background: Rectangle { implicitWidth: 190; radius: Theme.radius; color: Theme.card; border.color: Theme.lineStrong }
        enter: Transition { ParallelAnimation { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.fadeFast } SnapSpring { property: "scale"; from: 0.96; to: 1 } } }
        delegate: MenuItem {
            id: menuItem
            implicitHeight: 32
            contentItem: Text {
                leftPadding: 8
                text: menuItem.text
                color: !menuItem.enabled ? Theme.textDisabled : menuItem.text === "Remove" ? Theme.danger : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 12
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle { radius: Theme.radiusSmall; color: menuItem.highlighted ? Theme.hover : "transparent" }
        }
        Action { text: "Split at playhead"; onTriggered: timeline.splitRequested() }
        Action { text: "Duplicate"; onTriggered: timeline.duplicateRequested(timeline.activeIndex) }
        Action { text: "Remove"; enabled: timeline.clips.length > 1; onTriggered: timeline.removeRequested(timeline.activeIndex) }
    }
}
