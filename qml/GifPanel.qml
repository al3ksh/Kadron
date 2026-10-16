import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

// GIF Studio: a range on the filmstrip, the size meter and the finished GIF.
ColumnLayout {
    id: gifPanel
    // The Tools page: section, sources, jobs and the dialogs it owns.
    required property var page
    property alias startField: gifStart
    property alias durationField: gifDuration
    property alias video: gifVideo
    visible: page.section === 4 && page.hasSource
    Layout.fillWidth: true
    spacing: 12
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 280
        radius: 10
        color: Theme.canvas
        clip: true
        VideoOutput { id: gifVideo; anchors.fill: parent; visible: page.gifPlayer.hasVideo; fillMode: VideoOutput.PreserveAspectFit }
        AnimatedImage { anchors.fill: parent; visible: page.gifSourceIsGif; source: visible ? page.sourceUrl : ""; fillMode: Image.PreserveAspectFit }
        Rectangle {
            visible: page.gifPlayer.hasVideo
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 10
            width: loopLabel.implicitWidth + 30
            height: 24
            radius: 12
            color: Theme.chipScrim
            ToolIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 13; height: 13; name: "loop"; tint: page.gifLooping ? Theme.accent : Theme.textMuted }
            Text {
                id: loopLabel
                x: 25
                anchors.verticalCenter: parent.verticalCenter
                text: (page.gifLooping ? "Looping " : "Paused · ") + ((page.gifEndMs - page.gifStartMs) / 1000).toFixed(2) + " s"
                color: Theme.textSoft
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        EditorButton {
            iconName: page.gifPlayer.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
            enabled: page.gifPlayer.hasVideo
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: 29
            onClicked: {
                if (page.gifPlayer.playbackState === MediaPlayer.PlayingState) {
                    page.gifLooping = false
                    page.gifPlayer.pause()
                } else {
                    page.gifLooping = true
                    if (page.gifPlayer.position < page.gifStartMs || page.gifPlayer.position >= page.gifEndMs) page.gifPlayer.position = page.gifStartMs
                    page.gifPlayer.play()
                }
            }
        }
        RangeStrip {
            Layout.fillWidth: true
            frames: page.gifPlayer.duration > 0 && thumbnails.revision >= 0 ? thumbnails.framesFor(page.sourceUrl, page.gifPlayer.duration) : []
            durationMs: page.gifPlayer.duration
            startMs: page.gifStartMs
            endMs: page.gifEndMs
            positionMs: page.gifPlayer.position
            onRangeRequested: function(startMs, endMs) { page.setGifRange(startMs, endMs) }
            onSeekRequested: function(ms) { page.gifPlayer.position = ms }
        }
    }
    // The clip going in and the GIF coming out.
    Rectangle {
        objectName: "gifMeter"
        Layout.fillWidth: true
        implicitHeight: gifMeterRow.implicitHeight + 28
        radius: Theme.radius + 2
        color: Theme.field
        border.color: Theme.line
        RowLayout {
            id: gifMeterRow
            x: 18
            y: 14
            width: parent.width - 36
            spacing: 14
            Column {
                spacing: 2
                Text { text: "CLIP"; color: Theme.textFaint; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                Text {
                    text: ((page.gifEndMs - page.gifStartMs) / 1000).toFixed(2) + " s"
                    color: Theme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Text {
                    text: "from " + page.clockLabel(page.gifStartMs)
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.features: { "tnum": 1 }
                }
            }
            ToolIcon { name: "chevron"; rotation: -90; tint: Theme.textFaint; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
            Column {
                Layout.fillWidth: true
                spacing: 2
                Text { text: "GIF"; color: Theme.textFaint; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                Text {
                    objectName: "gifOutSize"
                    text: page.gifWidthPx + (page.gifHeightPx > 0 ? " × " + page.gifHeightPx : " px wide")
                    color: Theme.accent
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Text {
                    text: page.gifOutSec.toFixed(2) + " s · " + Math.round(page.gifOutSec * page.gifFps) + " frames"
                          + (page.gifExtras ? " · " + page.gifExtras : "")
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.features: { "tnum": 1 }
                }
            }
            Rectangle {
                Layout.preferredWidth: gifLimitText.implicitWidth + 20
                Layout.preferredHeight: 26
                radius: 13
                color: page.gifLimitMB > 0 ? Theme.accentWash : Theme.field
                border.color: page.gifLimitMB > 0 ? Theme.accentEdge : Theme.lineStrong
                Text {
                    id: gifLimitText
                    anchors.centerIn: parent
                    text: page.gifLimitMB > 0 ? "≤ " + page.gifLimitMB + " MB" : "No size limit"
                    color: page.gifLimitMB > 0 ? Theme.accent : Theme.textSoft
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    GridLayout {
        columns: 2
        columnSpacing: 28
        rowSpacing: 7
        Layout.fillWidth: true
        Layout.topMargin: 4
        Text { text: "Size"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; Layout.preferredWidth: 1 }
        Text { text: "Smoothness"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; Layout.preferredWidth: 1 }
        SegmentedControl {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            namePrefix: "gifWidth_"
            options: [
                { label: "320", value: 320, tip: "Chats and reactions" },
                { label: "480", value: 480, tip: "The usual GIF size" },
                { label: "720", value: 720, tip: "Sharp, but heavier" },
                { label: "1080", value: 1080, tip: "Full HD width; big files" }
            ]
            current: page.gifWidthPx
            onActivated: function(width) { page.gifWidthPx = width }
        }
        SegmentedControl {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            namePrefix: "gifFps_"
            options: [
                { label: "10 fps", value: 10, tip: "Light, the classic GIF look" },
                { label: "15 fps", value: 15, tip: "Smoother motion" },
                { label: "24 fps", value: 24, tip: "Film-smooth; about twice the size of 10 fps" }
            ]
            current: page.gifFps
            onActivated: function(fps) { page.gifFps = fps }
        }
        Text { text: "Size limit"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; Layout.preferredWidth: 1 }
        Item { Layout.fillWidth: true; Layout.preferredWidth: 1 }
        SegmentedControl {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            namePrefix: "gifLimit_"
            options: [
                { label: "None", value: 0 },
                { label: "2 MB", value: 2, tip: "Small enough for most chats" },
                { label: "5 MB", value: 5 },
                { label: "10 MB", value: 10, tip: "Discord's upload limit" }
            ]
            current: page.gifLimitMB
            onActivated: function(mb) { page.gifLimitMB = mb }
        }
        Text {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            text: page.gifLimitMB > 0 ? "Shrinks size and frame rate until it fits." : ""
            color: Theme.textFaint
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
    }

    // Speed, playback and exact times fold away.
    Item {
        objectName: "gifMoreToggle"
        Layout.fillWidth: true
        Layout.topMargin: 2
        implicitHeight: 30
        HoverHandler { id: gifMoreHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: Prefs.gifMoreOptions = !Prefs.gifMoreOptions }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            ToolIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron"
                width: 14
                height: 14
                tint: gifMoreHover.hovered ? Theme.text : Theme.textMuted
                rotation: Prefs.gifMoreOptions ? 0 : -90
                Behavior on rotation { SmoothSpring {} }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Prefs.gifMoreOptions ? "Fewer options" : "More options"
                color: gifMoreHover.hovered ? Theme.text : Theme.textMuted
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Prefs.gifMoreOptions ? "" : page.gifExtras || "speed, bounce, exact times"
                color: page.gifExtras ? Theme.accent : Theme.textFaint
                font.pixelSize: 12
            }
        }
    }

    Collapsible {
        open: Prefs.gifMoreOptions
        GridLayout {
            columns: 2
            columnSpacing: 28
            rowSpacing: 7
            Layout.fillWidth: true
            Text { text: "Speed"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; Layout.preferredWidth: 1 }
            Text { text: "Playback"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; Layout.preferredWidth: 1 }
            SegmentedControl {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                namePrefix: "gifSpeed_"
                options: [
                    { label: "0.5×", value: 0.5, tip: "Slow motion" },
                    { label: "1×", value: 1 },
                    { label: "1.5×", value: 1.5 },
                    { label: "2×", value: 2, glyph: "bolt", boltSize: 12 }
                ]
                current: page.gifSpeed
                onActivated: function(speed) { page.gifSpeed = speed }
            }
            SegmentedControl {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                namePrefix: "gifPlayback_"
                options: [
                    { label: "Loop", value: "loop", tip: "Plays forward, over and over" },
                    { label: "Bounce", value: "bounce", tip: "Forward, then backward, like a boomerang" },
                    { label: "Once", value: "once", tip: "Plays one time and stops on the last frame" }
                ]
                current: page.gifOnce ? "once" : page.gifBounce ? "bounce" : "loop"
                onActivated: function(mode) {
                    page.gifBounce = mode === "bounce"
                    page.gifOnce = mode === "once"
                }
            }
            Text { text: "Start (s)"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; Layout.preferredWidth: 1 }
            Text { text: "Length (s)"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true; Layout.preferredWidth: 1 }
            EditorField { id: gifStart; objectName: "gifStart"; text: "0"; validator: DoubleValidator { bottom: 0 }
                Layout.fillWidth: true; Layout.preferredWidth: 1 }
            EditorField { id: gifDuration; objectName: "gifDuration"; text: "8"; validator: DoubleValidator { bottom: 0.1 }
                Layout.fillWidth: true; Layout.preferredWidth: 1 }
        }
    }

    EditorButton {
        text: "Create GIF"
        iconName: "gif"
        primary: true
        Layout.topMargin: 6
        enabled: page.sourceUrl.toString() && localTools.available && !localTools.busy
        onClicked: page.beginLocal("gif")
    }
    Text { visible: page.resultSection === "gif" && localTools.outputUrl.toString().length > 0 && !localTools.busy; text: "Result preview · " + page.sizeLabel(localTools.outputBytes); color: Theme.textMuted; font.pixelSize: 12 }
    Rectangle {
        visible: page.resultSection === "gif" && localTools.outputUrl.toString().length > 0 && !localTools.busy
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 252 : 0
        radius: 10
        color: Theme.canvas
        clip: true
        AnimatedImage { anchors.fill: parent; source: parent.visible ? localTools.outputUrl : ""; fillMode: Image.PreserveAspectFit }
    }
}
