pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtMultimedia
import Kadron.Backend

// The editor's monitor: the video with the clip's turn, crop and colour
// applied, captions and the crop frame over it, and the start screen with
// recent files when nothing is open. Main moves it into a full-window host
// for fullscreen.
Rectangle {
    id: pane
    required property var app
    required property MediaPlayer mediaPlayer
    // The caption size while the inspector's slider is dragged; -1 otherwise.
    property real captionDraftSize: -1
    readonly property alias videoOutput: videoOutput
    signal importMedia()

    // Starts typing in caption `index` on the video.
    function editCaption(index) { captionLayer.edit(index) }

    color: pane.app.previewFullscreen ? "black" : Theme.canvas
    DropArea {
        id: previewDropArea
        anchors.fill: parent
        z: 2
        onDropped: function(drop) {
            if (drop.urls.length > 0) pane.app.requestOpen(drop.urls[0], false)
        }
    }
    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        anchors.margins: 20
        visible: pane.mediaPlayer.hasVideo
        fillMode: VideoOutput.PreserveAspectFit
        TapHandler { onDoubleTapped: pane.app.previewFullscreen = !pane.app.previewFullscreen }
    }
    // A clip with a turn, crop or colour change is previewed through
    // this: the shown part of the frame, scaled to fit and turned.
    Item {
        id: lookFrame
        readonly property rect content: videoOutput.contentRect
        readonly property var crop: pane.app.lookSourceCrop
        readonly property bool turned: pane.app.clipLook.rotation % 180 !== 0
        readonly property real partWidth: Math.max(1, crop.w * content.width)
        readonly property real partHeight: Math.max(1, crop.h * content.height)
        readonly property real shownWidth: turned ? partHeight : partWidth
        readonly property real shownHeight: turned ? partWidth : partHeight
        readonly property real fit: Math.min(videoOutput.width / shownWidth, videoOutput.height / shownHeight)
        // Where the picture sits in the pane; captions and the crop frame follow it.
        readonly property rect frame: pane.app.lookActive
            ? Qt.rect(videoOutput.x + (videoOutput.width - shownWidth * fit) / 2, videoOutput.y + (videoOutput.height - shownHeight * fit) / 2, shownWidth * fit, shownHeight * fit)
            : Qt.rect(videoOutput.x + content.x, videoOutput.y + content.y, content.width, content.height)
        anchors.fill: parent
        visible: pane.app.lookActive
        ShaderEffectSource {
            id: lookSource
            sourceItem: videoOutput
            hideSource: pane.app.lookActive
            live: true
            visible: false
            sourceRect: Qt.rect(lookFrame.content.x + lookFrame.crop.u * lookFrame.content.width, lookFrame.content.y + lookFrame.crop.v * lookFrame.content.height,
                                lookFrame.partWidth, lookFrame.partHeight)
        }
        MultiEffect {
            objectName: "lookPreview"
            source: lookSource
            width: lookFrame.partWidth * lookFrame.fit
            height: lookFrame.partHeight * lookFrame.fit
            x: lookFrame.frame.x + (lookFrame.frame.width - width) / 2
            y: lookFrame.frame.y + (lookFrame.frame.height - height) / 2
            rotation: pane.app.clipLook.rotation
            brightness: pane.app.clipLook.brightness * 0.25
            contrast: pane.app.clipLook.contrast * 0.6
            saturation: pane.app.clipLook.saturation
        }
    }
    Rectangle {
        objectName: "transitionDim"
        visible: pane.mediaPlayer.hasVideo && pane.app.transitionDim > 0
        x: lookFrame.frame.x
        y: lookFrame.frame.y
        width: lookFrame.frame.width
        height: lookFrame.frame.height
        color: "black"
        opacity: pane.app.transitionDim
    }
    // Captions, laid out like the export draws them; drag one to place it.
    TextOverlayLayer {
        id: captionLayer
        objectName: "captionLayer"
        visible: pane.mediaPlayer.hasVideo && !pane.app.cropEditing
        x: lookFrame.frame.x
        y: lookFrame.frame.y
        width: lookFrame.frame.width
        height: lookFrame.frame.height
        texts: Core.editorProject.textItems
        timeMs: pane.app.sequencePositionMs
        selectedIndex: Core.editorProject.activeTextIndex
        draftSize: pane.captionDraftSize
        editable: !Core.exporter.busy
        onPicked: function(index) { Core.editorProject.selectText(index) }
        onMoved: function(index, x, y) { Core.editorProject.setTextStyle(index, { x: x, y: y }) }
        onEdited: function(index, text) { Core.editorProject.setTextContent(index, text) }
    }
    // Crop frame over the whole turned picture while cropping.
    CropOverlay {
        objectName: "clipCropOverlay"
        visible: pane.app.cropEditing && pane.mediaPlayer.hasVideo
        x: lookFrame.frame.x
        y: lookFrame.frame.y
        width: lookFrame.frame.width
        height: lookFrame.frame.height
        item: pane.app.activeClip ? { cropX: pane.app.clipLook.x, cropY: pane.app.clipLook.y, cropW: pane.app.clipLook.w, cropH: pane.app.clipLook.h } : null
        viewSize: Qt.size(Math.max(1, lookFrame.frame.width), Math.max(1, lookFrame.frame.height))
        revision: pane.app.cropRevision
        onCommitted: function(crop) {
            Core.editorProject.setClipCrop(Core.editorProject.activeClipIndex, crop.cropX, crop.cropY, crop.cropW, crop.cropH)
            pane.app.cropRevision++
        }
    }
    Column {
        anchors.centerIn: parent
        spacing: 13
        visible: !Core.editorProject.hasMedia || !pane.mediaPlayer.hasVideo
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !Core.editorProject.hasMedia ? "Your next edit starts here" : pane.mediaPlayer.hasVideo ? Core.editorProject.mediaName : "Audio clip"
            color: Theme.text
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Core.editorProject.hasMedia && !pane.mediaPlayer.hasVideo
            text: Core.editorProject.mediaName
            color: Theme.textMuted
            font.pixelSize: 12
        }
        EditorButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !Core.editorProject.hasMedia
            text: "Import media"
            primary: true
            onClicked: pane.importMedia()
        }
        // Recent projects and media, one click to pick up where you left off.
        Column {
            objectName: "recentList"
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !Core.editorProject.hasMedia && pane.app.recentFiles.length > 0
            width: 340
            spacing: 2
            topPadding: 14
            Text {
                text: "RECENT"
                color: Theme.textFaint
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
                leftPadding: 10
                bottomPadding: 4
            }
            Repeater {
                model: pane.app.recentFiles.slice(0, 5)
                delegate: Rectangle {
                    id: recentRow
                    required property var modelData
                    required property int index
                    readonly property string path: decodeURIComponent(modelData.url.replace(/^file:\/\/\//, ""))
                    objectName: "recentFile" + index
                    width: parent.width
                    height: 34
                    radius: Theme.radiusSmall
                    color: recentMouse.containsMouse ? Theme.hover : Theme.hoverClear
                    ToolIcon {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: recentRow.modelData.project ? "edit" : "file"
                        tint: recentMouse.containsMouse ? Theme.accent : Theme.textMuted
                    }
                    Text {
                        x: 38
                        width: parent.width - 48
                        anchors.verticalCenter: parent.verticalCenter
                        text: recentRow.path.replace(/^.*\//, "")
                        color: recentMouse.containsMouse ? Theme.text : Theme.textSoft
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }
                    MouseArea {
                        id: recentMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pane.app.requestOpen(recentRow.modelData.url, recentRow.modelData.project)
                    }
                    ToolTip.visible: recentMouse.containsMouse
                    ToolTip.delay: 700
                    ToolTip.text: recentRow.path
                }
            }
        }
    }
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 16
        text: pane.app.playerError
        color: Theme.danger
        font.pixelSize: 12
        visible: pane.app.playerError.length > 0
    }
    Rectangle {
        anchors.fill: parent
        z: 1
        visible: previewDropArea.containsDrag
        color: "transparent"
        border.color: Theme.accent
        border.width: 2
    }
}
