import QtQuick

// Page thumbnails to pick from: click toggles a page, Shift+click a run.
Item {
    id: picker
    property var images: []
    property var selected: []          // 1-based page numbers
    property int lastClicked: 0
    signal selectionEdited(var pages)

    implicitHeight: Math.min(grid.contentHeight + 4, 640)

    function isSelected(page) { return selected.indexOf(page) >= 0 }
    function toggle(page, shift) {
        var next = selected.slice()
        if (shift && lastClicked > 0) {
            var on = !isSelected(page)
            for (var p = Math.min(lastClicked, page); p <= Math.max(lastClicked, page); p++) {
                var at = next.indexOf(p)
                if (on && at < 0) next.push(p)
                if (!on && at >= 0) next.splice(at, 1)
            }
        } else {
            var index = next.indexOf(page)
            if (index >= 0) next.splice(index, 1)
            else next.push(page)
        }
        lastClicked = page
        next.sort(function(a, b) { return a - b })
        selectionEdited(next)
    }

    GridView {
        id: grid
        anchors.fill: parent
        clip: true
        cellWidth: 146
        cellHeight: 206
        model: picker.images
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
            id: cell
            required property int index
            required property string modelData
            readonly property int page: index + 1
            readonly property bool chosen: picker.isSelected(page)
            width: grid.cellWidth
            height: grid.cellHeight
            Rectangle {
                objectName: "pickPage" + cell.page
                anchors.horizontalCenter: parent.horizontalCenter
                width: 134
                height: 194
                radius: 10
                color: cell.chosen ? Theme.accentWash : pickMouse.containsMouse ? Theme.card : Theme.field
                border.width: cell.chosen ? 2 : 1
                border.color: cell.chosen ? Theme.accent : pickMouse.containsMouse ? Theme.lineStrong : Theme.line
                Behavior on color { ColorAnimation { duration: Theme.fadeFast } }
                Image {
                    x: 10; y: 10
                    width: parent.width - 20
                    height: parent.height - 42
                    source: cell.modelData
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    opacity: cell.chosen ? 1 : 0.7
                }
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    width: 22; height: 22; radius: 11
                    color: cell.chosen ? Theme.accent : Theme.panel
                    border.width: cell.chosen ? 0 : 1.5
                    border.color: Theme.lineStrong
                    Text { anchors.centerIn: parent; visible: cell.chosen; text: "✓"; color: Theme.accentInk; font.pixelSize: 12; font.weight: Font.Bold }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 9
                    text: cell.page
                    color: cell.chosen ? Theme.accent : Theme.textMuted
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: pickMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) { picker.toggle(cell.page, mouse.modifiers & Qt.ShiftModifier) }
                }
            }
        }
    }
}
