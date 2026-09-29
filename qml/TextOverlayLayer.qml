import QtQuick

// Texts over a picture, laid out like TextOverlay::filter draws them: x and y
// place each text's centre, size is a share of the picture's height. With
// editable set, a text can be picked and dragged; the move is reported once,
// on release, so a drag is one undo step.
Item {
    id: overlay
    property var texts: []
    property real timeMs: 0
    property int selectedIndex: -1
    property bool editable: true
    // A size the style editor is dragging for the selected text, or -1.
    property real draftSize: -1
    signal picked(int index)
    signal moved(int index, real x, real y)

    clip: true

    function family(font) {
        return font === "impact" ? "Impact" : font === "black" ? "Arial Black" : font === "serif" ? "Georgia"
             : font === "mono" ? "Consolas" : "Segoe UI"
    }

    Repeater {
        model: overlay.texts
        delegate: Item {
            id: caption
            required property var modelData
            required property int index
            readonly property bool selected: index === overlay.selectedIndex
            readonly property real share: selected && overlay.draftSize > 0 ? overlay.draftSize : modelData.size
            readonly property real fontPx: Math.max(4, overlay.height * share)
            readonly property real centreX: mouse.dragging ? mouse.draftX : modelData.x
            readonly property real centreY: mouse.dragging ? mouse.draftY : modelData.y
            readonly property real pad: modelData.style === "box" ? fontPx * 0.3 : 0

            visible: overlay.timeMs >= modelData.startMs && overlay.timeMs < modelData.endMs
            width: label.implicitWidth
            height: label.implicitHeight
            x: Math.max(0, Math.min(overlay.width * centreX - width / 2, Math.max(0, overlay.width - width)))
            y: Math.max(0, Math.min(overlay.height * centreY - height / 2, Math.max(0, overlay.height - height)))

            Rectangle {
                visible: caption.modelData.style === "box"
                x: -caption.pad
                y: -caption.pad
                width: caption.width + caption.pad * 2
                height: caption.height + caption.pad * 2
                color: "#99000000"
            }
            Text {
                visible: caption.modelData.style === "shadow"
                x: Math.max(1, caption.fontPx / 18)
                y: x
                text: label.text
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                color: "#b3000000"
                font: label.font
                lineHeight: 1.0
            }
            Text {
                id: label
                text: caption.modelData.text
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                color: caption.modelData.color
                style: caption.modelData.style === "outline" ? Text.Outline : Text.Normal
                styleColor: "#99000000"
                font.family: overlay.family(caption.modelData.font)
                font.weight: caption.modelData.font === "impact" || caption.modelData.font === "black" ? Font.Normal : Font.Bold
                font.pixelSize: caption.fontPx
                lineHeight: 1.0
            }
            Rectangle {
                visible: overlay.editable && (caption.selected || mouse.containsMouse)
                x: -caption.pad - 4
                y: -caption.pad - 4
                width: caption.width + caption.pad * 2 + 8
                height: caption.height + caption.pad * 2 + 8
                radius: 4
                color: "transparent"
                border.width: caption.selected ? 2 : 1
                border.color: caption.selected ? Theme.accent : "#aaffffff"
            }
            MouseArea {
                id: mouse
                property bool dragging: false
                property real draftX: 0
                property real draftY: 0
                property point pressAt
                anchors.fill: parent
                anchors.margins: -caption.pad - 4
                enabled: overlay.editable
                hoverEnabled: true
                // The Reframe panel scrolls; its Flickable would take the drag.
                preventStealing: true
                cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: function(event) {
                    pressAt = mapToItem(overlay, event.x, event.y)
                    draftX = caption.modelData.x
                    draftY = caption.modelData.y
                    overlay.picked(caption.index)
                }
                onPositionChanged: function(event) {
                    if (!pressed) return
                    const at = mapToItem(overlay, event.x, event.y)
                    if (!dragging && Math.abs(at.x - pressAt.x) + Math.abs(at.y - pressAt.y) < 4) return
                    dragging = true
                    let nx = caption.modelData.x + (at.x - pressAt.x) / Math.max(1, overlay.width)
                    const ny = caption.modelData.y + (at.y - pressAt.y) / Math.max(1, overlay.height)
                    // Settles on the middle, where titles usually go.
                    if (Math.abs(nx - 0.5) < 0.015) nx = 0.5
                    draftX = Math.max(0, Math.min(1, nx))
                    draftY = Math.max(0, Math.min(1, ny))
                }
                onReleased: {
                    const wasDragged = dragging
                    dragging = false
                    // The model is rebuilt by the move, so this goes last.
                    if (wasDragged) overlay.moved(caption.index, draftX, draftY)
                }
                onCanceled: dragging = false
            }
        }
    }
}
