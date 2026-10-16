import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kadron.Backend

// The editor's Publish inspector: connect a Tools server, send a file to
// Clips or Drop, or shorten a link. Choose file asks Main for its dialog.
ColumnLayout {
    id: panel
    // The file Clips and Drop would send.
    property url source
    signal chooseFile()

    spacing: 9
    Text { text: "Tools server"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
    EditorField {
        id: serverField
        Layout.fillWidth: true
        text: Core.toolsClient.serverUrl
        placeholderText: "https://tools.example.com"
        onEditingFinished: Core.toolsClient.serverUrl = text
    }
    RowLayout {
        Layout.fillWidth: true
        EditorButton { text: "Connect"; enabled: !Core.toolsClient.busy; onClicked: { Core.toolsClient.serverUrl = serverField.text; Core.toolsClient.testConnection() } }
        Text { text: Core.toolsClient.connected ? "Connected" : "Not connected"; color: Core.toolsClient.connected ? Theme.success : Theme.textMuted; font.pixelSize: 11; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
    }
    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.topMargin: 3 }
    Text { text: "Publish a file"; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
    Text {
        Layout.fillWidth: true
        text: panel.source.toString() ? panel.source.toString().split("/").pop() : "No file selected"
        color: Theme.textSoft
        elide: Text.ElideMiddle
        font.pixelSize: 11
    }
    EditorButton { text: "Choose file"; Layout.fillWidth: true; onClicked: panel.chooseFile() }
    RowLayout {
        Layout.fillWidth: true
        EditorButton { text: "To Clips"; Layout.fillWidth: true; enabled: !Core.toolsClient.busy && panel.source.toString().length > 0; onClicked: Core.toolsClient.publishClip(panel.source) }
        EditorButton { text: "To Drop"; Layout.fillWidth: true; enabled: !Core.toolsClient.busy && panel.source.toString().length > 0; onClicked: Core.toolsClient.publishDrop(panel.source) }
    }
    Text { text: "Guest: Clips 200 MB / 24 h, Drop 50 MB / 1 h"; color: Theme.textMuted; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.topMargin: 3 }
    Text { text: "Shorten a link"; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
    EditorField { id: targetField; Layout.fillWidth: true; placeholderText: "https://..." }
    RowLayout {
        Layout.fillWidth: true
        EditorField { id: slugField; Layout.fillWidth: true; placeholderText: "Custom slug (optional)" }
        EditorButton { text: "Create"; enabled: !Core.toolsClient.busy; onClicked: Core.toolsClient.shorten(targetField.text, slugField.text) }
    }
    Text {
        visible: Core.toolsClient.busy
        text: Core.toolsClient.stage + "  " + Core.toolsClient.progress + "%"
        color: Theme.textSoft
        font.pixelSize: 11
    }
    StudioProgress { visible: Core.toolsClient.busy; value: Core.toolsClient.progress / 100; Layout.fillWidth: true }
    Text {
        Layout.fillWidth: true
        visible: Core.toolsClient.errorText.length > 0
        text: Core.toolsClient.errorText
        wrapMode: Text.WordWrap
        color: Theme.danger
        font.pixelSize: 11
    }
    RowLayout {
        Layout.fillWidth: true
        visible: Core.toolsClient.resultUrl.toString().length > 0
        EditorField {
            id: resultField
            Layout.fillWidth: true
            readOnly: true
            text: Core.toolsClient.resultUrl.toString()
            selectByMouse: true
        }
        EditorButton {
            text: "Copy"
            onClicked: { resultField.selectAll(); resultField.copy(); resultField.deselect() }
        }
    }
    EditorButton { text: "Cancel upload"; visible: Core.toolsClient.busy; danger: true; onClicked: Core.toolsClient.cancel() }
}
