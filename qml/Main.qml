import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia

ApplicationWindow {
    id: root
    width: 1440
    height: 900
    minimumWidth: 1020
    minimumHeight: 680
    visible: true
    color: "#181a1b"
    title: "Kadron" + (editorProject.projectUrl.toString() ? " - " + editorProject.projectUrl.toString().split("/").pop() : "")

    property bool forceClose: false
    property bool hasPlayed: false
    property string currentMediaKey: ""
    property int currentClipIndex: -1
    property string editSignature: ""
    property bool sequencePlaying: false
    property bool sequenceAdvancing: false
    property int pendingCueIndex: -1
    property string playerError: ""
    property string notice: ""
    property int inspectorMode: 0
    property int workspace: 0
    property url uploadFile: ""
    property url pendingOpenUrl: ""
    property bool pendingIsProject: false

    function timecode(milliseconds) {
        var total = Math.max(0, Math.floor(milliseconds / 1000))
        var millis = Math.max(0, Math.floor(milliseconds % 1000)).toString().padStart(3, "0")
        return Math.floor(total / 60).toString().padStart(2, "0") + ":" + (total % 60).toString().padStart(2, "0") + "." + millis
    }
    function saveProject() {
        if (editorProject.projectUrl.toString()) editorProject.saveProject()
        else saveDialog.open()
    }
    function syncRangeFields() {
        if (!inField.activeFocus) inField.text = (editorProject.inMs / 1000).toFixed(3)
        if (!outField.activeFocus) outField.text = (editorProject.outMs / 1000).toFixed(3)
    }
    function publishSource() {
        return uploadFile.toString() ? uploadFile : exporter.outputUrl
    }
    function sequenceSignature() {
        var parts = []
        var items = editorProject.clips
        for (var i = 0; i < items.length; i++)
            parts.push(items[i].url.toString() + ":" + items[i].inMs + ":" + items[i].outMs)
        return parts.join("|")
    }
    function posterFrame() {
        var frames = thumbnails.frames
        if (frames.length === 0) return ""
        var index = editorProject.durationMs > 0 ? Math.min(frames.length - 1, Math.floor(player.position / editorProject.durationMs * frames.length)) : 0
        return frames[index] || frames[0] || ""
    }
    function ensureActiveClipVisible() {
        if (editorProject.activeClipIndex < 0 || !clipScroll.contentItem) return
        var top = editorProject.activeClipIndex * 63
        var bottom = top + 58
        var view = clipScroll.contentItem
        if (top < view.contentY) view.contentY = top
        else if (bottom > view.contentY + clipScroll.height) view.contentY = Math.max(0, bottom - clipScroll.height)
    }
    function addMedia(url) {
        if (exporter.busy) {
            root.notice = "Wait for the export before adding a clip"
            return
        }
        if (editorProject.hasMedia ? editorProject.appendMedia(url) : editorProject.importMedia(url))
            root.notice = "Clip added to sequence"
    }
    function togglePlayback() {
        if (player.playbackState === MediaPlayer.PlayingState) {
            sequencePlaying = false
            sequenceAdvancing = false
            player.pause()
        }
        else {
            sequencePlaying = false
            sequenceAdvancing = false
            if (player.position < editorProject.inMs || player.position >= editorProject.outMs)
                player.position = editorProject.inMs
            player.play()
        }
    }
    function cueActiveClip() {
        pendingCueIndex = editorProject.activeClipIndex
        Qt.callLater(function() { root.finishCue() })
    }
    function finishCue() {
        if (pendingCueIndex !== editorProject.activeClipIndex || pendingCueIndex < 0) return
        if (player.source.toString() !== editorProject.mediaUrl.toString()) return
        if (player.mediaStatus !== MediaPlayer.LoadedMedia && player.mediaStatus !== MediaPlayer.BufferedMedia) return
        pendingCueIndex = -1
        player.position = editorProject.inMs
        if (sequencePlaying) player.play()
        sequenceAdvancing = false
    }
    function previewSequence() {
        if (!editorProject.canExport) return
        sequencePlaying = true
        sequenceAdvancing = true
        if (editorProject.activeClipIndex !== 0) editorProject.selectClip(0)
        else cueActiveClip()
    }
    function stopSequence() {
        sequencePlaying = false
        sequenceAdvancing = false
        player.pause()
    }
    function advanceSequence() {
        if (!sequencePlaying || sequenceAdvancing) return
        if (editorProject.activeClipIndex + 1 >= editorProject.clipCount) {
            sequencePlaying = false
            player.pause()
            return
        }
        sequenceAdvancing = true
        editorProject.selectClip(editorProject.activeClipIndex + 1)
    }
    function applyOpen(url, isProject) {
        var opened = isProject ? editorProject.openProject(url) : editorProject.importMedia(url)
        if (opened) {
            exporter.resetResult()
            root.playerError = ""
            root.notice = isProject ? "Project opened" : "Media imported"
            root.uploadFile = ""
        }
    }
    function requestOpen(url, isProject) {
        if (exporter.busy || toolsClient.busy || localTools.busy || remoteJobs.busy) {
            root.notice = "Finish or cancel the current operation before opening another file"
            return
        }
        if (editorProject.dirty) {
            pendingOpenUrl = url
            pendingIsProject = isProject
            replaceDialog.open()
        } else applyOpen(url, isProject)
    }

    Component.onCompleted: syncRangeFields()
    onClosing: function(event) {
        if (!forceClose && (editorProject.dirty || exporter.busy || toolsClient.busy || localTools.busy || remoteJobs.busy)) {
            event.accepted = false
            quitDialog.open()
        }
    }

    Connections {
        target: editorProject
        function onChanged() {
            root.syncRangeFields()
            var signature = root.sequenceSignature()
            if (signature !== root.editSignature) {
                root.editSignature = signature
                exporter.resetResult()
            }
            if (root.currentClipIndex !== editorProject.activeClipIndex) {
                root.currentClipIndex = editorProject.activeClipIndex
                if (!root.sequencePlaying) player.pause()
                root.cueActiveClip()
                Qt.callLater(function() { root.ensureActiveClipVisible() })
            }
            var mediaKey = editorProject.mediaUrl.toString()
            if (mediaKey !== root.currentMediaKey) {
                root.currentMediaKey = mediaKey
                root.hasPlayed = false
            }
            if (editorProject.hasMedia && editorProject.durationMs > 0)
                thumbnails.generate(editorProject.mediaUrl, editorProject.durationMs)
        }
    }

    Shortcut { sequence: StandardKey.Open; onActivated: mediaDialog.open() }
    Shortcut { sequence: StandardKey.Save; enabled: editorProject.hasMedia; onActivated: root.saveProject() }
    Shortcut { sequence: "Space"; enabled: root.workspace === 0 && editorProject.hasMedia; onActivated: root.togglePlayback() }
    Shortcut { sequence: "I"; enabled: root.workspace === 0 && editorProject.hasMedia && !exporter.busy; onActivated: editorProject.setInMs(player.position) }
    Shortcut { sequence: "O"; enabled: root.workspace === 0 && editorProject.hasMedia && !exporter.busy; onActivated: editorProject.setOutMs(player.position) }
    Shortcut { sequence: "Ctrl+K"; enabled: root.workspace === 0 && editorProject.hasMedia && !exporter.busy; onActivated: editorProject.splitAt(player.position) }

    FileDialog {
        id: mediaDialog
        title: "Import media"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Media files (*.mp4 *.mov *.mkv *.webm *.m4v *.avi *.mp3 *.wav *.flac *.m4a *.ogg)", "All files (*)"]
        onAccepted: root.requestOpen(selectedFile, false)
    }
    FileDialog {
        id: addClipDialog
        title: "Add clip to sequence"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Media files (*.mp4 *.mov *.mkv *.webm *.m4v *.avi *.mp3 *.wav *.flac *.m4a *.ogg)", "All files (*)"]
        onAccepted: root.addMedia(selectedFile)
    }
    FileDialog {
        id: openDialog
        title: "Open Kadron project"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Kadron project (*.kadr)"]
        onAccepted: root.requestOpen(selectedFile, true)
    }
    FileDialog {
        id: saveDialog
        title: "Save Kadron project"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "kadr"
        nameFilters: ["Kadron project (*.kadr)"]
        onAccepted: if (editorProject.saveProject(selectedFile)) root.notice = "Project saved"
    }
    FileDialog {
        id: exportDialog
        title: "Export MP4"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "mp4"
        nameFilters: ["MP4 video (*.mp4)"]
        onAccepted: {
            if (editorProject.clipCount > 1) exporter.startSequence(editorProject.clips, selectedFile)
            else exporter.start(editorProject.mediaUrl, selectedFile, editorProject.inMs, editorProject.outMs)
        }
    }
    FileDialog {
        id: uploadDialog
        title: "Select a file to publish"
        fileMode: FileDialog.OpenFile
        onAccepted: root.uploadFile = selectedFile
    }

    Dialog {
        id: replaceDialog
        modal: true
        title: "Replace current project?"
        anchors.centerIn: parent
        width: 390
        standardButtons: Dialog.NoButton
        background: Rectangle { color: "#282d2f"; radius: 6; border.color: "#485053" }
        contentItem: ColumnLayout {
            spacing: 17
            Text { text: "Unsaved changes in the current project will be lost."; color: "#e8eceb"; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            RowLayout {
                Item { Layout.fillWidth: true }
                EditorButton { text: "Keep editing"; onClicked: replaceDialog.close() }
                EditorButton {
                    text: "Replace"
                    danger: true
                    onClicked: {
                        root.applyOpen(root.pendingOpenUrl, root.pendingIsProject)
                        replaceDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: quitDialog
        modal: true
        title: "Close Kadron?"
        anchors.centerIn: parent
        width: 390
        standardButtons: Dialog.NoButton
        background: Rectangle { color: "#282d2f"; radius: 6; border.color: "#485053" }
        contentItem: ColumnLayout {
            spacing: 17
            Text {
                Layout.fillWidth: true
                text: exporter.busy || toolsClient.busy || localTools.busy || remoteJobs.busy ? "Current work will stop. A job already submitted to the server may continue processing. Unsaved changes will be lost." : "Unsaved project changes will be lost."
                wrapMode: Text.WordWrap
                color: "#e8eceb"
                font.pixelSize: 13
            }
            RowLayout {
                Item { Layout.fillWidth: true }
                EditorButton { text: "Keep working"; onClicked: quitDialog.close() }
                EditorButton {
                    text: "Close without saving"
                    danger: true
                    onClicked: {
                        exporter.cancel()
                        toolsClient.cancel()
                        localTools.cancel()
                        remoteJobs.cancel()
                        root.forceClose = true
                        quitDialog.close()
                        root.close()
                    }
                }
            }
        }
    }

    MediaPlayer {
        id: player
        source: editorProject.mediaUrl
        audioOutput: AudioOutput { volume: volumeSlider.value }
        videoOutput: videoOutput
        onDurationChanged: if (source.toString() === editorProject.mediaUrl.toString()) editorProject.setDurationMs(duration)
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) root.finishCue()
        onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) root.hasPlayed = true
        onPositionChanged: {
            if (playbackState === MediaPlayer.PlayingState && editorProject.outMs > editorProject.inMs && position >= editorProject.outMs) {
                if (root.sequencePlaying) root.advanceSequence()
                else pause()
            }
        }
        onErrorOccurred: function(error, errorString) {
            root.sequencePlaying = false
            root.sequenceAdvancing = false
            root.pendingCueIndex = -1
            root.playerError = errorString
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 54
            color: "#222527"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 10
                Text { text: "KADRON"; color: "#ecf0ef"; font.pixelSize: 17; font.weight: Font.Bold; Layout.preferredWidth: 110 }
                Rectangle { width: 1; height: 22; color: "#464c4e" }
                Text {
                    text: root.workspace === 0 ? editorProject.hasMedia ? editorProject.mediaName : "Untitled project" : "Media tools"
                    color: "#c5cdcc"
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
                Text {
                    visible: root.workspace === 0 && editorProject.dirty
                    text: "Unsaved changes"
                    color: "#dcb287"
                    font.pixelSize: 11
                }
                EditorButton { text: "Open project"; visible: root.workspace === 0; subtle: true; onClicked: openDialog.open() }
                EditorButton { text: "Import"; visible: root.workspace === 0; onClicked: mediaDialog.open() }
                EditorButton { text: "Save"; visible: root.workspace === 0; enabled: editorProject.hasMedia; onClicked: root.saveProject() }
                EditorButton {
                    text: "Export MP4"
                    visible: root.workspace === 0
                    primary: true
                    enabled: editorProject.canExport && !exporter.busy && exporter.available
                    onClicked: exportDialog.open()
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3b4142" }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 45
            color: "#202425"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 4
                Repeater {
                    model: ["Edit", "Download", "Audio", "Compress", "GIF", "PDF", "QR", "Publish"]
                    EditorButton {
                        required property int index
                        required property string modelData
                        text: modelData
                        primary: index === 7 ? root.workspace === 0 && root.inspectorMode === 1 : root.workspace === index && (index !== 0 || root.inspectorMode === 0)
                        subtle: !primary
                        onClicked: {
                            if (index === 7) { root.workspace = 0; root.inspectorMode = 1 }
                            else { root.workspace = index; if (index === 0) root.inspectorMode = 0 }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3b4142" }
        }

        RowLayout {
            visible: root.workspace === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Rectangle {
                Layout.preferredWidth: 210
                Layout.fillHeight: true
                color: "#202324"
                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 18
                    anchors.bottomMargin: 15
                    spacing: 7
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Sequence"; color: "#e6eae9"; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Text { text: editorProject.clipCount + " · " + root.timecode(editorProject.sequenceDurationMs); color: "#aab7b5"; font.pixelSize: 10 }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#3a4042" }
                    ScrollView {
                        id: clipScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 105
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical: ScrollBar {
                            width: 7
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle { implicitWidth: 5; radius: 2; color: "#697576" }
                        }
                        Column {
                            width: clipScroll.availableWidth - 4
                            spacing: 5
                            Repeater {
                                model: editorProject.clips
                                delegate: Rectangle {
                                    required property int index
                                    required property var modelData
                                    width: parent.width
                                    height: 58
                                    radius: 4
                                    color: editorProject.activeClipIndex === index ? "#344447" : clipMouse.containsMouse ? "#2d3638" : "#282d2f"
                                    border.color: editorProject.activeClipIndex === index ? "#8bbec1" : "#3e4749"
                                    border.width: 1
                                    MouseArea {
                                        id: clipMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.sequencePlaying = false; root.sequenceAdvancing = false; editorProject.selectClip(index) }
                                    }
                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 3
                                        Text { text: "CLIP " + (index + 1).toString().padStart(2, "0") + "   " + root.timecode(modelData.lengthMs); color: editorProject.activeClipIndex === index ? "#bfe3e4" : "#aab9b7"; font.pixelSize: 10; font.weight: Font.DemiBold }
                                        Text { width: parent.width; text: modelData.name; color: "#e9eeed"; font.pixelSize: 11; elide: Text.ElideMiddle }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        visible: !editorProject.hasMedia
                        text: "No clips in this project"
                        color: "#a7b1b0"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    EditorButton { text: "Add clip"; Layout.fillWidth: true; onClicked: addClipDialog.open() }
                    RowLayout {
                        Layout.fillWidth: true
                        EditorButton { text: "Up"; subtle: true; Layout.fillWidth: true; enabled: editorProject.activeClipIndex > 0 && !exporter.busy; onClicked: editorProject.moveClip(editorProject.activeClipIndex, -1) }
                        EditorButton { text: "Down"; subtle: true; Layout.fillWidth: true; enabled: editorProject.activeClipIndex < editorProject.clipCount - 1 && !exporter.busy; onClicked: editorProject.moveClip(editorProject.activeClipIndex, 1) }
                    }
                    EditorButton { text: "Remove selected"; subtle: true; danger: true; Layout.fillWidth: true; enabled: editorProject.clipCount > 1 && !exporter.busy; onClicked: editorProject.removeClip(editorProject.activeClipIndex) }
                }
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#3a4042" }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#0e1011"
                    DropArea {
                        id: previewDropArea
                        anchors.fill: parent
                        z: 2
                        onDropped: function(drop) {
                            if (drop.urls.length > 0) root.requestOpen(drop.urls[0], false)
                        }
                    }
                    VideoOutput {
                        id: videoOutput
                        anchors.fill: parent
                        anchors.margins: 20
                        visible: player.hasVideo && root.hasPlayed
                        fillMode: VideoOutput.PreserveAspectFit
                    }
                    Image {
                        anchors.fill: parent
                        anchors.margins: 20
                        source: root.posterFrame()
                        fillMode: Image.PreserveAspectFit
                        visible: editorProject.hasMedia && player.hasVideo && !root.hasPlayed && root.posterFrame() !== ""
                        asynchronous: true
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 13
                        visible: !editorProject.hasMedia || !player.hasVideo || !root.hasPlayed && root.posterFrame() === ""
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: !editorProject.hasMedia ? "Your next edit starts here" : player.hasVideo ? editorProject.mediaName : "Audio clip"
                            color: "#e8eeee"
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: editorProject.hasMedia && !player.hasVideo
                            text: editorProject.mediaName
                            color: "#b7c5c3"
                            font.pixelSize: 12
                        }
                        EditorButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: !editorProject.hasMedia
                            text: "Import media"
                            primary: true
                            onClicked: mediaDialog.open()
                        }
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 16
                        text: root.playerError
                        color: "#e7aaa4"
                        font.pixelSize: 12
                        visible: root.playerError.length > 0
                    }
                    Rectangle {
                        anchors.fill: parent
                        z: 1
                        visible: previewDropArea.containsDrag
                        color: "transparent"
                        border.color: "#9bcdd0"
                        border.width: 2
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    color: "#222627"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 10
                        EditorButton { text: player.playbackState === MediaPlayer.PlayingState ? "Pause" : "Play"; enabled: editorProject.hasMedia; onClicked: root.togglePlayback() }
                        Text { text: root.timecode(player.position); color: "#f0f3f2"; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Text { text: "/ " + root.timecode(editorProject.durationMs); color: "#aab5b5"; font.pixelSize: 12 }
                        Item { Layout.fillWidth: true }
                        Text { text: "Volume"; color: "#aab5b5"; font.pixelSize: 11 }
                        Slider { id: volumeSlider; from: 0; to: 1; value: 0.8; Layout.preferredWidth: 90 }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#393f41" }
                }
            }

            Rectangle {
                Layout.preferredWidth: 316
                Layout.fillHeight: true
                color: "#202324"
                Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: "#3a4042" }
                ScrollView {
                    id: inspectorScroll
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 11
                    anchors.topMargin: 15
                    anchors.bottomMargin: 15
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical: ScrollBar {
                        width: 7
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle { implicitWidth: 5; radius: 2; color: "#697576" }
                    }
                    ColumnLayout {
                    width: inspectorScroll.availableWidth - 7
                    spacing: 11
                    RowLayout {
                        Layout.fillWidth: true
                        EditorButton { text: "Edit"; primary: root.inspectorMode === 0; Layout.fillWidth: true; onClicked: root.inspectorMode = 0 }
                        EditorButton { text: "Publish"; primary: root.inspectorMode === 1; Layout.fillWidth: true; onClicked: root.inspectorMode = 1 }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#3a4042" }

                    ColumnLayout {
                        visible: root.inspectorMode === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10
                        Text { text: "Selection"; color: "#e7ebea"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { text: "In point (seconds)"; color: "#b0bab9"; font.pixelSize: 11 }
                        EditorField {
                            id: inField
                            Layout.fillWidth: true
                            enabled: editorProject.durationMs > 0 && !exporter.busy
                            validator: DoubleValidator { bottom: 0; decimals: 3 }
                            onEditingFinished: editorProject.setInMs(Math.round(Number(text) * 1000))
                        }
                        Text { text: "Out point (seconds)"; color: "#b0bab9"; font.pixelSize: 11 }
                        EditorField {
                            id: outField
                            Layout.fillWidth: true
                            enabled: editorProject.durationMs > 0 && !exporter.busy
                            validator: DoubleValidator { bottom: 0; decimals: 3 }
                            onEditingFinished: editorProject.setOutMs(Math.round(Number(text) * 1000))
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a4042"; Layout.topMargin: 5 }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Selected duration"; color: "#b0bab9"; font.pixelSize: 12; Layout.fillWidth: true }
                            Text { text: root.timecode(editorProject.outMs - editorProject.inMs); color: "#e8ecea"; font.pixelSize: 12; font.weight: Font.DemiBold }
                        }
                        EditorButton {
                            Layout.fillWidth: true
                            text: "Split at playhead  Ctrl+K"
                            enabled: editorProject.hasMedia && !exporter.busy && player.position > editorProject.inMs + 100 && player.position < editorProject.outMs - 100
                            onClicked: editorProject.splitAt(player.position)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Sequence duration"; color: "#b0bab9"; font.pixelSize: 12; Layout.fillWidth: true }
                            Text { text: root.timecode(editorProject.sequenceDurationMs); color: "#e8ecea"; font.pixelSize: 12; font.weight: Font.DemiBold }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: !exporter.available
                            text: "FFmpeg is required for export. Set KADRON_FFMPEG or add it to PATH."
                            wrapMode: Text.WordWrap
                            color: "#e2bb8e"
                            font.pixelSize: 11
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: exporter.errorText.length > 0
                            text: exporter.errorText
                            wrapMode: Text.WordWrap
                            color: "#e7aaa4"
                            font.pixelSize: 11
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: exporter.busy
                            text: exporter.stage + "  " + exporter.progress + "%"
                            color: "#c9d5d3"
                            font.pixelSize: 11
                        }
                        EditorButton {
                            Layout.fillWidth: true
                            text: exporter.busy ? "Cancel export" : "Export sequence"
                            enabled: exporter.busy || editorProject.canExport && exporter.available
                            primary: !exporter.busy
                            onClicked: exporter.busy ? exporter.cancel() : exportDialog.open()
                        }
                        EditorButton {
                            Layout.fillWidth: true
                            visible: exporter.outputUrl.toString().length > 0 && !exporter.busy
                            text: "Open exported file"
                            onClicked: Qt.openUrlExternally(exporter.outputUrl)
                        }
                    }

                    ColumnLayout {
                        visible: root.inspectorMode === 1
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 9
                        Text { text: "Tools server"; color: "#e7ebea"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        EditorField {
                            id: serverField
                            Layout.fillWidth: true
                            text: toolsClient.serverUrl
                            placeholderText: "https://tools.example.com"
                            onEditingFinished: toolsClient.serverUrl = text
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            EditorButton { text: "Connect"; enabled: !toolsClient.busy; onClicked: { toolsClient.serverUrl = serverField.text; toolsClient.testConnection() } }
                            Text { text: toolsClient.connected ? "Connected" : "Not connected"; color: toolsClient.connected ? "#a7d4b4" : "#aeb8b7"; font.pixelSize: 11; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a4042"; Layout.topMargin: 3 }
                        Text { text: "Publish a file"; color: "#e7ebea"; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text {
                            Layout.fillWidth: true
                            text: root.publishSource().toString() ? root.publishSource().toString().split("/").pop() : "No file selected"
                            color: "#c6d0ce"
                            elide: Text.ElideMiddle
                            font.pixelSize: 11
                        }
                        EditorButton { text: "Choose file"; Layout.fillWidth: true; onClicked: uploadDialog.open() }
                        RowLayout {
                            Layout.fillWidth: true
                            EditorButton { text: "To Clips"; Layout.fillWidth: true; enabled: !toolsClient.busy && root.publishSource().toString(); onClicked: toolsClient.publishClip(root.publishSource()) }
                            EditorButton { text: "To Drop"; Layout.fillWidth: true; enabled: !toolsClient.busy && root.publishSource().toString(); onClicked: toolsClient.publishDrop(root.publishSource()) }
                        }
                        Text { text: "Guest: Clips 200 MB / 24 h, Drop 50 MB / 1 h"; color: "#aeb8b6"; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a4042"; Layout.topMargin: 3 }
                        Text { text: "Shorten a link"; color: "#e7ebea"; font.pixelSize: 13; font.weight: Font.DemiBold }
                        EditorField { id: targetField; Layout.fillWidth: true; placeholderText: "https://..." }
                        RowLayout {
                            Layout.fillWidth: true
                            EditorField { id: slugField; Layout.fillWidth: true; placeholderText: "Custom slug (optional)" }
                            EditorButton { text: "Create"; enabled: !toolsClient.busy; onClicked: toolsClient.shorten(targetField.text, slugField.text) }
                        }
                        Text {
                            visible: toolsClient.busy
                            text: toolsClient.stage + "  " + toolsClient.progress + "%"
                            color: "#d5e1df"
                            font.pixelSize: 11
                        }
                        ProgressBar { visible: toolsClient.busy; value: toolsClient.progress / 100; Layout.fillWidth: true }
                        Text {
                            Layout.fillWidth: true
                            visible: toolsClient.errorText.length > 0
                            text: toolsClient.errorText
                            wrapMode: Text.WordWrap
                            color: "#e7aaa4"
                            font.pixelSize: 11
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: toolsClient.resultUrl.toString().length > 0
                            EditorField {
                                id: resultField
                                Layout.fillWidth: true
                                readOnly: true
                                text: toolsClient.resultUrl.toString()
                                selectByMouse: true
                            }
                            EditorButton {
                                text: "Copy"
                                onClicked: { resultField.selectAll(); resultField.copy(); resultField.deselect() }
                            }
                        }
                        EditorButton { text: "Cancel upload"; visible: toolsClient.busy; danger: true; onClicked: toolsClient.cancel() }
                    }
                    }
                }
            }
        }

        Rectangle {
            visible: root.workspace === 0
            Layout.fillWidth: true
            Layout.preferredHeight: 248
            color: "#202324"
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#3a4042" }
            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 13
                anchors.bottomMargin: 13
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Clip timeline"; color: "#e8eceb"; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { text: editorProject.hasMedia ? (editorProject.activeClipIndex + 1) + "/" + editorProject.clipCount : ""; color: "#b9d7d7"; font.pixelSize: 11 }
                    Text { text: editorProject.hasMedia ? editorProject.mediaName : "No clip loaded"; color: "#aab4b3"; font.pixelSize: 11; elide: Text.ElideMiddle; Layout.fillWidth: true }
                    EditorButton {
                        text: root.sequencePlaying ? "Stop preview" : "Preview sequence"
                        enabled: editorProject.canExport && !exporter.busy
                        onClicked: root.sequencePlaying ? root.stopSequence() : root.previewSequence()
                    }
                    EditorButton { text: "Split"; enabled: editorProject.hasMedia && !exporter.busy && player.position > editorProject.inMs + 100 && player.position < editorProject.outMs - 100; onClicked: editorProject.splitAt(player.position) }
                    EditorButton { text: "Mark in"; enabled: editorProject.hasMedia && !exporter.busy; onClicked: editorProject.setInMs(player.position) }
                    EditorButton { text: "Mark out"; enabled: editorProject.hasMedia && !exporter.busy; onClicked: editorProject.setOutMs(player.position) }
                }
                Timeline {
                    enabled: !exporter.busy
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    durationMs: editorProject.durationMs
                    inMs: editorProject.inMs
                    outMs: editorProject.outMs
                    playheadMs: player.position
                    frames: thumbnails.frames
                    onSeekRequested: function(ms) { root.sequencePlaying = false; root.sequenceAdvancing = false; player.position = ms }
                    onInRequested: function(ms) { editorProject.setInMs(ms) }
                    onOutRequested: function(ms) { editorProject.setOutMs(ms) }
                    onMoveRequested: function(delta) { editorProject.moveRange(delta) }
                }
            }
        }

        ToolsWorkspace {
            section: root.workspace
            visible: root.workspace !== 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            onPublishFile: function(fileUrl) {
                root.uploadFile = fileUrl
                root.workspace = 0
                root.inspectorMode = 1
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            color: "#2a2e30"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 8
                Rectangle { width: 6; height: 6; radius: 3; color: editorProject.errorText || exporter.errorText || toolsClient.errorText || localTools.errorText || remoteJobs.errorText ? "#e8a29e" : exporter.busy || toolsClient.busy || localTools.busy || remoteJobs.busy ? "#e6b980" : "#9dcab6" }
                Text {
                    text: editorProject.errorText || exporter.errorText || toolsClient.errorText || localTools.errorText || remoteJobs.errorText || (exporter.busy ? exporter.stage + " " + exporter.progress + "%" : localTools.busy ? localTools.stage + " " + localTools.progress + "%" : remoteJobs.busy ? remoteJobs.stage + " " + remoteJobs.progress + "%" : toolsClient.busy ? toolsClient.stage + " " + toolsClient.progress + "%" : root.notice || "Ready")
                    color: "#d6dedd"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text { text: root.workspace === 0 ? "LOCAL EDIT" : root.workspace === 1 || root.workspace >= 5 ? "TOOLS SERVER" : "LOCAL PROCESSING"; color: "#a5b0af"; font.pixelSize: 10; font.weight: Font.DemiBold }
            }
        }
    }
}
