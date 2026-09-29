import QtQuick
import QtQuick.Layouts

// Empty page of a tool with its own workspace, laid out like the tools in
// ToolsWorkspace: title, scope pill and a line of help above a card that
// holds the drop zone.
Item {
    id: empty
    property string title
    property string subtitle
    property alias iconName: zone.iconName
    property alias heading: zone.heading
    property alias formats: zone.formats
    property alias active: zone.active
    signal browseRequested()

    Rectangle {
        x: column.x + zone.x - 23
        y: column.y + zone.y - 12
        width: zone.width + 46
        height: zone.height + 46
        radius: 14
        color: Theme.panel
        border.color: Theme.hover
    }
    ColumnLayout {
        id: column
        width: Math.min(empty.width - 90, 760)
        x: Math.max(45, (empty.width - width) / 2)
        y: 35
        spacing: 15

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: empty.title
                color: Theme.text
                font.pixelSize: 28
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            Rectangle {
                Layout.preferredWidth: scopeLabel.implicitWidth + 22
                Layout.preferredHeight: 28
                radius: 14
                color: Theme.accentWash
                Text {
                    id: scopeLabel
                    anchors.centerIn: parent
                    text: "ON DEVICE"
                    color: Theme.accentSoft
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                }
            }
        }
        Text {
            Layout.fillWidth: true
            Layout.bottomMargin: 32
            text: empty.subtitle
            color: Theme.textMuted
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }
        DropZone {
            id: zone
            Layout.fillWidth: true
            onBrowseRequested: empty.browseRequested()
        }
    }
}
