import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: page
    property int section: 7
    property url sourceUrl: ""
    property int resultSection: -1
    signal chooseFile()

    Rectangle { anchors.fill: parent; color: Theme.window }
    ScrollView {
        id: scroll
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

            Text {
                text: page.section === 7 ? "Publish to Clips" : page.section === 8 ? "Share with Drop" : "Shorten a link"
                color: Theme.text
                font.pixelSize: 28
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                Layout.bottomMargin: 15
                text: page.section === 7 ? "Upload a clip to your Tools server and get a shareable link." : page.section === 8 ? "Send a file to your Tools server and share it with one link." : "Create a short link on your Tools server."
                color: Theme.textMuted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: body.implicitHeight + 48
                radius: 14
                color: Theme.panel
                border.color: Theme.hover
                ColumnLayout {
                    id: body
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 24
                    spacing: 12
                    Text { text: "Tools server"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
                    RowLayout {
                        Layout.fillWidth: true
                        EditorField {
                            id: serverField
                            Layout.fillWidth: true
                            text: toolsClient.serverUrl
                            placeholderText: "https://tools.example.com"
                            onEditingFinished: toolsClient.serverUrl = text.trim()
                        }
                        EditorButton {
                            text: "Connect"
                            enabled: !toolsClient.busy
                            onClicked: { toolsClient.serverUrl = serverField.text.trim(); toolsClient.testConnection() }
                        }
                    }
                    Text {
                        text: toolsClient.connected ? "Connected" : "Enter your Tools server address, then connect"
                        color: toolsClient.connected ? Theme.success : Theme.textMuted
                        font.pixelSize: 11
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line; Layout.topMargin: 8; Layout.bottomMargin: 8 }
                    Text { visible: page.section !== 9; text: "File to share"; color: Theme.textSoft; font.pixelSize: 12 }
                    RowLayout {
                        visible: page.section !== 9
                        Layout.fillWidth: true
                        EditorField {
                            Layout.fillWidth: true
                            readOnly: true
                            text: page.sourceUrl.toString() ? decodeURIComponent(page.sourceUrl.toString().split("/").pop()) : ""
                            placeholderText: "Choose a file or export from the editor"
                        }
                        EditorButton { text: "Choose file"; onClicked: page.chooseFile() }
                    }
                    Text { visible: page.section === 7; text: "Guest Clips limit: 200 MB / 24 h"; color: Theme.textMuted; font.pixelSize: 11 }
                    Text { visible: page.section === 8; text: "Guest Drop limit: 50 MB / 1 h"; color: Theme.textMuted; font.pixelSize: 11 }
                    Text { visible: page.section === 9; text: "Destination URL"; color: Theme.textSoft; font.pixelSize: 12 }
                    EditorField { id: targetField; visible: page.section === 9; Layout.fillWidth: true; placeholderText: "https://..." }
                    EditorField { id: slugField; visible: page.section === 9; Layout.fillWidth: true; placeholderText: "Custom slug (optional)" }
                    EditorButton {
                        text: page.section === 7 ? "Upload to Clips" : page.section === 8 ? "Upload to Drop" : "Create short link"
                        primary: true
                        enabled: !toolsClient.busy && toolsClient.serverUrl.length > 0 && serverField.text.trim() === toolsClient.serverUrl && (page.section === 9 ? targetField.text.trim().length > 0 : page.sourceUrl.toString().length > 0)
                        onClicked: {
                            page.resultSection = page.section
                            if (page.section === 7) toolsClient.publishClip(page.sourceUrl)
                            else if (page.section === 8) toolsClient.publishDrop(page.sourceUrl)
                            else toolsClient.shorten(targetField.text.trim(), slugField.text.trim())
                        }
                    }
                    Text { visible: toolsClient.busy; text: toolsClient.stage + "  " + toolsClient.progress + "%"; color: Theme.textSoft; font.pixelSize: 12 }
                    StudioProgress { visible: toolsClient.busy; value: toolsClient.progress / 100; Layout.fillWidth: true }
                    EditorButton { visible: toolsClient.busy; text: "Cancel"; danger: true; onClicked: toolsClient.cancel() }
                    Text { visible: toolsClient.errorText.length > 0; text: toolsClient.errorText; color: Theme.danger; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    RowLayout {
                        visible: page.resultSection === page.section && toolsClient.resultUrl.toString().length > 0 && !toolsClient.busy
                        Layout.fillWidth: true
                        EditorField { id: resultField; Layout.fillWidth: true; readOnly: true; text: toolsClient.resultUrl.toString(); selectByMouse: true }
                        EditorButton { text: "Copy"; onClicked: { resultField.selectAll(); resultField.copy(); resultField.deselect() } }
                        EditorButton { text: "Open"; onClicked: Qt.openUrlExternally(toolsClient.resultUrl) }
                    }
                }
            }
        }
        }
    }
}
