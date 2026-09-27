import QtQuick

// A region of the picture for split screen: drag inside to move it, drag a
// corner or an edge to resize it. With `ratio` (width / height in picture
// pixels) above zero the shape is locked and only the corners resize. The
// area is normalized to the picture and reported live through `moved`, so
// the preview follows the pointer. Inside the frame the video shows undimmed.
Item {
    id: region
    property rect area: Qt.rect(0, 0, 1, 1)
    property real ratio: 0
    // The picture's width / height, to convert `ratio` to normalized units.
    property real pictureAspect: 16 / 9
    property color tint: Theme.accent
    property color ink: Theme.accentInk
    property string label: ""
    property Item sourceItem: null
    // Where the picture sits inside sourceItem.
    property rect sourcePicture: Qt.rect(0, 0, 0, 0)
    readonly property bool active: moveArea.pressed || resizing
    property bool resizing: false
    signal moved(rect area)

    readonly property real minSize: 0.05
    // Normalized height for a normalized width at `ratio`, and back.
    function heightFor(w) { return w * pictureAspect / ratio }
    function widthFor(h) { return h * ratio / pictureAspect }

    Rectangle {
        id: box
        x: region.area.x * region.width
        y: region.area.y * region.height
        width: region.area.width * region.width
        height: region.area.height * region.height
        color: "transparent"
        border.width: 2
        border.color: region.tint

        ShaderEffectSource {
            anchors.fill: parent
            anchors.margins: 2
            z: -1
            sourceItem: region.sourceItem
            live: true
            sourceRect: Qt.rect(region.sourcePicture.x + region.area.x * region.sourcePicture.width,
                                region.sourcePicture.y + region.area.y * region.sourcePicture.height,
                                region.area.width * region.sourcePicture.width,
                                region.area.height * region.sourcePicture.height)
        }
        Rectangle {
            x: 6
            y: 6
            visible: region.label.length > 0
            width: tag.implicitWidth + 14
            height: 20
            radius: 10
            color: region.tint
            Text { id: tag; anchors.centerIn: parent; text: region.label; color: region.ink; font.pixelSize: 10; font.weight: Font.DemiBold }
        }
        MouseArea {
            id: moveArea
            anchors.fill: parent
            anchors.margins: 10
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point grab
            property rect start
            onPressed: function(mouse) {
                var p = mapToItem(region, mouse.x, mouse.y)
                grab = Qt.point(p.x / region.width, p.y / region.height)
                start = region.area
            }
            onPositionChanged: function(mouse) {
                if (!pressed) return
                var p = mapToItem(region, mouse.x, mouse.y)
                var nx = Math.max(0, Math.min(1 - start.width, start.x + p.x / region.width - grab.x))
                var ny = Math.max(0, Math.min(1 - start.height, start.y + p.y / region.height - grab.y))
                region.moved(Qt.rect(nx, ny, start.width, start.height))
            }
        }
    }

    // Handles: [horizontal, vertical] with 0 = left/top, 0.5 = middle, 1 = right/bottom.
    Repeater {
        model: [[0, 0], [1, 0], [0, 1], [1, 1], [0.5, 0], [0.5, 1], [0, 0.5], [1, 0.5]]
        delegate: Item {
            id: handle
            required property var modelData
            readonly property real hx: modelData[0]
            readonly property real hy: modelData[1]
            readonly property bool corner: hx !== 0.5 && hy !== 0.5
            visible: corner || region.ratio <= 0
            width: 26
            height: 26
            x: box.x + box.width * hx - width / 2
            y: box.y + box.height * hy - height / 2
            Rectangle {
                anchors.centerIn: parent
                width: handle.corner ? 12 : (handle.hx === 0.5 ? 20 : 6)
                height: handle.corner ? 12 : (handle.hy === 0.5 ? 20 : 6)
                radius: 3
                color: region.tint
                border.color: region.ink
                border.width: 1
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: handle.corner ? (handle.hx === handle.hy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor)
                                           : handle.hx === 0.5 ? Qt.SizeVerCursor : Qt.SizeHorCursor
                onPressed: region.resizing = true
                onReleased: region.resizing = false
                onCanceled: region.resizing = false
                onPositionChanged: function(mouse) {
                    if (!pressed) return
                    var p = mapToItem(region, mouse.x, mouse.y)
                    var px = Math.max(0, Math.min(1, p.x / region.width))
                    var py = Math.max(0, Math.min(1, p.y / region.height))
                    var a = region.area
                    var x0 = a.x, y0 = a.y, x1 = a.x + a.width, y1 = a.y + a.height
                    if (handle.hx === 0) x0 = Math.min(px, x1 - region.minSize)
                    if (handle.hx === 1) x1 = Math.max(px, x0 + region.minSize)
                    if (handle.hy === 0) y0 = Math.min(py, y1 - region.minSize)
                    if (handle.hy === 1) y1 = Math.max(py, y0 + region.minSize)
                    if (region.ratio > 0 && handle.corner) {
                        // Keep the shape: height follows width, both limited by the picture.
                        var w = x1 - x0
                        var h = region.heightFor(w)
                        var room = handle.hy === 0 ? y1 : 1 - y0
                        if (h > room) { h = room; w = region.widthFor(h) }
                        if (handle.hx === 0) x0 = x1 - w; else x1 = x0 + w
                        if (handle.hy === 0) y0 = y1 - h; else y1 = y0 + h
                    }
                    region.moved(Qt.rect(x0, y0, x1 - x0, y1 - y0))
                }
            }
        }
    }
}
