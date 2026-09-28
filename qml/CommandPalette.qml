import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Ctrl+P: type to find any page, action or recent file and run it with Enter.
// Each command is { title, group, keys, enabled, run }; entries without run
// only document a shortcut.
Popup {
    id: palette
    property var commands: []
    property var source: function() { return [] }
    readonly property var matches: {
        var query = search.text.trim().toLowerCase()
        if (!query) return commands
        var words = query.split(/\s+/)
        return commands.filter(function(command) {
            var haystack = (command.title + " " + command.group + " " + (command.keys || "")).toLowerCase()
            return words.every(function(word) { return haystack.indexOf(word) >= 0 })
        })
    }

    function show() {
        commands = source()
        search.text = ""
        list.currentIndex = 0
        open()
    }
    function runCurrent() {
        var command = matches[list.currentIndex]
        if (!command || !command.run || command.enabled === false) return
        close()
        command.run()
    }
    function move(step) {
        if (matches.length === 0) return
        list.currentIndex = (list.currentIndex + step + matches.length) % matches.length
        list.positionViewAtIndex(list.currentIndex, ListView.Contain)
    }

    modal: true
    focus: true
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round(parent.height * 0.14) : 0
    width: Math.min(560, parent ? parent.width - 48 : 560)
    height: Math.min(440, contentColumn.implicitHeight + 16)
    padding: 8
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: search.forceActiveFocus()

    Overlay.modal: Rectangle { color: Theme.scrim }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.fade; easing.type: Easing.OutCubic }
            SnapSpring { property: "scale"; from: 0.96; to: 1 }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.fadeFast } }
    background: Rectangle {
        color: Theme.card
        radius: Theme.radiusLarge
        border.color: Theme.lineStrong
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 6

        EditorField {
            id: search
            objectName: "paletteSearch"
            Layout.fillWidth: true
            placeholderText: "Type a command, page or file…"
            onTextChanged: list.currentIndex = 0
            Keys.onUpPressed: palette.move(-1)
            Keys.onDownPressed: palette.move(1)
            Keys.onReturnPressed: palette.runCurrent()
            Keys.onEnterPressed: palette.runCurrent()
        }

        ListView {
            id: list
            objectName: "paletteList"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 360)
            clip: true
            model: palette.matches
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            ScrollBar.vertical: ScrollBar { policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool runnable: !!modelData.run && modelData.enabled !== false
                width: ListView.view.width
                height: 34
                radius: Theme.radius
                color: ListView.isCurrentItem ? Theme.hover : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10
                    Text {
                        text: row.modelData.title
                        color: row.runnable ? Theme.text : Theme.textDisabled
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                    Text {
                        text: row.modelData.group
                        color: Theme.textFaint
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    Rectangle {
                        visible: !!row.modelData.keys
                        implicitWidth: keysLabel.implicitWidth + 12
                        implicitHeight: 20
                        radius: Theme.radiusSmall
                        color: Theme.field
                        border.color: Theme.line
                        Text {
                            id: keysLabel
                            anchors.centerIn: parent
                            text: row.modelData.keys || ""
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: row.runnable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onEntered: list.currentIndex = row.index
                    onClicked: palette.runCurrent()
                }
            }
        }

        Text {
            visible: palette.matches.length === 0
            text: "Nothing matches"
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 12
            Layout.margins: 10
        }
    }
}
