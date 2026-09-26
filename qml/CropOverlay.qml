import QtQuick

// Crop frame over an image: drag inside to move it, drag a corner or an edge
// to resize it. With a fixed `ratio` (width / height in image pixels) only the
// corners resize and keep the shape. The rectangle is normalized to the image
// (0..1) and reported once the drag ends.
Item {
    id: overlay
    property var item: null          // cropX, cropY, cropW, cropH
    property real ratio: 0
    property size viewSize: Qt.size(1, 1)
    // Bumped by the page on every edit, so the frame follows undo-like resets.
    property int revision: 0
    signal committed(var crop)

    // The frame being shown: the item's crop, or the one under the pointer.
    property bool dragging: false
    property real x0: 0
    property real y0: 0
    property real x1: 1
    property real y1: 1
    function sync() {
        if (dragging || !item) return
        x0 = item.cropX; y0 = item.cropY
        x1 = item.cropX + item.cropW; y1 = item.cropY + item.cropH
    }
    onItemChanged: sync()
    onRevisionChanged: sync()
    Component.onCompleted: sync()

    readonly property real minSize: 0.04
    // Height in normalized units that keeps `ratio` for a normalized width.
    function heightFor(w) { return w * viewSize.width / (ratio * viewSize.height) }
    function widthFor(h) { return h * ratio * viewSize.height / viewSize.width }
    function commit() {
        dragging = false
        committed({ cropX: x0, cropY: y0, cropW: x1 - x0, cropH: y1 - y0 })
    }

    readonly property real cropLeft: x0 * width
    readonly property real cropTop: y0 * height
    readonly property real cropRight: x1 * width
    readonly property real cropBottom: y1 * height
    readonly property bool whole: x0 <= 0.0005 && y0 <= 0.0005 && x1 >= 0.9995 && y1 >= 0.9995

    // Shade outside the crop.
    Rectangle { x: 0; y: 0; width: overlay.width; height: overlay.cropTop; color: "#99000000" }
    Rectangle { x: 0; y: overlay.cropBottom; width: overlay.width; height: overlay.height - overlay.cropBottom; color: "#99000000" }
    Rectangle { x: 0; y: overlay.cropTop; width: overlay.cropLeft; height: overlay.cropBottom - overlay.cropTop; color: "#99000000" }
    Rectangle { x: overlay.cropRight; y: overlay.cropTop; width: overlay.width - overlay.cropRight; height: overlay.cropBottom - overlay.cropTop; color: "#99000000" }

    Rectangle {
        id: box
        x: overlay.cropLeft
        y: overlay.cropTop
        width: overlay.cropRight - overlay.cropLeft
        height: overlay.cropBottom - overlay.cropTop
        color: "transparent"
        border.width: 2
        border.color: overlay.whole && !overlay.dragging ? Qt.rgba(1, 1, 1, 0.35) : Theme.accent

        // Rule of thirds while the frame is in use.
        Repeater {
            model: 2
            delegate: Item {
                required property int index
                anchors.fill: parent
                visible: overlay.dragging
                Rectangle { x: box.width * (index + 1) / 3; width: 1; height: box.height; color: Qt.rgba(1, 1, 1, 0.45) }
                Rectangle { y: box.height * (index + 1) / 3; height: 1; width: box.width; color: Qt.rgba(1, 1, 1, 0.45) }
            }
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: 12
            cursorShape: overlay.whole ? Qt.ArrowCursor : Qt.SizeAllCursor
            enabled: !overlay.whole
            property real startX: 0
            property real startY: 0
            property var start: null
            onPressed: function(mouse) {
                var p = mapToItem(overlay, mouse.x, mouse.y)
                startX = p.x / overlay.width
                startY = p.y / overlay.height
                start = { x0: overlay.x0, y0: overlay.y0, x1: overlay.x1, y1: overlay.y1 }
                overlay.dragging = true
            }
            onPositionChanged: function(mouse) {
                if (!pressed) return
                var p = mapToItem(overlay, mouse.x, mouse.y)
                var w = start.x1 - start.x0, h = start.y1 - start.y0
                var nx = Math.max(0, Math.min(1 - w, start.x0 + p.x / overlay.width - startX))
                var ny = Math.max(0, Math.min(1 - h, start.y0 + p.y / overlay.height - startY))
                overlay.x0 = nx; overlay.x1 = nx + w
                overlay.y0 = ny; overlay.y1 = ny + h
            }
            onReleased: overlay.commit()
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
            visible: corner || overlay.ratio <= 0
            width: 28
            height: 28
            x: overlay.cropLeft + (overlay.cropRight - overlay.cropLeft) * hx - width / 2
            y: overlay.cropTop + (overlay.cropBottom - overlay.cropTop) * hy - height / 2
            Rectangle {
                anchors.centerIn: parent
                width: handle.corner ? 14 : (handle.hx === 0.5 ? 22 : 6)
                height: handle.corner ? 14 : (handle.hy === 0.5 ? 22 : 6)
                radius: 3
                color: Theme.accent
                border.color: Theme.accentInk
                border.width: 1
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: handle.corner ? (handle.hx === handle.hy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor)
                                           : handle.hx === 0.5 ? Qt.SizeVerCursor : Qt.SizeHorCursor
                onPressed: overlay.dragging = true
                onPositionChanged: function(mouse) {
                    if (!pressed) return
                    var p = mapToItem(overlay, mouse.x, mouse.y)
                    var px = Math.max(0, Math.min(1, p.x / overlay.width))
                    var py = Math.max(0, Math.min(1, p.y / overlay.height))
                    var x0 = overlay.x0, y0 = overlay.y0, x1 = overlay.x1, y1 = overlay.y1
                    if (handle.hx === 0) x0 = Math.min(px, x1 - overlay.minSize)
                    if (handle.hx === 1) x1 = Math.max(px, x0 + overlay.minSize)
                    if (handle.hy === 0) y0 = Math.min(py, y1 - overlay.minSize)
                    if (handle.hy === 1) y1 = Math.max(py, y0 + overlay.minSize)
                    if (overlay.ratio > 0 && handle.corner) {
                        // Keep the shape: height follows width, both limited by the image.
                        var w = x1 - x0
                        var h = overlay.heightFor(w)
                        var room = handle.hy === 0 ? y1 : 1 - y0
                        if (h > room) { h = room; w = overlay.widthFor(h) }
                        if (handle.hx === 0) x0 = x1 - w; else x1 = x0 + w
                        if (handle.hy === 0) y0 = y1 - h; else y1 = y0 + h
                    }
                    overlay.x0 = x0; overlay.y0 = y0; overlay.x1 = x1; overlay.y1 = y1
                }
                onReleased: overlay.commit()
            }
        }
    }
}
