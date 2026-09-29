import QtQuick
import QtQuick.Effects
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
    // Marks on the joins when clips fade or crossfade.
    property string transition: "cut"
    // The audio track under the clips: items placed at a sequence time.
    property var audioItems: []
    property int audioIndex: -1

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
    signal audioSelectRequested(int index)
    signal audioPlaceRequested(int index, real startMs, real inMs, real outMs)
    signal audioRemoveRequested(int index)
    signal audioSplitRequested(int index, real atMs)
    signal audioFadeRequested(int index, real fadeInMs, real fadeOutMs)
    signal audioAddRequested(real startMs)
    signal audioDropped(var urls, real startMs)
    property var textItems: []
    property int textIndex: -1
    signal textSelectRequested(int index)
    signal textPlaceRequested(int index, real startMs, real endMs)
    signal textAddRequested(real startMs)
    signal textRemoveRequested(int index)
    signal textSplitRequested(int index, real atMs)
    signal textDuplicateRequested(int index)
    signal textEditRequested(int index)

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
    function cancelTrim() { trimIndex = -1; audioEditIndex = -1; audioFadeIndex = -1; textEditIndex = -1; snapGuideMs = -1 }

    // Caption being moved or trimmed, committed on release.
    property int textEditIndex: -1
    property real textEditStart: 0
    property real textEditEnd: 0

    // Audio track edits are previewed the same way: startMs/inMs/outMs of the
    // item being moved or trimmed, committed on release.
    property int audioEditIndex: -1
    property real audioEditStart: 0
    property real audioEditIn: 0
    property real audioEditOut: 0
    // Fade handles being dragged on an audio item.
    property int audioFadeIndex: -1
    property real audioFadeIn: 0
    property real audioFadeOut: 0
    // Where the dragged audio item snapped, drawn as a guide (-1 when it didn't).
    property real snapGuideMs: -1
    // Pulls a time to a nearby join, the playhead, the ends or another audio item.
    function snapMs(ms, skipIndex, skipText) {
        var reach = 8 / Math.max(pxPerMs, 0.0001)
        var points = [0, totalMs, playheadMs].concat(starts)
        for (var i = 0; i < audioItems.length; i++) {
            if (i === skipIndex) continue
            points.push(audioItems[i].startMs, audioItems[i].startMs + audioItems[i].lengthMs)
        }
        for (var t = 0; t < textItems.length; t++) {
            if (t === skipText) continue
            points.push(textItems[t].startMs, textItems[t].endMs)
        }
        var best = ms, distance = reach
        for (var k = 0; k < points.length; k++) {
            if (Math.abs(points[k] - ms) < distance) {
                distance = Math.abs(points[k] - ms)
                best = points[k]
            }
        }
        return best
    }

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

    implicitHeight: 176
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
        else if (event.key === Qt.Key_Escape && (trimIndex >= 0 || audioEditIndex >= 0 || textEditIndex >= 0)) { cancelTrim(); event.accepted = true; return }
        else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && textIndex >= 0) timeline.textRemoveRequested(textIndex)
        else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && audioIndex >= 0) timeline.audioRemoveRequested(audioIndex)
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
                height: parent.height - y - (audioLane.visible ? audioLane.height + 4 : 0) - (textLane.visible ? textLane.height + 4 : 0)

                Repeater {
                    model: timeline.clips.length
                    delegate: Item {
                        id: block
                        required property int index
                        readonly property var clip: timeline.clips[index] || ({ url: "", name: "", durationMs: 0, inMs: 0, outMs: 0, lengthMs: 0 })
                        readonly property bool active: timeline.activeIndex === index
                        // Source media per timeline pixel: a 2x clip packs twice the footage.
                        readonly property real srcPxPerMs: timeline.pxPerMs / (clip.speed || 1)
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
                                        readonly property real sourceMs: block.clip.inMs + (tile + 0.5) * film.tileWidth / Math.max(block.srcPxPerMs, 0.0001)
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
                                // Silence reads as a flat line rather than an empty lane.
                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.waveInk
                                    opacity: block.clip.muted ? 0.12 : 0.3
                                }
                                Image {
                                    x: -block.clip.inMs * block.srcPxPerMs
                                    width: block.clip.durationMs * block.srcPxPerMs
                                    height: parent.height - 4
                                    y: 2
                                    source: block.waveform
                                    fillMode: Image.Stretch
                                    smooth: true
                                    opacity: block.clip.muted ? 0.1 : block.active ? 0.7 : 0.4
                                    // The waveform image is white; ink it on light surfaces.
                                    layer.enabled: !Theme.dark
                                    layer.effect: MultiEffect { colorization: 1; colorizationColor: Theme.waveInk }
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
                                    text: (block.index + 1).toString().padStart(2, "0") + "  " + block.clip.name + "  " + timeline.timeLabel(block.clip.lengthMs, true) + ((block.clip.speed || 1) !== 1 ? "  " + block.clip.speed + "×" : "")
                                          + (block.clip.muted ? "  · muted" : block.clip.volume !== undefined && Math.abs(block.clip.volume - 1) > 0.001 ? "  · " + Math.round(block.clip.volume * 100) + "%" : "")
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
                            readonly property real inX: (timeline.trimInMs - block.clip.inMs) * block.srcPxPerMs
                            readonly property real outX: (timeline.trimOutMs - block.clip.inMs) * block.srcPxPerMs
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
                                    var delta = (mapToItem(timeline, mouse.x, 0).x - pressX) / Math.max(block.srcPxPerMs, 0.0001)
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

            // Joins that fade or crossfade.
            Repeater {
                model: timeline.transition !== "cut" && timeline.dragIndex < 0 ? Math.max(0, timeline.clips.length - 1) : 0
                delegate: Rectangle {
                    required property int index
                    x: (timeline.starts[index + 1] || 0) * timeline.pxPerMs - width / 2 - 0.5
                    y: track.y + track.height / 2 - height / 2
                    z: 6
                    width: 12
                    height: 12
                    rotation: 45
                    radius: 2
                    color: timeline.transition === "fade" ? "black" : Theme.accent
                    border.color: timeline.transition === "fade" ? Theme.accent : Theme.accentInk
                    border.width: 1.5
                }
            }

            // Audio track: music and sounds placed anywhere under the clips.
            // Anything past the end of the video is cut off, so the lane is too.
            Rectangle {
                id: audioLane
                objectName: "audioLane"
                visible: timeline.clips.length > 0
                y: track.y + track.height + 4
                width: Math.max(3, timeline.totalMs * timeline.pxPerMs - 1)
                height: 34
                radius: Theme.radiusSmall
                color: laneDrop.containsDrag ? Theme.selectionFill : Theme.field
                border.color: laneDrop.containsDrag ? Theme.accent : Theme.line
                clip: true

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onPressed: timeline.forceActiveFocus()
                    onClicked: function(mouse) {
                        timeline.audioSelectRequested(-1)
                        timeline.scrubRequested(timeline.msAt(mouse.x))
                        timeline.scrubFinished()
                    }
                    onDoubleClicked: function(mouse) { timeline.audioAddRequested(timeline.msAt(mouse.x)) }
                }
                DropArea {
                    id: laneDrop
                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    onDropped: function(drop) {
                        if (drop.urls.length > 0) timeline.audioDropped(drop.urls, timeline.msAt(drop.x))
                        drop.accept()
                    }
                }
                Row {
                    visible: timeline.audioItems.length === 0
                    x: Math.max(8, flick.contentX + 8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    ToolIcon { name: "music"; tint: Theme.textFaint; width: 12; height: 12; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Audio track · drop music or sounds here, or double-click to add"
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Repeater {
                    model: timeline.audioItems.length
                    delegate: Item {
                        id: audioBlock
                        required property int index
                        readonly property var item: timeline.audioItems[index] || ({ url: "", name: "", durationMs: 0, startMs: 0, inMs: 0, outMs: 0, lengthMs: 0, volume: 1 })
                        readonly property bool editing: timeline.audioEditIndex === index
                        readonly property real startMs: editing ? timeline.audioEditStart : item.startMs
                        readonly property real inMs: editing ? timeline.audioEditIn : item.inMs
                        readonly property real outMs: editing ? timeline.audioEditOut : item.outMs
                        readonly property bool active: timeline.audioIndex === index
                        readonly property string waveform: timeline.thumbnailSource && timeline.thumbnailSource.revision >= 0 ? timeline.thumbnailSource.waveformFor(item.url) : ""
                        x: startMs * timeline.pxPerMs
                        z: editing ? 3 : active ? 2 : 1
                        width: Math.max(3, (outMs - inMs) * timeline.pxPerMs)
                        height: audioLane.height

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 4
                            color: audioBlock.active ? Theme.waveActive : Theme.accentWash
                            border.width: audioBlock.active ? 2 : 1
                            border.color: audioBlock.active ? Theme.accent : audioMouse.containsMouse ? Theme.accent : Theme.accentEdge
                            clip: true
                            Rectangle {
                                visible: audioBlock.waveform.length === 0
                                width: parent.width
                                height: 1
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.waveInk
                                opacity: 0.3
                            }
                            Image {
                                x: -audioBlock.inMs * timeline.pxPerMs
                                width: audioBlock.item.durationMs * timeline.pxPerMs
                                height: parent.height - 4
                                y: 2
                                source: audioBlock.waveform
                                fillMode: Image.Stretch
                                opacity: audioBlock.active ? 0.6 : 0.35
                                layer.enabled: !Theme.dark
                                layer.effect: MultiEffect { colorization: 1; colorizationColor: Theme.waveInk }
                            }
                            Row {
                                x: 5
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                visible: audioBlock.width > 40
                                ToolIcon { name: "music"; tint: Theme.accent; width: 11; height: 11; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    width: Math.max(0, audioBlock.width - 30)
                                    text: audioBlock.item.name + "  " + Math.round(audioBlock.item.volume * 100) + "%"
                                    color: audioBlock.active ? Theme.accentSoft : Theme.textSoft
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Body: drag to move along the sequence.
                        MouseArea {
                            id: audioMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            preventStealing: true
                            cursorShape: audioBlock.editing ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property real pressX: 0
                            property bool moved: false
                            onPressed: function(mouse) {
                                timeline.forceActiveFocus()
                                pressX = mapToItem(timeline, mouse.x, 0).x
                                moved = false
                                timeline.audioSelectRequested(audioBlock.index)
                                if (mouse.button === Qt.RightButton) {
                                    timeline.menuMs = audioBlock.item.startMs + mouse.x / Math.max(timeline.pxPerMs, 0.0001)
                                    audioMenu.popup()
                                }
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed || !(pressedButtons & Qt.LeftButton)) return
                                var offset = mapToItem(timeline, mouse.x, 0).x - pressX
                                if (!moved && Math.abs(offset) < 5) return
                                moved = true
                                var length = audioBlock.item.lengthMs
                                var start = Math.max(0, audioBlock.item.startMs + offset / Math.max(timeline.pxPerMs, 0.0001))
                                // Either end may catch a snap point.
                                var head = timeline.snapMs(start, audioBlock.index)
                                var tail = timeline.snapMs(start + length, audioBlock.index) - length
                                timeline.snapGuideMs = head !== start ? head : tail !== start ? tail + length : -1
                                start = head !== start ? head : tail !== start ? tail : start
                                timeline.audioEditIn = audioBlock.item.inMs
                                timeline.audioEditOut = audioBlock.item.outMs
                                timeline.audioEditStart = Math.round(Math.max(0, Math.min(Math.max(0, timeline.totalMs - 100), start)))
                                timeline.audioEditIndex = audioBlock.index
                            }
                            onReleased: function(mouse) {
                                if (mouse.button !== Qt.LeftButton) return
                                timeline.snapGuideMs = -1
                                if (timeline.audioEditIndex === audioBlock.index) {
                                    timeline.audioEditIndex = -1
                                    if (timeline.audioEditStart !== audioBlock.item.startMs)
                                        timeline.audioPlaceRequested(audioBlock.index, timeline.audioEditStart, audioBlock.item.inMs, audioBlock.item.outMs)
                                } else if (!moved) {
                                    timeline.scrubRequested(audioBlock.item.startMs + mouse.x / Math.max(timeline.pxPerMs, 0.0001))
                                    timeline.scrubFinished()
                                }
                            }
                            onCanceled: { timeline.audioEditIndex = -1; timeline.snapGuideMs = -1 }
                            ToolTip.visible: containsMouse && !pressed
                            ToolTip.delay: 700
                            ToolTip.text: audioBlock.item.name + " · starts at " + timeline.timeLabel(audioBlock.item.startMs, true) + " · drag to move, edges to trim"
                        }

                        // Edges trim the part of the file that plays.
                        Repeater {
                            model: 2
                            delegate: MouseArea {
                                id: audioEdge
                                required property int index
                                readonly property bool leading: index === 0
                                x: leading ? 0 : audioBlock.width - width
                                width: Math.min(10, audioBlock.width / 3)
                                height: audioBlock.height
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: Qt.SizeHorCursor
                                property real pressX: 0
                                onPressed: function(mouse) {
                                    timeline.forceActiveFocus()
                                    timeline.audioSelectRequested(audioBlock.index)
                                    pressX = mapToItem(timeline, mouse.x, 0).x
                                    timeline.audioEditStart = audioBlock.item.startMs
                                    timeline.audioEditIn = audioBlock.item.inMs
                                    timeline.audioEditOut = audioBlock.item.outMs
                                    timeline.audioEditIndex = audioBlock.index
                                }
                                onPositionChanged: function(mouse) {
                                    if (!pressed || timeline.audioEditIndex !== audioBlock.index) return
                                    var item = audioBlock.item
                                    var delta = (mapToItem(timeline, mouse.x, 0).x - pressX) / Math.max(timeline.pxPerMs, 0.0001)
                                    var minimum = Math.min(100, item.durationMs)
                                    if (leading) {
                                        // The start moves with the in point so the rest stays in place.
                                        var raw = item.startMs + delta
                                        var start = timeline.snapMs(raw, audioBlock.index)
                                        timeline.snapGuideMs = start !== raw ? start : -1
                                        var shift = Math.max(-item.inMs, -item.startMs, Math.min(item.lengthMs - minimum, start - item.startMs))
                                        timeline.audioEditIn = Math.round(item.inMs + shift)
                                        timeline.audioEditStart = Math.round(item.startMs + shift)
                                    } else {
                                        var rawEnd = item.startMs + item.lengthMs + delta
                                        var end = timeline.snapMs(rawEnd, audioBlock.index)
                                        timeline.snapGuideMs = end !== rawEnd ? end : -1
                                        timeline.audioEditOut = Math.round(Math.max(item.inMs + minimum, Math.min(item.durationMs, item.inMs + end - item.startMs)))
                                    }
                                }
                                onReleased: {
                                    timeline.snapGuideMs = -1
                                    if (timeline.audioEditIndex !== audioBlock.index) return
                                    timeline.audioEditIndex = -1
                                    var item = audioBlock.item
                                    if (timeline.audioEditStart !== item.startMs || timeline.audioEditIn !== item.inMs || timeline.audioEditOut !== item.outMs)
                                        timeline.audioPlaceRequested(audioBlock.index, timeline.audioEditStart, timeline.audioEditIn, timeline.audioEditOut)
                                }
                                onCanceled: { timeline.audioEditIndex = -1; timeline.snapGuideMs = -1 }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: audioEdge.leading ? 3 : parent.width - width - 3
                                    width: 3
                                    height: Math.min(14, audioBlock.height - 10)
                                    radius: 2
                                    color: audioEdge.pressed ? Theme.accent : Theme.text
                                    opacity: audioEdge.pressed || audioEdge.containsMouse ? 1 : audioBlock.active ? 0.5 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.fadeFast } }
                                }
                            }
                        }

                        // Fades: the ramps are shaded, and a dot at each top
                        // corner drags the fade longer or shorter.
                        readonly property bool fading: timeline.audioFadeIndex === index
                        readonly property real fadeInMs: fading ? timeline.audioFadeIn : item.fadeInMs || 0
                        readonly property real fadeOutMs: fading ? timeline.audioFadeOut : item.fadeOutMs || 0
                        Shape {
                            id: fadeShape
                            anchors.fill: parent
                            anchors.margins: 2
                            z: 1
                            preferredRendererType: Shape.CurveRenderer
                            readonly property real inX: audioBlock.fadeInMs * timeline.pxPerMs
                            readonly property real outX: width - audioBlock.fadeOutMs * timeline.pxPerMs
                            ShapePath {
                                strokeColor: Theme.accent
                                strokeWidth: 1.5
                                fillColor: Theme.scrim
                                startX: 0; startY: fadeShape.height
                                PathLine { x: 0; y: 0 }
                                PathLine { x: Math.max(0, fadeShape.inX); y: 0 }
                                PathLine { x: 0; y: fadeShape.height }
                            }
                            ShapePath {
                                strokeColor: Theme.accent
                                strokeWidth: 1.5
                                fillColor: Theme.scrim
                                startX: fadeShape.width; startY: fadeShape.height
                                PathLine { x: fadeShape.width; y: 0 }
                                PathLine { x: Math.min(fadeShape.width, fadeShape.outX); y: 0 }
                                PathLine { x: fadeShape.width; y: fadeShape.height }
                            }
                        }
                        Repeater {
                            model: 2
                            delegate: MouseArea {
                                id: fadeHandle
                                required property int index
                                readonly property bool leading: index === 0
                                readonly property real centerX: leading ? Math.max(6, audioBlock.fadeInMs * timeline.pxPerMs)
                                                                        : Math.min(audioBlock.width - 6, audioBlock.width - audioBlock.fadeOutMs * timeline.pxPerMs)
                                visible: audioBlock.width > 36 && (audioBlock.active || audioMouse.containsMouse || containsMouse || pressed
                                                                   || (leading ? audioBlock.fadeInMs : audioBlock.fadeOutMs) > 0)
                                x: centerX - width / 2
                                y: 0
                                z: 4
                                width: 14
                                height: 12
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: Qt.SizeHorCursor
                                property real pressX: 0
                                onPressed: function(mouse) {
                                    timeline.forceActiveFocus()
                                    timeline.audioSelectRequested(audioBlock.index)
                                    pressX = mapToItem(timeline, mouse.x, 0).x
                                    timeline.audioFadeIn = audioBlock.item.fadeInMs || 0
                                    timeline.audioFadeOut = audioBlock.item.fadeOutMs || 0
                                    timeline.audioFadeIndex = audioBlock.index
                                }
                                onPositionChanged: function(mouse) {
                                    if (!pressed || timeline.audioFadeIndex !== audioBlock.index) return
                                    var item = audioBlock.item
                                    var delta = (mapToItem(timeline, mouse.x, 0).x - pressX) / Math.max(timeline.pxPerMs, 0.0001)
                                    if (leading)
                                        timeline.audioFadeIn = Math.round(Math.max(0, Math.min(item.lengthMs - timeline.audioFadeOut, (item.fadeInMs || 0) + delta)))
                                    else
                                        timeline.audioFadeOut = Math.round(Math.max(0, Math.min(item.lengthMs - timeline.audioFadeIn, (item.fadeOutMs || 0) - delta)))
                                }
                                onReleased: {
                                    if (timeline.audioFadeIndex !== audioBlock.index) return
                                    timeline.audioFadeIndex = -1
                                    if (timeline.audioFadeIn !== (audioBlock.item.fadeInMs || 0) || timeline.audioFadeOut !== (audioBlock.item.fadeOutMs || 0))
                                        timeline.audioFadeRequested(audioBlock.index, timeline.audioFadeIn, timeline.audioFadeOut)
                                }
                                onCanceled: timeline.audioFadeIndex = -1
                                ToolTip.visible: containsMouse && !pressed
                                ToolTip.delay: 400
                                ToolTip.text: (leading ? "Fade in" : "Fade out") + " · drag to change"
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: fadeHandle.pressed || fadeHandle.containsMouse ? 10 : 8
                                    height: width
                                    radius: width / 2
                                    color: Theme.accent
                                    border.color: Theme.accentInk
                                    border.width: 1
                                    Behavior on width { NumberAnimation { duration: Theme.fadeFast } }
                                }
                                Rectangle {
                                    visible: fadeHandle.pressed
                                    x: fadeHandle.leading ? parent.width + 2 : -width - 2
                                    y: 0
                                    width: fadeLabel.implicitWidth + 10
                                    height: 16
                                    radius: 4
                                    color: Theme.accent
                                    Text {
                                        id: fadeLabel
                                        anchors.centerIn: parent
                                        text: ((fadeHandle.leading ? timeline.audioFadeIn : timeline.audioFadeOut) / 1000).toFixed(1) + " s"
                                        color: Theme.accentInk
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Text track: captions drawn over the video for a stretch of the sequence.
            Rectangle {
                id: textLane
                objectName: "textLane"
                visible: timeline.clips.length > 0
                y: audioLane.y + audioLane.height + 4
                width: audioLane.width
                height: 22
                radius: Theme.radiusSmall
                color: Theme.field
                border.color: Theme.line
                clip: true

                MouseArea {
                    anchors.fill: parent
                    onPressed: timeline.forceActiveFocus()
                    onClicked: function(mouse) {
                        timeline.textSelectRequested(-1)
                        timeline.scrubRequested(timeline.msAt(mouse.x))
                        timeline.scrubFinished()
                    }
                    onDoubleClicked: function(mouse) { timeline.textAddRequested(timeline.msAt(mouse.x)) }
                }
                Text {
                    visible: timeline.textItems.length === 0
                    x: Math.max(8, flick.contentX + 8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Text track · double-click to put a caption on the video"
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Repeater {
                    model: timeline.textItems.length
                    delegate: Item {
                        id: textBlock
                        required property int index
                        readonly property var item: timeline.textItems[index] || ({ text: "", startMs: 0, endMs: 0, lengthMs: 0 })
                        readonly property bool editing: timeline.textEditIndex === index
                        readonly property real startMs: editing ? timeline.textEditStart : item.startMs
                        readonly property real endMs: editing ? timeline.textEditEnd : item.endMs
                        readonly property bool active: timeline.textIndex === index
                        x: startMs * timeline.pxPerMs
                        z: editing ? 3 : active ? 2 : 1
                        width: Math.max(3, (endMs - startMs) * timeline.pxPerMs)
                        height: textLane.height

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 4
                            color: textBlock.active ? Theme.playheadHover : Theme.playheadWash
                            border.width: textBlock.active ? 2 : 1
                            border.color: textBlock.active || textMouse.containsMouse ? Theme.playhead : Theme.line
                            clip: true
                            Text {
                                x: 6
                                width: Math.max(0, parent.width - 12)
                                anchors.verticalCenter: parent.verticalCenter
                                visible: parent.width > 24
                                text: textBlock.item.text.replace(/\s+/g, " ")
                                color: Theme.playheadInk
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }

                        // Body: drag to move, click to select.
                        MouseArea {
                            id: textMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            preventStealing: true
                            cursorShape: textBlock.editing ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property real pressX: 0
                            property bool moved: false
                            // Double-click opens the text for typing on the video.
                            onDoubleClicked: function(mouse) {
                                if (mouse.button === Qt.LeftButton) timeline.textEditRequested(textBlock.index)
                            }
                            onPressed: function(mouse) {
                                timeline.forceActiveFocus()
                                pressX = mapToItem(timeline, mouse.x, 0).x
                                moved = false
                                timeline.textSelectRequested(textBlock.index)
                                if (mouse.button === Qt.RightButton) {
                                    timeline.menuMs = textBlock.item.startMs + mouse.x / Math.max(timeline.pxPerMs, 0.0001)
                                    textMenu.popup()
                                }
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed || !(pressedButtons & Qt.LeftButton)) return
                                var offset = mapToItem(timeline, mouse.x, 0).x - pressX
                                if (!moved && Math.abs(offset) < 5) return
                                moved = true
                                var length = textBlock.item.lengthMs
                                var start = Math.max(0, textBlock.item.startMs + offset / Math.max(timeline.pxPerMs, 0.0001))
                                var head = timeline.snapMs(start, -1, textBlock.index)
                                var tail = timeline.snapMs(start + length, -1, textBlock.index) - length
                                timeline.snapGuideMs = head !== start ? head : tail !== start ? tail + length : -1
                                start = head !== start ? head : tail !== start ? tail : start
                                start = Math.round(Math.max(0, Math.min(timeline.totalMs - length, start)))
                                timeline.textEditStart = start
                                timeline.textEditEnd = start + length
                                timeline.textEditIndex = textBlock.index
                            }
                            onReleased: function(mouse) {
                                if (mouse.button !== Qt.LeftButton) return
                                timeline.snapGuideMs = -1
                                if (timeline.textEditIndex === textBlock.index) {
                                    timeline.textEditIndex = -1
                                    if (timeline.textEditStart !== textBlock.item.startMs)
                                        timeline.textPlaceRequested(textBlock.index, timeline.textEditStart, timeline.textEditEnd)
                                } else if (!moved) {
                                    timeline.scrubRequested(textBlock.item.startMs + mouse.x / Math.max(timeline.pxPerMs, 0.0001))
                                    timeline.scrubFinished()
                                }
                            }
                            onCanceled: { timeline.textEditIndex = -1; timeline.snapGuideMs = -1 }
                            ToolTip.visible: containsMouse && !pressed
                            ToolTip.delay: 700
                            ToolTip.text: timeline.timeLabel(textBlock.item.startMs, true) + " – " + timeline.timeLabel(textBlock.item.endMs, true) + " · drag to move, edges to change how long it shows, right-click for more"
                        }

                        // Edges change when the caption appears and disappears.
                        Repeater {
                            model: 2
                            delegate: MouseArea {
                                id: textEdge
                                required property int index
                                readonly property bool leading: index === 0
                                x: leading ? 0 : textBlock.width - width
                                width: Math.min(8, textBlock.width / 3)
                                height: textBlock.height
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: Qt.SizeHorCursor
                                property real pressX: 0
                                onPressed: function(mouse) {
                                    timeline.forceActiveFocus()
                                    timeline.textSelectRequested(textBlock.index)
                                    pressX = mapToItem(timeline, mouse.x, 0).x
                                    timeline.textEditStart = textBlock.item.startMs
                                    timeline.textEditEnd = textBlock.item.endMs
                                    timeline.textEditIndex = textBlock.index
                                }
                                onPositionChanged: function(mouse) {
                                    if (!pressed || timeline.textEditIndex !== textBlock.index) return
                                    var item = textBlock.item
                                    var delta = (mapToItem(timeline, mouse.x, 0).x - pressX) / Math.max(timeline.pxPerMs, 0.0001)
                                    var raw = (leading ? item.startMs : item.endMs) + delta
                                    var edge = timeline.snapMs(raw, -1, textBlock.index)
                                    timeline.snapGuideMs = edge !== raw ? edge : -1
                                    if (leading)
                                        timeline.textEditStart = Math.round(Math.max(0, Math.min(item.endMs - 200, edge)))
                                    else
                                        timeline.textEditEnd = Math.round(Math.max(item.startMs + 200, Math.min(timeline.totalMs, edge)))
                                }
                                onReleased: {
                                    timeline.snapGuideMs = -1
                                    if (timeline.textEditIndex !== textBlock.index) return
                                    timeline.textEditIndex = -1
                                    if (timeline.textEditStart !== textBlock.item.startMs || timeline.textEditEnd !== textBlock.item.endMs)
                                        timeline.textPlaceRequested(textBlock.index, timeline.textEditStart, timeline.textEditEnd)
                                }
                                onCanceled: { timeline.textEditIndex = -1; timeline.snapGuideMs = -1 }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: textEdge.leading ? 3 : parent.width - width - 3
                                    width: 3
                                    height: Math.min(10, textBlock.height - 8)
                                    radius: 2
                                    color: textEdge.pressed ? Theme.playhead : Theme.text
                                    opacity: textEdge.pressed || textEdge.containsMouse ? 1 : textBlock.active ? 0.5 : 0
                                }
                            }
                        }
                    }
                }
            }

            // Snap guide while an audio item is dragged onto a join, the playhead or another item.
            Rectangle {
                visible: timeline.snapGuideMs >= 0
                x: Math.round(timeline.snapGuideMs * timeline.pxPerMs) - 1
                y: ruler.height
                z: 9
                width: 2
                height: parent.height - ruler.height
                color: Theme.accent
                opacity: 0.85
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

    // Right-click menus share one look; "Remove" is red.
    component TimelineMenu: Menu {
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
            background: Rectangle { radius: Theme.radiusSmall; color: menuItem.highlighted ? Theme.hover : Theme.hoverClear }
        }
    }
    // Where the menu was opened, in sequence time.
    property real menuMs: 0

    TimelineMenu {
        id: clipMenu
        Action { text: "Split at playhead"; onTriggered: timeline.splitRequested() }
        Action { text: "Duplicate"; onTriggered: timeline.duplicateRequested(timeline.activeIndex) }
        Action { text: "Remove"; enabled: timeline.clips.length > 1; onTriggered: timeline.removeRequested(timeline.activeIndex) }
    }
    TimelineMenu {
        id: audioMenu
        objectName: "audioMenu"
        readonly property var item: timeline.audioItems[timeline.audioIndex]
        Action {
            text: "Split here"
            enabled: !!audioMenu.item && timeline.menuMs - audioMenu.item.startMs >= 100
                     && audioMenu.item.startMs + audioMenu.item.lengthMs - timeline.menuMs >= 100
            onTriggered: timeline.audioSplitRequested(timeline.audioIndex, timeline.menuMs)
        }
        Action { text: "Move to playhead"; onTriggered: { var item = timeline.audioItems[timeline.audioIndex]; if (item) timeline.audioPlaceRequested(timeline.audioIndex, timeline.playheadMs, item.inMs, item.outMs) } }
        Action { text: "Remove"; onTriggered: timeline.audioRemoveRequested(timeline.audioIndex) }
    }
    TimelineMenu {
        id: textMenu
        objectName: "textMenu"
        readonly property var item: timeline.textItems[timeline.textIndex]
        Action {
            text: "Split here"
            enabled: !!textMenu.item && timeline.menuMs - textMenu.item.startMs >= 200 && textMenu.item.endMs - timeline.menuMs >= 200
            onTriggered: timeline.textSplitRequested(timeline.textIndex, timeline.menuMs)
        }
        Action { text: "Duplicate"; onTriggered: timeline.textDuplicateRequested(timeline.textIndex) }
        Action { text: "Remove"; onTriggered: timeline.textRemoveRequested(timeline.textIndex) }
    }
}
