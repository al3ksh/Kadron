import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Kadron.Backend

// Audio: trim on the waveform and convert to another format.
ColumnLayout {
    id: audioPanel
    // The Tools page: section, sources, jobs and the dialogs it owns.
    required property var page
    property alias startField: audioStart
    property alias endField: audioEnd
    property alias volumeControl: audioVolume
    visible: page.section === 2 && page.hasSource
    Layout.fillWidth: true
    spacing: 12
    // Visual trimmer: the waveform with a draggable selection.
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        EditorButton {
            objectName: "audioPlayButton"
            iconName: page.audioPlayer.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
            enabled: page.audioPlayer.duration > 0
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: 50
            onClicked: page.toggleAudioPreview()
        }
        RangeStrip {
            id: audioStrip
            objectName: "audioStrip"
            Layout.fillWidth: true
            implicitHeight: 134
            waveLoading: page.audioPlayer.duration > 0 && waveform.length === 0
            waveform: page.audioPlayer.duration > 0 && Core.thumbnails.revision >= 0 ? Core.thumbnails.waveformFor(page.sourceUrl) : ""
            durationMs: page.audioPlayer.duration
            startMs: page.audioStartMs
            endMs: page.audioEndMs
            positionMs: page.audioPlayer.position
            onRangeRequested: function(startMs, endMs) { page.setAudioRange(startMs, endMs) }
            onSeekRequested: function(ms) { page.audioPlayer.position = ms }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        Text {
            text: page.audioPlayer.duration > 0
                  ? "Selection " + page.clockLabel(page.audioEndMs - page.audioStartMs) + " of " + page.clockLabel(page.audioPlayer.duration)
                  : page.audioPlayer.mediaStatus === MediaPlayer.InvalidMedia ? "This file cannot be previewed; the range fields still apply." : "Reading the file…"
            color: Theme.textSoft
            font.pixelSize: 12
            font.features: { "tnum": 1 }
        }
        Text { visible: Prefs.audioMoreOptions; text: "from"; color: Theme.textFaint; font.pixelSize: 12; Layout.leftMargin: 6 }
        EditorField { id: audioStart; objectName: "audioStart"; visible: Prefs.audioMoreOptions; text: "0"; validator: DoubleValidator { bottom: 0 }
            Layout.preferredWidth: 78 }
        Text { visible: Prefs.audioMoreOptions; text: "to"; color: Theme.textFaint; font.pixelSize: 12 }
        EditorField { id: audioEnd; objectName: "audioEnd"; visible: Prefs.audioMoreOptions; text: "0"; validator: DoubleValidator { bottom: 0 }
            Layout.preferredWidth: 78 }
        Text { visible: Prefs.audioMoreOptions; text: "s"; color: Theme.textFaint; font.pixelSize: 12 }
        Item { Layout.fillWidth: true }
        VolumeControl { id: audioVolume; objectName: "audioVolume" }
        ToolCheck { text: "Loop"; checked: page.audioLooping; onToggled: page.audioLooping = checked }
        EditorButton {
            text: "Whole file"
            subtle: true
            enabled: page.audioPlayer.duration > 0 && (page.audioStartMs > 0 || page.audioEndMs < page.audioPlayer.duration)
            onClicked: { audioStart.text = "0"; audioEnd.text = "0" }
        }
    }
    // What goes in and roughly what comes out.
    Rectangle {
        objectName: "audioMeter"
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: audioMeterRow.implicitHeight + 28
        radius: Theme.radius + 2
        color: Theme.field
        border.color: Theme.line
        RowLayout {
            id: audioMeterRow
            x: 18
            y: 14
            width: parent.width - 36
            spacing: 14
            Column {
                spacing: 2
                Text { text: "NOW"; color: Theme.textFaint; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                Text {
                    text: page.sourceBytes > 0 ? page.sizeLabel(page.sourceBytes) : "—"
                    color: Theme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                Text {
                    text: page.audioPlayer.duration > 0 ? page.clockLabel(page.audioPlayer.duration) : " "
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.features: { "tnum": 1 }
                }
            }
            ToolIcon { name: "chevron"; rotation: -90; tint: Theme.textFaint; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
            Column {
                Layout.fillWidth: true
                spacing: 2
                Text { text: "OUT"; color: Theme.textFaint; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                Text {
                    objectName: "audioEstimate"
                    text: page.audioEstimateBytes > 0 ? "≈ " + page.sizeLabel(page.audioEstimateBytes) : "—"
                    color: Theme.accent
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                Text {
                    text: page.audioSelectionSec > 0
                          ? page.clockLabel(page.audioSelectionSec * 1000) + " · " + page.audioFormatName.replace("m4a", "aac").toUpperCase()
                            + (page.audioLossless ? " lossless" : " " + page.audioKbps + " kbps") + (page.audioMono ? " · mono" : "")
                          : " "
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.features: { "tnum": 1 }
                }
            }
            // Smaller or bigger than the source, by how much.
            Rectangle {
                readonly property real change: page.sourceBytes > 0 && page.audioEstimateBytes > 0
                                               ? page.audioEstimateBytes / page.sourceBytes - 1 : 0
                visible: Math.abs(change) >= 0.05
                Layout.preferredWidth: audioChange.implicitWidth + 20
                Layout.preferredHeight: 26
                radius: 13
                color: change < 0 ? Theme.accentWash : Theme.field
                border.color: change < 0 ? Theme.accentEdge : Theme.lineStrong
                Text {
                    id: audioChange
                    anchors.centerIn: parent
                    text: (parent.change < 0 ? "−" : "+") + Math.round(Math.abs(parent.change) * 100) + "%"
                    color: parent.change < 0 ? Theme.accent : Theme.textSoft
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    GridLayout {
        columns: 2
        columnSpacing: 28
        Layout.fillWidth: true
        rowSpacing: 7
        Layout.topMargin: 4
        Text { text: "Format"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; Layout.preferredWidth: 1 }
        Text { text: page.audioLossless ? "Quality" : "Quality (kbps)"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; Layout.preferredWidth: 1 }
        SegmentedControl {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            namePrefix: "audioFormat_"
            options: [
                { label: "MP3", value: "mp3", tip: "Plays everywhere" },
                { label: "AAC", value: "m4a", tip: "Apple devices and phones; smaller than MP3 at the same quality" },
                { label: "Opus", value: "opus", tip: "Best quality for its size; web and voice" },
                { label: "WAV", value: "wav", tip: "Uncompressed, for further editing" },
                { label: "FLAC", value: "flac", tip: "Lossless and smaller than WAV" }
            ]
            current: page.audioFormatName
            onActivated: function(format) { page.audioFormatName = format }
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: 34
            SegmentedControl {
                visible: !page.audioLossless
                anchors.fill: parent
                namePrefix: "audioKbps_"
                options: [
                    { label: "96", value: 96, tip: "Voice and podcasts" },
                    { label: "128", value: 128, tip: "Good for music" },
                    { label: "192", value: 192, tip: "High quality" },
                    { label: "320", value: 320, tip: "The most MP3 can do" }
                ]
                current: page.audioKbps
                onActivated: function(kbps) { page.audioKbps = kbps }
            }
            Text {
                visible: page.audioLossless
                anchors.verticalCenter: parent.verticalCenter
                text: "Lossless · keeps every detail of the source"
                color: Theme.textSoft
                font.pixelSize: 12
            }
        }
    }

    // Everything past format and quality folds away.
    Item {
        objectName: "audioMoreToggle"
        Layout.fillWidth: true
        Layout.topMargin: 2
        implicitHeight: 30
        HoverHandler { id: audioMoreHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Prefs.audioMoreOptions = !Prefs.audioMoreOptions }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            ToolIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron"
                width: 14
                height: 14
                tint: audioMoreHover.hovered ? Theme.text : Theme.textMuted
                rotation: Prefs.audioMoreOptions ? 0 : -90
                Behavior on rotation { SmoothSpring {} }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Prefs.audioMoreOptions ? "Fewer options" : "More options"
                color: audioMoreHover.hovered ? Theme.text : Theme.textMuted
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Prefs.audioMoreOptions ? "" : page.audioExtras || "fades, loudness, channels, exact times"
                color: page.audioExtras ? Theme.accent : Theme.textFaint
                font.pixelSize: 12
            }
        }
    }

    Collapsible {
        open: Prefs.audioMoreOptions
        GridLayout {
            columns: 2
            columnSpacing: 28
            Layout.fillWidth: true
            rowSpacing: 7

            Text { text: "Fade in"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; Layout.preferredWidth: 1 }
            Text { text: "Fade out"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; Layout.preferredWidth: 1 }
            SegmentedControl {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                namePrefix: "audioFadeIn_"
                options: [{ label: "Off", value: 0 }, { label: "0.5 s", value: 0.5 }, { label: "1 s", value: 1 }, { label: "3 s", value: 3 }]
                current: page.audioFadeIn
                onActivated: function(sec) { page.audioFadeIn = sec }
            }
            SegmentedControl {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                namePrefix: "audioFadeOut_"
                options: [{ label: "Off", value: 0 }, { label: "0.5 s", value: 0.5 }, { label: "1 s", value: 1 }, { label: "3 s", value: 3 }]
                current: page.audioFadeOut
                onActivated: function(sec) { page.audioFadeOut = sec }
            }

            Text { text: "Loudness"; color: Theme.textMuted; font.pixelSize: 12; Layout.topMargin: 6; Layout.fillWidth: true; Layout.preferredWidth: 1 }
            Text { text: "Channels"; color: Theme.textMuted; font.pixelSize: 12; Layout.topMargin: 6; Layout.fillWidth: true; Layout.preferredWidth: 1 }
            SegmentedControl {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                namePrefix: "audioLufs_"
                options: [
                    { label: "As is", value: 0 },
                    { label: "Podcast", value: -16, tip: "−16 LUFS, the spoken-word standard" },
                    { label: "Music", value: -14, tip: "−14 LUFS, what Spotify and YouTube play at" },
                    { label: "Loud", value: -9, tip: "−9 LUFS, for clips that must cut through" }
                ]
                current: page.audioLufs
                onActivated: function(lufs) { page.audioLufs = lufs }
            }
            SegmentedControl {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                namePrefix: "audioChannels_"
                options: [{ label: "Stereo", value: false }, { label: "Mono", value: true, tip: "One channel; fine for voice" }]
                current: page.audioMono
                onActivated: function(mono) { page.audioMono = mono }
            }
        }
    }

    EditorButton {
        text: "Convert audio"
        iconName: "audio"
        primary: true
        Layout.topMargin: 6
        enabled: page.sourceUrl.toString() && Core.localTools.available && !Core.localTools.busy
        onClicked: page.beginLocal("audio")
    }
}
