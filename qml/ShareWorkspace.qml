import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Clips (7), Drop (8) and the link shortener (9) on the user's Tools server.
Item {
    id: page
    property int section: 7
    property url sourceUrl: ""
    property int resultSection: -1
    signal chooseFile()
    // A file dropped on the page, or "" to let go of the chosen one.
    signal fileDropped(url fileUrl)

    readonly property bool shortener: section === 9
    readonly property string fileName: sourceUrl.toString() ? decodeURIComponent(sourceUrl.toString().split("/").pop()) : ""
    readonly property real fileBytes: sourceUrl.toString() ? localTools.fileBytes(sourceUrl) : 0
    // Guest limits on the Tools server.
    readonly property real limitBytes: (section === 7 ? 200 : 50) * 1048576
    readonly property bool tooBig: !shortener && fileBytes > limitBytes
    readonly property string host: toolsClient.serverUrl.replace(/^https?:\/\//, "").replace(/\/+$/, "")
    readonly property bool showResult: resultSection === section && toolsClient.resultUrl.toString().length > 0 && !toolsClient.busy

    function sizeLabel(bytes) {
        return bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(bytes / 1024)) + " KB"
    }

    Rectangle { anchors.fill: parent; color: Theme.window }
    ScrollView {
        id: scroll
        readonly property SoftBounds softBounds: SoftBounds { flickable: scroll.contentItem }
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        Item {
            width: scroll.availableWidth
            implicitHeight: formColumn.implicitHeight + 95
        ColumnLayout {
            id: formColumn
            width: Math.min(scroll.availableWidth - 88, 760)
            x: Math.max(44, (scroll.availableWidth - width) / 2)
            y: 40
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 14
                    color: Theme.accentWash
                    border.color: Theme.accentEdge
                    ToolIcon {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        name: page.section === 7 ? "publish" : page.section === 8 ? "drop" : "link"
                        tint: Theme.accent
                    }
                }
                Column {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: page.section === 7 ? "Publish to Clips" : page.section === 8 ? "Share with Drop" : "Shorten a link"
                        color: Theme.text
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: page.section === 7 ? "Upload a clip to your Tools server and get a shareable link." : page.section === 8 ? "Send a file to your Tools server and share it with one link." : "Turn a long address into a short one on your Tools server."
                        color: Theme.textMuted
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // The server, with its state in a pill.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 8
                implicitHeight: serverRow.implicitHeight + 28
                radius: 14
                color: Theme.panel
                border.color: Theme.hover
                RowLayout {
                    id: serverRow
                    x: 16
                    y: 14
                    width: parent.width - 32
                    spacing: 10
                    Rectangle {
                        objectName: "serverState"
                        Layout.preferredHeight: 26
                        Layout.preferredWidth: stateRow.implicitWidth + 20
                        radius: 13
                        color: toolsClient.connected ? Theme.accentWash : Theme.field
                        border.color: toolsClient.connected ? Theme.accentEdge : Theme.line
                        Row {
                            id: stateRow
                            anchors.centerIn: parent
                            spacing: 7
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 7
                                height: 7
                                radius: 4
                                color: toolsClient.connected ? Theme.success : toolsClient.busy ? Theme.accent : Theme.textFaint
                                SequentialAnimation on opacity {
                                    running: toolsClient.connected
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                                }
                            }
                            Text {
                                text: toolsClient.connected ? "Connected" : "Not connected"
                                color: toolsClient.connected ? Theme.text : Theme.textMuted
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                    EditorField {
                        id: serverField
                        Layout.fillWidth: true
                        text: toolsClient.serverUrl
                        placeholderText: "https://tools.example.com"
                        onEditingFinished: toolsClient.serverUrl = text.trim()
                    }
                    EditorButton {
                        text: toolsClient.connected && serverField.text.trim() === toolsClient.serverUrl ? "Check" : "Connect"
                        enabled: !toolsClient.busy
                        onClicked: { toolsClient.serverUrl = serverField.text.trim(); toolsClient.testConnection() }
                    }
                }
            }

            // Clips and Drop: the file.
            DropZone {
                visible: !page.shortener && !page.sourceUrl.toString()
                Layout.fillWidth: true
                implicitHeight: 220
                active: pageDrop.containsDrag
                iconName: page.section === 7 ? "publish" : "drop"
                heading: page.section === 7 ? "Drop a clip to publish" : "Drop a file to share"
                formats: page.section === 7 ? "Videos up to 200 MB · kept for 24 h" : "Any file up to 50 MB · kept for 1 h"
                onBrowseRequested: page.chooseFile()
            }
            Rectangle {
                objectName: "shareFileCard"
                visible: !page.shortener && page.sourceUrl.toString().length > 0
                Layout.fillWidth: true
                implicitHeight: 64
                radius: 14
                color: pageDrop.containsDrag ? Theme.accentWash : Theme.panel
                border.color: pageDrop.containsDrag ? Theme.accent : page.tooBig ? Theme.danger : Theme.hover
                Behavior on color { ColorAnimation { duration: Theme.fade } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 12
                    Rectangle {
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 38
                        radius: 11
                        color: Theme.field
                        ToolIcon { anchors.centerIn: parent; name: "file"; tint: Theme.accent }
                    }
                    Column {
                        Layout.fillWidth: true
                        spacing: 3
                        Text {
                            width: parent.width
                            text: page.fileName
                            elide: Text.ElideMiddle
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: page.fileBytes > 0
                                  ? page.sizeLabel(page.fileBytes) + (page.tooBig ? " · over the " + page.sizeLabel(page.limitBytes) + " guest limit" : " of " + page.sizeLabel(page.limitBytes))
                                  : ""
                            color: page.tooBig ? Theme.danger : Theme.textMuted
                            font.pixelSize: 11
                        }
                    }
                    EditorButton { text: "Change"; subtle: true; onClicked: page.chooseFile() }
                    EditorButton { iconName: "close"; subtle: true; onClicked: page.fileDropped("") }
                }
            }

            // Shortener: the long link and how the short one will read.
            Rectangle {
                visible: page.shortener
                Layout.fillWidth: true
                implicitHeight: shortColumn.implicitHeight + 40
                radius: 14
                color: Theme.panel
                border.color: Theme.hover
                ColumnLayout {
                    id: shortColumn
                    x: 20
                    y: 20
                    width: parent.width - 40
                    spacing: 10
                    Text { text: "Long link"; color: Theme.textSoft; font.pixelSize: 12 }
                    EditorField {
                        id: targetField
                        objectName: "shortTarget"
                        Layout.fillWidth: true
                        implicitHeight: 46
                        font.pixelSize: 14
                        leftPadding: 38
                        placeholderText: "Paste a long https://… address"
                        ToolIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "link"; tint: Theme.textFaint }
                    }
                    Text { text: "Short link"; color: Theme.textSoft; font.pixelSize: 12; Layout.topMargin: 4 }
                    // The server's address with the slug typed right after it.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Rectangle {
                            Layout.preferredHeight: 39
                            Layout.preferredWidth: hostLabel.implicitWidth + 24
                            radius: 8
                            color: Theme.field
                            border.color: Theme.lineStrong
                            Text {
                                id: hostLabel
                                anchors.centerIn: parent
                                text: (page.host || "your-server") + "/"
                                color: Theme.textMuted
                                font.pixelSize: 12
                            }
                        }
                        EditorField {
                            id: slugField
                            objectName: "shortSlug"
                            Layout.fillWidth: true
                            Layout.leftMargin: -1
                            placeholderText: "random, or type your own"
                            validator: RegularExpressionValidator { regularExpression: /[A-Za-z0-9_-]{0,48}/ }
                        }
                    }
                }
            }

            RowLayout {
                spacing: 12
                EditorButton {
                    text: page.section === 7 ? "Upload to Clips" : page.section === 8 ? "Upload to Drop" : "Create short link"
                    iconName: page.shortener ? "link" : "publish"
                    primary: true
                    enabled: !toolsClient.busy && toolsClient.serverUrl.length > 0 && serverField.text.trim() === toolsClient.serverUrl
                             && (page.shortener ? targetField.text.trim().length > 0 : page.sourceUrl.toString().length > 0 && !page.tooBig)
                    onClicked: {
                        page.resultSection = page.section
                        if (page.section === 7) toolsClient.publishClip(page.sourceUrl)
                        else if (page.section === 8) toolsClient.publishDrop(page.sourceUrl)
                        else toolsClient.shorten(targetField.text.trim(), slugField.text.trim())
                    }
                }
                EditorButton { visible: toolsClient.busy; text: "Cancel"; danger: true; onClicked: toolsClient.cancel() }
                Text {
                    visible: !toolsClient.connected && !toolsClient.busy
                    text: "Connect to your server first"
                    color: Theme.textFaint
                    font.pixelSize: 11
                }
            }
            ColumnLayout {
                visible: toolsClient.busy
                Layout.fillWidth: true
                spacing: 6
                Text { text: toolsClient.stage + "  " + toolsClient.progress + "%"; color: Theme.textSoft; font.pixelSize: 12 }
                StudioProgress { value: toolsClient.progress / 100; Layout.fillWidth: true }
            }
            Text { visible: toolsClient.errorText.length > 0; text: toolsClient.errorText; color: Theme.danger; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }

            // The link, ready to copy.
            Rectangle {
                id: resultCard
                objectName: "shareResult"
                visible: page.showResult
                Layout.fillWidth: true
                implicitHeight: resultColumn.implicitHeight + 36
                radius: 14
                color: Theme.accentWash
                border.color: Theme.accentEdge
                property bool copied: false
                onVisibleChanged: if (visible) { copied = false; resultFireworks.play() }
                ColumnLayout {
                    id: resultColumn
                    x: 18
                    y: 18
                    width: parent.width - 36
                    spacing: 10
                    Text {
                        text: page.section === 7 ? "Your clip is live" : page.section === 8 ? "Your file is ready to share" : "Your short link is ready"
                        color: Theme.accent
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        TextEdit {
                            id: resultText
                            Layout.fillWidth: true
                            readOnly: true
                            selectByMouse: true
                            text: toolsClient.resultUrl.toString()
                            color: Theme.text
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.accentInk
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            wrapMode: TextEdit.WrapAnywhere
                        }
                        EditorButton {
                            objectName: "copyResult"
                            text: resultCard.copied ? "Copied" : "Copy"
                            primary: !resultCard.copied
                            onClicked: {
                                resultText.selectAll(); resultText.copy(); resultText.deselect()
                                resultCard.copied = true
                                copiedReset.restart()
                            }
                        }
                        EditorButton { iconName: "external"; text: "Open"; onClicked: Qt.openUrlExternally(toolsClient.resultUrl) }
                    }
                }
                Timer { id: copiedReset; interval: 1800; onTriggered: resultCard.copied = false }
                Fireworks { id: resultFireworks; anchors.fill: parent; bursts: 2 }
            }
        }
        }
    }

    DropArea {
        id: pageDrop
        anchors.fill: parent
        keys: ["text/uri-list"]
        enabled: !page.shortener && page.visible
        onEntered: function(drag) { if (drag.source) drag.accepted = false }
        onDropped: function(drop) {
            if (drop.hasUrls && drop.urls[0].toString().startsWith("file:")) page.fileDropped(drop.urls[0])
            drop.accept()
        }
    }
}
