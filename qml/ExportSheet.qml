import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kadron.Backend

// The editor's export options: a preset, loudness, only the part between
// markers, or a lossless cut. Choose file… asks Main for the save dialog.
StudioDialog {
    id: sheet
    required property var app
    signal chooseFile()
    property bool losslessCut: false
    // Only the part between the markers around the playhead, where it was
    // when the sheet opened.
    property bool onlyMarked: false
    property real openedAtMs: 0
    onAboutToShow: openedAtMs = sheet.app.sequencePositionMs
    readonly property var markedRange: sheet.app.markerRangeAt(openedAtMs)
    readonly property var range: onlyMarked ? markedRange : null
    readonly property real lengthMs: range ? range.endMs - range.startMs : Core.editorProject.sequenceDurationMs
    readonly property var presets: [
        ["source", "Source", "Original size and frame rate"],
        ["1080p60", "1080p60", "Full HD, up to 60 fps"],
        ["discord", "Discord", "Under 10 MB, 720p"],
        ["vertical", "Vertical", "1080×1920 for Shorts and Reels"]
    ]
    readonly property int discordKbps: Core.exporter.discordVideoKbps(lengthMs)
    heading: "Export MP4"
    message: ""
    iconName: "publish"
    width: 500
    body: [
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8
            enabled: !sheet.losslessCut
            opacity: enabled ? 1 : 0.45
            Repeater {
                model: sheet.presets
                delegate: Rectangle {
                    id: presetTile
                    required property var modelData
                    readonly property bool chosen: Prefs.exportPreset === modelData[0]
                    objectName: "preset_" + modelData[0]
                    Layout.fillWidth: true
                    implicitHeight: 58
                    radius: Theme.radius
                    color: chosen ? Theme.accentWash : tileMouse.containsMouse ? Theme.hover : Theme.field
                    border.color: chosen ? Theme.accentEdge : Theme.line
                    Behavior on color { ColorAnimation { duration: Theme.fadeFast } }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 2
                        Text { text: presetTile.modelData[1]; color: presetTile.chosen ? Theme.accent : Theme.text; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { width: parent.width; text: presetTile.modelData[2]; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: 11; elide: Text.ElideRight }
                    }
                    MouseArea { id: tileMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Prefs.exportPreset = presetTile.modelData[0] }
                }
            }
        },
        Text {
            Layout.fillWidth: true
            visible: Prefs.exportPreset === "discord" && !sheet.losslessCut
            text: sheet.discordKbps < 400 ? "Long for 10 MB: about " + sheet.discordKbps + " kbit/s, expect a soft picture."
                                                : "About " + sheet.discordKbps + " kbit/s for " + sheet.app.timecode(sheet.lengthMs) + "."
            color: sheet.discordKbps < 400 ? Theme.warning : Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        },
        ToolCheck {
            text: "Even out loudness (-16 LUFS)"
            enabled: !sheet.losslessCut
            checked: Prefs.exportLoudnorm
            onToggled: Prefs.exportLoudnorm = checked
        },
        ToolCheck {
            objectName: "exportOnlyMarked"
            visible: !!sheet.markedRange
            text: sheet.markedRange ? "Only " + sheet.app.timecode(sheet.markedRange.startMs) + " – " + sheet.app.timecode(sheet.markedRange.endMs)
                                            + ", between the markers around the playhead" : ""
            checked: sheet.onlyMarked
            onToggled: sheet.onlyMarked = checked
        },
        Text {
            Layout.fillWidth: true
            visible: Prefs.watermarkEnabled && Prefs.watermarkPath.length > 0 || Core.editorProject.markers.length > 0 || Core.exporter.busy
            text: [Core.exporter.busy ? "An export is running: this one waits in the queue." : "",
                   Prefs.watermarkEnabled && Prefs.watermarkPath.length > 0 ? (sheet.losslessCut && !Core.editorProject.mixed ? "The logo is skipped by a lossless cut." : "Your logo from Settings goes on.") : "",
                   Core.editorProject.markers.length > 0 ? "Markers become chapters in the file." : ""].filter(function(line) { return line.length > 0 }).join(" ")
            color: Theme.textFaint
            font.family: Theme.fontFamily
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        },
        ToolCheck {
            visible: !Core.editorProject.mixed
            text: "Fast lossless cut: no re-encode, starts at the nearest keyframe"
            checked: sheet.losslessCut
            onToggled: sheet.losslessCut = checked
        }
    ]
    EditorButton {
        text: Core.exporter.busy ? "Queue · choose file…" : "Choose file…"
        primary: true
        onClicked: { sheet.close(); sheet.chooseFile() }
    }
    EditorButton { text: "Cancel"; subtle: true; onClicked: sheet.close() }
}
