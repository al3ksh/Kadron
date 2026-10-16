import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Compress: video or images, optionally to a target size.
ColumnLayout {
    id: compressPanel
    // The Tools page: section, sources, jobs and the dialogs it owns.
    required property var page
    property alias noAudioBox: compressNoAudio
    property alias targetField: compressTarget
    visible: page.section === 3 && page.hasSource
    Layout.fillWidth: true
    spacing: 10
    // Before and after: the file as it is, and what the settings aim for.
    Rectangle {
        objectName: "compressMeter"
        Layout.fillWidth: true
        Layout.maximumWidth: 560
        Layout.bottomMargin: 6
        implicitHeight: meterColumn.implicitHeight + 32
        radius: Theme.radius + 2
        color: Theme.field
        border.color: Theme.line
        ColumnLayout {
            id: meterColumn
            x: 18
            y: 16
            width: parent.width - 36
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
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
                }
                ToolIcon { name: "chevron"; rotation: -90; tint: Theme.textFaint; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "AIM"; color: Theme.textFaint; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                    Text {
                        text: page.compressToSize ? "≤ " + page.compressMB + " MB"
                            : "Quality " + page.compressQuality + " · " + page.qualityName(page.compressQuality)
                        color: Theme.accent
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                }
                // How much smaller the file should get.
                Rectangle {
                    visible: page.compressToSize && page.compressShare < 1
                    Layout.preferredWidth: savedLabel.implicitWidth + 20
                    Layout.preferredHeight: 26
                    radius: 13
                    color: Theme.accentWash
                    border.color: Theme.accentEdge
                    Text {
                        id: savedLabel
                        anchors.centerIn: parent
                        text: "−" + Math.round((1 - page.compressShare) * 100) + "%"
                        color: Theme.accent
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Theme.hover
                Rectangle {
                    width: parent.width * (page.compressToSize ? page.compressShare : page.compressQuality / 100)
                    height: parent.height
                    radius: 3
                    color: Theme.accent
                    Behavior on width { SmoothSpring {} }
                }
            }
            Text {
                visible: page.compressToSize && page.sourceBytes > 0 && page.compressShare >= 1
                text: "Already under " + page.compressMB + " MB, so it will stay about the same size."
                color: Theme.textMuted
                font.pixelSize: 11
            }
        }
    }

    Text { visible: !page.isImage; text: "Goal"; color: Theme.textMuted; font.pixelSize: 12 }
    SegmentedControl {
        visible: !page.isImage
        Layout.preferredWidth: 300
        namePrefix: "compressGoal_"
        options: [{ label: "Fit a size", value: "size" }, { label: "Keep quality", value: "quality" }]
        current: page.compressGoal
        onActivated: function(goal) { page.compressGoal = goal }
    }
    RowLayout {
        visible: page.compressGoal === "size" && !page.isImage
        spacing: 10
        SegmentedControl {
            Layout.preferredWidth: 340
            namePrefix: "compressSize_"
            options: [
                { label: "8 MB", value: 8, tip: "Discord without Nitro" },
                { label: "25 MB", value: 25, tip: "Most email attachments" },
                { label: "50 MB", value: 50, tip: "Discord Nitro Basic" },
                { label: "100 MB", value: 100 }
            ]
            current: page.compressMB
            onActivated: function(mb) { page.compressMB = mb; compressTarget.text = mb }
        }
        EditorField {
            id: compressTarget
            objectName: "compressTarget"
            text: "8"
            validator: DoubleValidator { bottom: 0.5 }
            Layout.preferredWidth: 72
            onTextEdited: if (Number(text) > 0) page.compressMB = Number(text)
        }
        Text { text: "MB"; color: Theme.textMuted; font.pixelSize: 12 }
    }
    RowLayout {
        visible: page.compressGoal === "quality" || page.isImage
        spacing: 14
        ToolSlider {
            objectName: "page.compressQuality"
            Layout.preferredWidth: 300
            from: 1
            to: 100
            stepSize: 1
            value: page.compressQuality
            onMoved: page.compressQuality = Math.round(value)
        }
        Text {
            text: page.compressQuality + " · " + page.qualityName(page.compressQuality)
            color: Theme.textSoft
            font.pixelSize: 12
        }
    }

    Text { text: "Format"; color: Theme.textMuted; font.pixelSize: 12; Layout.topMargin: 6 }
    SegmentedControl {
        Layout.preferredWidth: page.compressFormats.length * 76
        namePrefix: "compressFormat_"
        options: page.compressFormats.map(function(name) { return { label: name, value: name } })
        current: page.compressFormatName
        onActivated: function(name) { page.compressPick = name }
    }

    Text { text: "Resolution"; color: Theme.textMuted; font.pixelSize: 12; Layout.topMargin: 6 }
    SegmentedControl {
        Layout.preferredWidth: 340
        namePrefix: "compressWidth_"
        options: page.isImage
            ? [{ label: "Original", value: 0 }, { label: "2560 px", value: 2560 }, { label: "1920 px", value: 1920 }, { label: "1280 px", value: 1280 }]
            : [{ label: "Original", value: 0 }, { label: "1080p", value: 1920 }, { label: "720p", value: 1280 }, { label: "480p", value: 854 }]
        current: page.compressWidth
        onActivated: function(width) { page.compressWidth = width }
    }

    ToolCheck { id: compressNoAudio; visible: !page.isImage; text: "Remove audio"; Layout.topMargin: 4 }
    EditorButton {
        objectName: "compressButton"
        text: page.compressBatch.length > 1 ? "Compress " + page.compressBatch.length + " files…" : "Compress"
        iconName: "compress"
        primary: true
        enabled: page.sourceUrl.toString() && localTools.available && !localTools.busy && !page.compressRunning
        onClicked: {
            if (page.compressBatch.length < 2) { page.beginLocal("compress"); return }
            var first = page.compressBatch[0].toString()
            page.compressFolderPicker.currentFolder = first.substring(0, first.lastIndexOf("/"))
            page.compressFolderPicker.open()
        }
    }
    Text {
        Layout.fillWidth: true
        visible: page.compressBatch.length < 2 && !page.compressRunning
        text: "Tip: drop or pick several files to compress them all with these settings."
        color: Theme.textFaint
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
}
