pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kadron.Backend

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
                        text: compressPanel.page.sourceBytes > 0 ? compressPanel.page.sizeLabel(compressPanel.page.sourceBytes) : "—"
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
                        text: compressPanel.page.compressToSize ? "≤ " + compressPanel.page.compressMB + " MB"
                            : "Quality " + compressPanel.page.compressQuality + " · " + compressPanel.page.qualityName(compressPanel.page.compressQuality)
                        color: Theme.accent
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                }
                // How much smaller the file should get.
                Rectangle {
                    visible: compressPanel.page.compressToSize && compressPanel.page.compressShare < 1
                    Layout.preferredWidth: savedLabel.implicitWidth + 20
                    Layout.preferredHeight: 26
                    radius: 13
                    color: Theme.accentWash
                    border.color: Theme.accentEdge
                    Text {
                        id: savedLabel
                        anchors.centerIn: parent
                        text: "−" + Math.round((1 - compressPanel.page.compressShare) * 100) + "%"
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
                    width: parent.width * (compressPanel.page.compressToSize ? compressPanel.page.compressShare : compressPanel.page.compressQuality / 100)
                    height: parent.height
                    radius: 3
                    color: Theme.accent
                    Behavior on width { SmoothSpring {} }
                }
            }
            Text {
                visible: compressPanel.page.compressToSize && compressPanel.page.sourceBytes > 0 && compressPanel.page.compressShare >= 1
                text: "Already under " + compressPanel.page.compressMB + " MB, so it will stay about the same size."
                color: Theme.textMuted
                font.pixelSize: 11
            }
        }
    }

    Text { visible: !compressPanel.page.isImage; text: "Goal"; color: Theme.textMuted; font.pixelSize: 12 }
    SegmentedControl {
        visible: !compressPanel.page.isImage
        Layout.preferredWidth: 300
        namePrefix: "compressGoal_"
        options: [{ label: "Fit a size", value: "size" }, { label: "Keep quality", value: "quality" }]
        current: compressPanel.page.compressGoal
        onActivated: function(goal) { compressPanel.page.compressGoal = goal }
    }
    RowLayout {
        visible: compressPanel.page.compressGoal === "size" && !compressPanel.page.isImage
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
            current: compressPanel.page.compressMB
            onActivated: function(mb) { compressPanel.page.compressMB = mb; compressTarget.text = mb }
        }
        EditorField {
            id: compressTarget
            objectName: "compressTarget"
            text: "8"
            validator: DoubleValidator { bottom: 0.5 }
            Layout.preferredWidth: 72
            onTextEdited: if (Number(text) > 0) compressPanel.page.compressMB = Number(text)
        }
        Text { text: "MB"; color: Theme.textMuted; font.pixelSize: 12 }
    }
    RowLayout {
        visible: compressPanel.page.compressGoal === "quality" || compressPanel.page.isImage
        spacing: 14
        ToolSlider {
            objectName: "page.compressQuality"
            Layout.preferredWidth: 300
            from: 1
            to: 100
            stepSize: 1
            value: compressPanel.page.compressQuality
            onMoved: compressPanel.page.compressQuality = Math.round(value)
        }
        Text {
            text: compressPanel.page.compressQuality + " · " + compressPanel.page.qualityName(compressPanel.page.compressQuality)
            color: Theme.textSoft
            font.pixelSize: 12
        }
    }

    Text { text: "Format"; color: Theme.textMuted; font.pixelSize: 12; Layout.topMargin: 6 }
    SegmentedControl {
        Layout.preferredWidth: compressPanel.page.compressFormats.length * 76
        namePrefix: "compressFormat_"
        options: compressPanel.page.compressFormats.map(function(name) { return { label: name, value: name } })
        current: compressPanel.page.compressFormatName
        onActivated: function(name) { compressPanel.page.compressPick = name }
    }

    Text { text: "Resolution"; color: Theme.textMuted; font.pixelSize: 12; Layout.topMargin: 6 }
    SegmentedControl {
        Layout.preferredWidth: 340
        namePrefix: "compressWidth_"
        options: compressPanel.page.isImage
            ? [{ label: "Original", value: 0 }, { label: "2560 px", value: 2560 }, { label: "1920 px", value: 1920 }, { label: "1280 px", value: 1280 }]
            : [{ label: "Original", value: 0 }, { label: "1080p", value: 1920 }, { label: "720p", value: 1280 }, { label: "480p", value: 854 }]
        current: compressPanel.page.compressWidth
        onActivated: function(width) { compressPanel.page.compressWidth = width }
    }

    ToolCheck { id: compressNoAudio; visible: !compressPanel.page.isImage; text: "Remove audio"; Layout.topMargin: 4 }
    EditorButton {
        objectName: "compressButton"
        text: compressPanel.page.compressBatch.length > 1 ? "Compress " + compressPanel.page.compressBatch.length + " files…" : "Compress"
        iconName: "compress"
        primary: true
        enabled: compressPanel.page.sourceUrl.toString() && Core.localTools.available && !Core.localTools.busy && !compressPanel.page.compressRunning
        onClicked: {
            if (compressPanel.page.compressBatch.length < 2) { compressPanel.page.beginLocal("compress"); return }
            var first = compressPanel.page.compressBatch[0].toString()
            compressPanel.page.compressFolderPicker.currentFolder = first.substring(0, first.lastIndexOf("/"))
            compressPanel.page.compressFolderPicker.open()
        }
    }
    Text {
        Layout.fillWidth: true
        visible: compressPanel.page.compressBatch.length < 2 && !compressPanel.page.compressRunning
        text: "Tip: drop or pick several files to compress them all with these settings."
        color: Theme.textFaint
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
}
