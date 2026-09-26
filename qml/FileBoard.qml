import QtQuick
import QtQuick.Controls

// Cards for a list of files, in order: drag a card to reorder, hover for
// remove, and a trailing tile adds more. Merge shows each PDF's first page and
// page count (from `covers`); Images to PDF shows the images themselves.
Item {
    id: board
    property var files: []
    property bool images: false
    property var covers: ({})
    property string addLabel: images ? "Add images" : "Add PDFs"
    signal reordered(var files)
    signal removeRequested(int index)
    signal addRequested()

    implicitHeight: grid.contentHeight + 4

    function fileName(url) { return decodeURIComponent(url.toString().split("/").pop()) }

    ListModel { id: cards }
    onFilesChanged: {
        cards.clear()
        for (var i = 0; i < files.length; i++) cards.append({ url: files[i].toString() })
        cards.append({ url: "" })   // the Add tile
    }
    function commitOrder() {
        var next = []
        for (var i = 0; i < cards.count; i++) if (cards.get(i).url) next.push(cards.get(i).url)
        board.reordered(next)
    }

    GridView {
        id: grid
        anchors.fill: parent
        interactive: false
        cellWidth: 168
        cellHeight: 236
        model: cards
        displaced: Transition { SmoothSpring { properties: "x,y" } }
        delegate: DropArea {
            id: slot
            required property int index
            required property string url
            readonly property bool isAdd: url.length === 0
            readonly property var cover: board.covers[url] || ({})
            width: grid.cellWidth
            height: grid.cellHeight
            keys: ["kadron-file-card"]
            onEntered: function(drag) {
                if (!slot.isAdd && drag.source && drag.source.visualIndex !== slot.index)
                    cards.move(drag.source.visualIndex, slot.index, 1)
            }

            // Add tile.
            Rectangle {
                visible: slot.isAdd
                objectName: "fileBoardAdd"
                width: 154
                height: 222
                radius: 10
                color: addMouse.containsMouse ? Theme.accentWash : "transparent"
                border.width: 1.5
                border.color: addMouse.containsMouse ? Theme.accentEdge : Theme.lineStrong
                Behavior on color { ColorAnimation { duration: Theme.fadeFast } }
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 44; height: 44; radius: 22
                        color: Theme.card
                        ToolIcon { anchors.centerIn: parent; width: 22; height: 22; name: "plus"; tint: addMouse.containsMouse ? Theme.accent : Theme.textMuted }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: board.addLabel; color: addMouse.containsMouse ? Theme.accent : Theme.textSoft; font.pixelSize: 12; font.weight: Font.DemiBold }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "or drop them here"; color: Theme.textFaint; font.pixelSize: 10 }
                }
                MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: board.addRequested() }
            }

            Rectangle {
                id: card
                visible: !slot.isAdd
                readonly property int visualIndex: slot.index
                readonly property bool dragging: cardMouse.drag.active
                width: 154
                height: 222
                anchors.horizontalCenter: dragging ? undefined : parent.horizontalCenter
                anchors.top: dragging ? undefined : parent.top
                radius: 10
                color: cardMouse.containsMouse ? Theme.card : Theme.field
                border.width: 1
                border.color: dragging ? Theme.accent : Theme.line
                scale: dragging ? 1.05 : 1
                z: dragging ? 10 : 1
                Behavior on scale { SnapSpring {} }
                Drag.active: dragging
                Drag.source: card
                Drag.keys: ["kadron-file-card"]
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2
                states: State {
                    when: card.dragging
                    ParentChange { target: card; parent: grid }
                }

                Rectangle {
                    id: preview
                    x: 10; y: 10
                    width: parent.width - 20
                    height: 150
                    radius: 6
                    color: Theme.canvas
                    clip: true
                    Image {
                        anchors.fill: parent
                        anchors.margins: board.images ? 0 : 8
                        source: board.images ? slot.url : (slot.cover.image || "")
                        sourceSize.width: 280
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    SkeletonBlock { anchors.fill: parent; visible: !board.images && !slot.cover.image && !slot.cover.error }
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 16
                        visible: !!slot.cover.error
                        text: slot.cover.error || ""
                        color: Theme.danger
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 4
                    width: orderLabel.implicitWidth + 14
                    height: 20
                    radius: 10
                    color: Theme.accent
                    Text { id: orderLabel; anchors.centerIn: parent; text: slot.index + 1; color: Theme.accentInk; font.pixelSize: 11; font.weight: Font.Bold }
                }
                Text {
                    x: 10
                    y: preview.y + preview.height + 10
                    width: parent.width - 20
                    text: board.fileName(slot.url)
                    color: Theme.text
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideMiddle
                }
                Text {
                    x: 10
                    y: preview.y + preview.height + 30
                    text: board.images ? "Page " + (slot.index + 1) : slot.cover.pages ? slot.cover.pages + (slot.cover.pages === 1 ? " page" : " pages") : "…"
                    color: Theme.textMuted
                    font.pixelSize: 11
                }
                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    drag.target: card
                    cursorShape: card.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    onReleased: { card.Drag.drop(); board.commitOrder() }
                }
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 6
                    width: 26; height: 26; radius: 13
                    visible: cardMouse.containsMouse || removeMouse.containsMouse
                    color: removeMouse.containsMouse ? Theme.dangerStrong : Theme.chipScrim
                    ToolIcon { anchors.centerIn: parent; width: 14; height: 14; name: "close"; tint: removeMouse.containsMouse ? Theme.panel : "#f1f4ef" }
                    MouseArea { id: removeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: board.removeRequested(slot.index) }
                }
            }
        }
    }
}
