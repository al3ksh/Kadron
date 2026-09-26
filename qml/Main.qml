import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import QtQuick.Effects

ApplicationWindow {
    id: root
    width: 1440
    height: 900
    minimumWidth: 1020
    minimumHeight: 680
    // With the startup intro, main.cpp shows the window when the intro hands off.
    visible: !startupIntroActive
    color: Theme.window
    // Read by WindowChrome to paint the native Windows caption in the app's colors.
    readonly property color captionColor: Theme.rail
    readonly property color captionTextColor: Theme.textSoft
    readonly property bool captionDark: Theme.dark
    title: "Kadron" + (editorProject.projectUrl.toString() ? " - " + editorProject.projectUrl.toString().split("/").pop() : "")

    property bool forceClose: false
    property bool closeAfterSave: false
    readonly property bool dialogOpen: quitDialog.visible || replaceDialog.visible
    property string currentMediaKey: ""
    property int currentClipIndex: -1
    property string editSignature: ""
    property bool sequencePlaying: false
    property bool sequenceAdvancing: false
    property int pendingCueIndex: -1
    // Source position to land on once a newly selected clip is cued; -1 means its in point.
    property real pendingSourceMs: -1
    property bool scrubbing: false
    property real scrubTargetMs: 0
    // Seek coalescing: at most one seek is in flight; the latest request wins.
    property real queuedSeekMs: -1
    property bool seekInFlight: false
    property string playerError: ""
    property string notice: ""
    property int inspectorMode: 0
    property int workspace: 0
    property url uploadFile: ""
    property url pendingOpenUrl: ""
    property bool pendingIsProject: false
    readonly property string sectionTitle: ["Editor", "Download", "Audio", "Compress", "GIF Studio", "PDF Tools", "QR Code", "Clips", "Drop", "Shortener", "Images"][workspace]
    // Workspaces 7-9 publish to the Tools server; 10 (Images) is local like 1-6.
    readonly property bool shareWorkspace: workspace >= 7 && workspace <= 9
    readonly property bool anyBusy: exporter.busy || toolsClient.busy || localTools.busy || localDownload.busy || localPdf.busy || localQr.busy || localImages.busy
    onWorkspaceChanged: {
        if (workspace === 0) editorEnter.restart()
        else if (workspace === 10) imagesEnter.restart()
        else if (shareWorkspace) shareEnter.restart()
        else toolsEnter.restart()
    }
    onInspectorModeChanged: inspectorEnter.restart()
    function revealAfterIntro() {
        if (workspace === 0) editorEnter.restart()
        else if (workspace === 10) imagesEnter.restart()
        else if (shareWorkspace) shareEnter.restart()
        else toolsEnter.restart()
    }

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
            // Play runs on through the following clips, like the timeline reads.
            sequencePlaying = true
            sequenceAdvancing = false
            if (player.position < editorProject.inMs || player.position >= editorProject.outMs - 20)
                player.position = editorProject.inMs
            player.play()
        }
    }
    function clipStartMs(index) {
        var items = editorProject.clips, total = 0
        for (var i = 0; i < index && i < items.length; i++) total += Math.max(0, items[i].lengthMs)
        return total
    }
    readonly property real sequencePositionMs: {
        if (scrubbing) return scrubTargetMs
        var index = editorProject.activeClipIndex
        if (index < 0) return 0
        var source = pendingCueIndex >= 0 && pendingSourceMs >= 0 ? pendingSourceMs : player.position
        var offset = Math.max(0, Math.min(editorProject.outMs - editorProject.inMs, source - editorProject.inMs))
        return clipStartMs(index) + offset
    }
    function seekSequence(ms) {
        var items = editorProject.clips
        if (items.length === 0) return
        var start = 0, index = items.length - 1
        for (var i = 0; i < items.length; i++) {
            var length = Math.max(0, items[i].lengthMs)
            if (ms < start + length || i === items.length - 1) { index = i; break }
            start += length
        }
        var clip = items[index]
        var source = Math.max(clip.inMs, Math.min(clip.outMs - 1, clip.inMs + ms - start))
        if (index !== editorProject.activeClipIndex || pendingCueIndex >= 0) {
            pendingSourceMs = source
            if (index !== editorProject.activeClipIndex) editorProject.selectClip(index)
        } else requestSourceSeek(source)
    }
    function beginScrub(ms) {
        if (sequencePlaying || player.playbackState === MediaPlayer.PlayingState) {
            sequencePlaying = false
            sequenceAdvancing = false
            player.pause()
        }
        scrubbing = true
        scrubTargetMs = ms
        seekSequence(ms)
    }
    function requestSourceSeek(ms) {
        queuedSeekMs = ms
        if (!seekInFlight) issueSeek()
    }
    function issueSeek() {
        if (queuedSeekMs < 0) return
        seekInFlight = true
        player.position = queuedSeekMs
        queuedSeekMs = -1
        seekSettle.restart()
    }
    function settleSeek() {
        seekSettle.stop()
        seekInFlight = false
        issueSeek()
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
        player.position = pendingSourceMs >= 0 ? pendingSourceMs : editorProject.inMs
        pendingSourceMs = -1
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
        if (root.anyBusy) {
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
    function stopAllWork() {
        exporter.cancel()
        toolsClient.cancel()
        localTools.cancel()
        localDownload.cancel()
        localPdf.cancel()
        localQr.cancel()
    }
    // Every close fades the window out; the real close runs once the fade ends.
    function fadeAndClose() {
        stopAllWork()
        forceClose = true
        quitDialog.close()
        closeFade.start()
    }
    function saveAndClose() {
        if (editorProject.projectUrl.toString()) {
            if (editorProject.saveProject()) fadeAndClose()
        } else {
            closeAfterSave = true
            saveDialog.open()
        }
    }
    onClosing: function(event) {
        if (forceClose) return
        event.accepted = false
        if (editorProject.dirty || root.anyBusy) quitDialog.open()
        else fadeAndClose()
    }
    NumberAnimation {
        id: closeFade
        target: root
        property: "opacity"
        to: 0
        duration: 170
        easing.type: Easing.InCubic
        onFinished: root.close()
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
            }
            var mediaKey = editorProject.mediaUrl.toString()
            if (mediaKey !== root.currentMediaKey) {
                root.currentMediaKey = mediaKey
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
    Shortcut { sequences: [StandardKey.Undo]; enabled: root.workspace === 0 && editorProject.canUndo && !exporter.busy; onActivated: editorProject.undo() }
    Shortcut { sequences: [StandardKey.Redo, "Ctrl+Shift+Z"]; enabled: root.workspace === 0 && editorProject.canRedo && !exporter.busy; onActivated: editorProject.redo() }
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
        onAccepted: {
            if (editorProject.saveProject(selectedFile)) {
                root.notice = "Project saved"
                if (root.closeAfterSave) root.fadeAndClose()
            }
            root.closeAfterSave = false
        }
        onRejected: root.closeAfterSave = false
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

    StudioDialog {
        id: replaceDialog
        heading: "Replace the current project?"
        message: "Unsaved changes in the current project will be lost."
        iconName: "folder"
        warning: true
        EditorButton {
            text: "Replace"
            danger: true
            onClicked: {
                root.applyOpen(root.pendingOpenUrl, root.pendingIsProject)
                replaceDialog.close()
            }
        }
        EditorButton { text: "Keep editing"; subtle: true; onClicked: replaceDialog.close() }
    }

    StudioDialog {
        id: quitDialog
        objectName: "quitDialog"
        heading: editorProject.dirty ? "Save changes before closing?" : "Stop work and close?"
        message: root.anyBusy
                 ? (editorProject.dirty ? "Your project has unsaved changes, and running work will stop. A server upload already submitted may continue processing."
                                        : "Running work will stop. A server upload already submitted may continue processing.")
                 : "Your project has unsaved changes. Save them now or close without saving."
        iconName: editorProject.dirty ? "save" : "close"
        warning: !editorProject.dirty
        EditorButton {
            visible: editorProject.dirty
            text: "Save and close"
            iconName: "save"
            primary: true
            enabled: editorProject.hasMedia
            onClicked: root.saveAndClose()
        }
        EditorButton {
            text: editorProject.dirty ? "Don't save" : "Stop and close"
            danger: true
            subtle: editorProject.dirty
            onClicked: root.fadeAndClose()
        }
        Item { Layout.fillWidth: true }
        EditorButton { text: "Keep working"; subtle: true; onClicked: quitDialog.close() }
    }

    // A seek is settled when the decoder delivers a frame, or after a short
    // fallback for audio-only media.
    Timer { id: seekSettle; interval: 90; onTriggered: root.settleSeek() }
    Connections {
        target: videoOutput.videoSink
        function onVideoFrameChanged() { if (root.seekInFlight) root.settleSeek() }
    }

    MediaPlayer {
        id: player
        objectName: "editorPlayer"
        source: editorProject.mediaUrl
        audioOutput: AudioOutput { volume: editorVolume.effectiveVolume }
        videoOutput: videoOutput
        onDurationChanged: function(duration) { if (source.toString() === editorProject.mediaUrl.toString()) editorProject.setDurationMs(duration) }
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) root.finishCue()
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

    RowLayout {
        id: appContent
        anchors.fill: parent
        spacing: 0
        // Blur the workspace behind modal dialogs; the layer exists only while needed.
        property real blurAmount: root.dialogOpen ? 1 : 0
        Behavior on blurAmount { NumberAnimation { duration: Theme.reveal + 40; easing.type: Easing.OutCubic } }
        layer.enabled: blurAmount > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 40
            blur: appContent.blurAmount
            saturation: -0.15 * appContent.blurAmount
        }

        Rectangle {
            Layout.preferredWidth: 188
            Layout.fillHeight: true
            color: Theme.rail
            // One shared highlight travels between rail items on a spring.
            Item {
                id: navHighlight
                readonly property Item target: [navEditor, navDownload, navAudio, navCompress, navGif, navPdf, navQr, navClips, navDrop, navShortener, navImages][root.workspace] || null
                visible: target !== null
                x: navColumn.x + (target ? target.x : 0)
                y: navColumn.y + (target ? target.y : 0)
                width: target ? target.width : 0
                height: target ? target.height : 0
                Behavior on y { SmoothSpring {} }
                Rectangle { anchors.fill: parent; radius: 9; color: Theme.accentWash }
                Rectangle { width: 3; height: 18; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
            }
            ColumnLayout {
                id: navColumn
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 15
                anchors.bottomMargin: 16
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.preferredHeight: 48
                    spacing: 8
                    BrandMark { Layout.preferredWidth: 34; Layout.preferredHeight: 34 }
                    Column {
                        spacing: 0
                        Text { text: "KADRON"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 16; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                        Text { text: "MEDIA STUDIO"; color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 8; font.weight: Font.DemiBold; font.letterSpacing: 1.5 }
                    }
                }
                Item { Layout.preferredHeight: 23 }
                Text { text: "WORKSPACE"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2; Layout.leftMargin: 13; Layout.bottomMargin: 7 }
                NavItem { id: navEditor; Layout.fillWidth: true; title: "Editor"; iconName: "edit"; active: root.workspace === 0 && root.inspectorMode === 0; onClicked: { root.workspace = 0; root.inspectorMode = 0 } }
                NavItem { id: navDownload; Layout.fillWidth: true; title: "Download"; iconName: "download"; active: root.workspace === 1; onClicked: root.workspace = 1 }
                NavItem { id: navAudio; Layout.fillWidth: true; title: "Audio"; iconName: "audio"; active: root.workspace === 2; onClicked: root.workspace = 2 }
                NavItem { id: navCompress; Layout.fillWidth: true; title: "Compress"; iconName: "compress"; active: root.workspace === 3; onClicked: root.workspace = 3 }
                NavItem { id: navGif; Layout.fillWidth: true; title: "GIF Studio"; iconName: "gif"; active: root.workspace === 4; onClicked: root.workspace = 4 }
                NavItem { id: navImages; objectName: "navImages"; Layout.fillWidth: true; title: "Images"; iconName: "image"; active: root.workspace === 10; onClicked: root.workspace = 10 }
                Item { Layout.preferredHeight: 20 }
                Text { text: "UTILITIES"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2; Layout.leftMargin: 13; Layout.bottomMargin: 7 }
                NavItem { id: navPdf; Layout.fillWidth: true; title: "PDF Tools"; iconName: "pdf"; active: root.workspace === 5; onClicked: root.workspace = 5 }
                NavItem { id: navQr; Layout.fillWidth: true; title: "QR Code"; iconName: "qr"; active: root.workspace === 6; onClicked: root.workspace = 6 }
                Item { Layout.preferredHeight: 20 }
                Text { text: "YOUR TOOLS SERVER"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2; Layout.leftMargin: 13; Layout.bottomMargin: 7 }
                NavItem { id: navClips; Layout.fillWidth: true; title: "Clips"; iconName: "publish"; active: root.workspace === 7; onClicked: root.workspace = 7 }
                NavItem { id: navDrop; Layout.fillWidth: true; title: "Drop"; iconName: "publish"; active: root.workspace === 8; onClicked: root.workspace = 8 }
                NavItem { id: navShortener; Layout.fillWidth: true; title: "Shortener"; iconName: "publish"; active: root.workspace === 9; onClicked: root.workspace = 9 }
                Item { Layout.fillHeight: true }
                UpdateCard {
                    id: updateCard
                    Layout.fillWidth: true
                    Layout.bottomMargin: 12
                    updater: appUpdater
                    onRestartRequested: root.close()
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 13
                    Layout.leftMargin: 9
                    spacing: 8
                    Rectangle { width: 7; height: 7; radius: 4; color: toolsClient.connected ? Theme.accent : Theme.textFaint }
                    Text { text: toolsClient.connected ? "Server connected" : "Local workspace"; color: Theme.textMuted; font.pixelSize: 11; Layout.fillWidth: true; Layout.minimumWidth: 0; elide: Text.ElideRight }
                    // Running version; click to look for an update.
                    Text {
                        objectName: "versionLink"
                        text: appUpdater.checking ? "Checking…" : "v" + appUpdater.currentVersion
                        color: versionMouse.containsMouse ? Theme.text : Theme.textFaint
                        font.pixelSize: 10
                        font.features: { "tnum": 1 }
                        MouseArea {
                            id: versionMouse
                            anchors.fill: parent
                            anchors.margins: -5
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: appUpdater.check()
                        }
                    }
                    ToolButton {
                        id: appearanceButton
                        objectName: "appearanceButton"
                        implicitWidth: 26
                        implicitHeight: 26
                        Accessible.name: "Appearance"
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: "Theme and accent"
                        onClicked: appearancePopup.opened ? appearancePopup.close() : appearancePopup.open()
                        contentItem: ToolIcon { name: "palette"; tint: appearanceButton.hovered || appearancePopup.opened ? Theme.text : Theme.textFaint }
                        background: Rectangle { radius: Theme.radiusSmall; color: appearanceButton.hovered || appearancePopup.opened ? Theme.hover : "transparent" }
                        AppearancePopup {
                            id: appearancePopup
                            objectName: "appearancePopup"
                            x: -8
                            y: -height - 10
                        }
                    }
                }
            }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 68
            color: Theme.panel
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 9
                Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: root.workspace === 0 && root.inspectorMode === 1 ? "Publish" : root.sectionTitle; color: Theme.text; font.pixelSize: 18; font.weight: Font.DemiBold }
                    Text {
                        text: root.workspace === 0 ? (editorProject.hasMedia ? editorProject.mediaName : "Create a project or import media") : root.shareWorkspace ? "Connected tools · your server" : "Private processing · on this device"
                        color: Theme.textMuted
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                        width: parent.width
                    }
                }
                Rectangle { visible: root.workspace === 0 && editorProject.dirty; width: 7; height: 7; radius: 4; color: Theme.warning }
                Text { visible: root.workspace === 0 && editorProject.dirty; text: "Unsaved"; color: Theme.warning; font.pixelSize: 11 }
                EditorButton { text: "Open"; visible: root.workspace === 0; subtle: true; onClicked: openDialog.open() }
                EditorButton { text: "Import"; visible: root.workspace === 0; onClicked: mediaDialog.open() }
                EditorButton { text: "Save"; visible: root.workspace === 0; enabled: editorProject.hasMedia; onClicked: root.saveProject() }
                EditorButton { text: "Export MP4"; visible: root.workspace === 0; primary: true; enabled: editorProject.canExport && !exporter.busy && exporter.available; onClicked: exportDialog.open() }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        }

        RevealAnimation { id: editorEnter; target: editorArea; shift: editorShift }
        RevealAnimation { id: toolsEnter; target: toolsArea; shift: toolsShift }
        RevealAnimation { id: shareEnter; target: shareArea; shift: shareShift }
        RevealAnimation { id: imagesEnter; target: imagesArea; shift: imagesShift }
        RevealAnimation { id: inspectorEnter; target: inspectorScroll; shift: inspectorShift; distance: 6 }

        RowLayout {
            id: editorArea
            transform: Translate { id: editorShift }
            visible: root.workspace === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.canvas
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
                        visible: player.hasVideo
                        fillMode: VideoOutput.PreserveAspectFit
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 13
                        visible: !editorProject.hasMedia || !player.hasVideo
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: !editorProject.hasMedia ? "Your next edit starts here" : player.hasVideo ? editorProject.mediaName : "Audio clip"
                            color: Theme.text
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: editorProject.hasMedia && !player.hasVideo
                            text: editorProject.mediaName
                            color: Theme.textMuted
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
                        color: Theme.danger
                        font.pixelSize: 12
                        visible: root.playerError.length > 0
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
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    color: Theme.panel
                    RowLayout {
                        id: transportRow
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 10
                        EditorButton { text: player.playbackState === MediaPlayer.PlayingState ? "Pause" : "Play"; iconName: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play"; enabled: editorProject.hasMedia; onClicked: root.togglePlayback() }
                        Text { text: root.timecode(root.sequencePositionMs); color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Text { text: "/ " + root.timecode(editorProject.sequenceDurationMs); color: Theme.textMuted; font.pixelSize: 12 }
                        Item { Layout.fillWidth: true }
                        VolumeControl { id: editorVolume; objectName: "editorVolume"; compact: transportRow.width <= 460 }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                }
            }

            Rectangle {
                Layout.preferredWidth: 294
                Layout.fillHeight: true
                color: Theme.panel
                Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Theme.line }
                ScrollView {
                    id: inspectorScroll
                    transform: Translate { id: inspectorShift }
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
                            contentItem: Rectangle { implicitWidth: 5; radius: 2; color: Theme.scrollThumb }
                    }
                    ColumnLayout {
                    width: inspectorScroll.availableWidth - 7
                    spacing: 11
                    Text { text: root.inspectorMode === 0 ? "Clip settings" : "Publish & share"; color: Theme.text; font.pixelSize: 16; font.weight: Font.DemiBold }
                    Text { text: root.inspectorMode === 0 ? "Adjust the active clip" : "Send only when you choose to"; color: Theme.textMuted; font.pixelSize: 11 }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.topMargin: 5; Layout.bottomMargin: 5 }

                    ColumnLayout {
                        visible: root.inspectorMode === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 9
                            ColumnLayout {
                                Layout.fillWidth: true
                                Text { text: "In point · s"; color: Theme.textMuted; font.pixelSize: 11 }
                                EditorField {
                                    id: inField
                                    Layout.fillWidth: true
                                    enabled: editorProject.durationMs > 0 && !exporter.busy
                                    validator: DoubleValidator { bottom: 0; decimals: 3 }
                                    onEditingFinished: editorProject.setInMs(Math.round(Number(text) * 1000))
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Text { text: "Out point · s"; color: Theme.textMuted; font.pixelSize: 11 }
                                EditorField {
                                    id: outField
                                    Layout.fillWidth: true
                                    enabled: editorProject.durationMs > 0 && !exporter.busy
                                    validator: DoubleValidator { bottom: 0; decimals: 3 }
                                    onEditingFinished: editorProject.setOutMs(Math.round(Number(text) * 1000))
                                }
                            }
                        }
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.topMargin: 5 }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Selected duration"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true }
                            Text { text: root.timecode(editorProject.outMs - editorProject.inMs); color: Theme.accentSoft; font.pixelSize: 17; font.weight: Font.DemiBold }
                        }
                        EditorButton {
                            Layout.fillWidth: true
                            text: "Split at playhead  Ctrl+K"
                            enabled: editorProject.hasMedia && !exporter.busy && player.position > editorProject.inMs + 100 && player.position < editorProject.outMs - 100
                            onClicked: editorProject.splitAt(player.position)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Sequence duration"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true }
                            Text { text: root.timecode(editorProject.sequenceDurationMs); color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: exporter.available
                            spacing: 8
                            Text { text: "Encoder"; color: Theme.textMuted; font.pixelSize: 12 }
                            ToolCombo {
                                id: encoderCombo
                                objectName: "encoderCombo"
                                Layout.fillWidth: true
                                enabled: !exporter.busy
                                textRole: "label"
                                valueRole: "value"
                                model: encoderItems
                                readonly property var encoderItems: {
                                    var names = { nvenc: "NVIDIA NVENC (GPU)", qsv: "Intel Quick Sync (GPU)", amf: "AMD AMF (GPU)" }
                                    var items = [{ value: "auto", label: !exporter.encodersChecked ? "Auto (checking GPU…)"
                                                                        : exporter.hardwareEncoders.length > 0 ? "Auto · " + names[exporter.hardwareEncoders[0]]
                                                                        : "Auto · CPU (no GPU encoder)" },
                                                 { value: "cpu", label: "CPU (x264)" }]
                                    for (var i = 0; i < exporter.hardwareEncoders.length; i++)
                                        items.push({ value: exporter.hardwareEncoders[i], label: names[exporter.hardwareEncoders[i]] })
                                    return items
                                }
                                currentIndex: {
                                    for (var i = 0; i < encoderItems.length; i++)
                                        if (encoderItems[i].value === exporter.encoder) return i
                                    return 0
                                }
                                onActivated: exporter.encoder = currentValue
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: !exporter.available
                            text: "FFmpeg is required for export. Set KADRON_FFMPEG or add it to PATH."
                            wrapMode: Text.WordWrap
                            color: Theme.warning
                            font.pixelSize: 11
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: exporter.errorText.length > 0
                            text: exporter.errorText
                            wrapMode: Text.WordWrap
                            color: Theme.danger
                            font.pixelSize: 11
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: exporter.busy
                            text: exporter.stage + "  " + exporter.progress + "%  ·  " + exporter.encoderUsed
                            color: Theme.textSoft
                            font.pixelSize: 11
                        }
                        StudioProgress {
                            visible: exporter.busy
                            Layout.fillWidth: true
                            value: exporter.progress / 100
                        }
                        EditorButton {
                            Layout.fillWidth: true
                            visible: exporter.busy
                            text: "Cancel export"
                            danger: true
                            onClicked: exporter.cancel()
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
                        Text { text: "Tools server"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
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
                            Text { text: toolsClient.connected ? "Connected" : "Not connected"; color: toolsClient.connected ? Theme.success : Theme.textMuted; font.pixelSize: 11; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line; Layout.topMargin: 3 }
                        Text { text: "Publish a file"; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text {
                            Layout.fillWidth: true
                            text: root.publishSource().toString() ? root.publishSource().toString().split("/").pop() : "No file selected"
                            color: Theme.textSoft
                            elide: Text.ElideMiddle
                            font.pixelSize: 11
                        }
                        EditorButton { text: "Choose file"; Layout.fillWidth: true; onClicked: uploadDialog.open() }
                        RowLayout {
                            Layout.fillWidth: true
                            EditorButton { text: "To Clips"; Layout.fillWidth: true; enabled: !toolsClient.busy && root.publishSource().toString(); onClicked: toolsClient.publishClip(root.publishSource()) }
                            EditorButton { text: "To Drop"; Layout.fillWidth: true; enabled: !toolsClient.busy && root.publishSource().toString(); onClicked: toolsClient.publishDrop(root.publishSource()) }
                        }
                        Text { text: "Guest: Clips 200 MB / 24 h, Drop 50 MB / 1 h"; color: Theme.textMuted; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line; Layout.topMargin: 3 }
                        Text { text: "Shorten a link"; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                        EditorField { id: targetField; Layout.fillWidth: true; placeholderText: "https://..." }
                        RowLayout {
                            Layout.fillWidth: true
                            EditorField { id: slugField; Layout.fillWidth: true; placeholderText: "Custom slug (optional)" }
                            EditorButton { text: "Create"; enabled: !toolsClient.busy; onClicked: toolsClient.shorten(targetField.text, slugField.text) }
                        }
                        Text {
                            visible: toolsClient.busy
                            text: toolsClient.stage + "  " + toolsClient.progress + "%"
                            color: Theme.textSoft
                            font.pixelSize: 11
                        }
                        StudioProgress { visible: toolsClient.busy; value: toolsClient.progress / 100; Layout.fillWidth: true }
                        Text {
                            Layout.fillWidth: true
                            visible: toolsClient.errorText.length > 0
                            text: toolsClient.errorText
                            wrapMode: Text.WordWrap
                            color: Theme.danger
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
            color: Theme.panel
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }
            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 13
                anchors.bottomMargin: 13
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: "Timeline"; color: Theme.text; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Text { text: editorProject.hasMedia ? editorProject.clipCount + (editorProject.clipCount === 1 ? " clip · " : " clips · ") + root.timecode(editorProject.sequenceDurationMs) : ""; color: Theme.accent; font.pixelSize: 11 }
                    Text { text: editorProject.hasMedia ? "Drag edges to trim, drag clips to reorder, Ctrl + wheel to zoom" : "No clip loaded"; color: Theme.textFaint; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                    EditorButton { iconName: "undo"; subtle: true; enabled: editorProject.canUndo && !exporter.busy; onClicked: editorProject.undo(); ToolTip.visible: hovered; ToolTip.text: "Undo (Ctrl+Z)" }
                    EditorButton { iconName: "redo"; subtle: true; enabled: editorProject.canRedo && !exporter.busy; onClicked: editorProject.redo(); ToolTip.visible: hovered; ToolTip.text: "Redo (Ctrl+Shift+Z)" }
                    EditorButton { text: "Add clip"; iconName: "plus"; enabled: !exporter.busy; onClicked: addClipDialog.open() }
                    EditorButton { text: "Fit"; subtle: true; visible: sequenceTimeline.zoom > 1; onClicked: sequenceTimeline.zoom = 1 }
                    EditorButton { text: "From start"; iconName: "play"; enabled: editorProject.canExport && !exporter.busy; onClicked: root.previewSequence() }
                    EditorButton { text: "Split"; iconName: "split"; enabled: editorProject.hasMedia && !exporter.busy && player.position > editorProject.inMs + 100 && player.position < editorProject.outMs - 100; onClicked: editorProject.splitAt(player.position) }
                    EditorButton { text: "Mark in"; enabled: editorProject.hasMedia && !exporter.busy; onClicked: editorProject.setInMs(player.position) }
                    EditorButton { text: "Mark out"; enabled: editorProject.hasMedia && !exporter.busy; onClicked: editorProject.setOutMs(player.position) }
                }
                Timeline {
                    id: sequenceTimeline
                    enabled: !exporter.busy
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clips: editorProject.clips
                    activeIndex: editorProject.activeClipIndex
                    playheadMs: root.sequencePositionMs
                    playing: player.playbackState === MediaPlayer.PlayingState
                    thumbnailSource: thumbnails
                    onScrubRequested: function(ms) { root.beginScrub(ms) }
                    onScrubFinished: root.scrubbing = false
                    onSelectRequested: function(index) {
                        root.sequencePlaying = false
                        root.sequenceAdvancing = false
                        editorProject.selectClip(index)
                    }
                    onTrimRequested: function(index, inMs, outMs, previewMs) {
                        if (editorProject.setClipRange(index, inMs, outMs) && index === editorProject.activeClipIndex)
                            root.requestSourceSeek(previewMs)
                    }
                    onTrimPreviewRequested: function(index, sourceMs) {
                        if (index === editorProject.activeClipIndex) root.requestSourceSeek(sourceMs)
                    }
                    onMoveRequested: function(from, to) { editorProject.moveClipTo(from, to) }
                    onSplitRequested: editorProject.splitAt(player.position)
                    onDuplicateRequested: function(index) { editorProject.duplicateClip(index) }
                    onRemoveRequested: function(index) { editorProject.removeClip(index) }
                }
            }
        }

        ToolsWorkspace {
            id: toolsArea
            transform: Translate { id: toolsShift }
            objectName: "toolsArea"
            section: Math.min(root.workspace, 6)
            visible: root.workspace >= 1 && root.workspace <= 6
            Layout.fillWidth: true
            Layout.fillHeight: true
            onPublishFile: function(fileUrl) {
                root.uploadFile = fileUrl
                root.workspace = 8
            }
        }

        ShareWorkspace {
            id: shareArea
            transform: Translate { id: shareShift }
            section: root.workspace
            sourceUrl: root.publishSource()
            visible: root.shareWorkspace
            Layout.fillWidth: true
            Layout.fillHeight: true
            onChooseFile: uploadDialog.open()
        }

        ImagesWorkspace {
            id: imagesArea
            transform: Translate { id: imagesShift }
            visible: root.workspace === 10
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            color: Theme.statusBar
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 8
                Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: editorProject.errorText || exporter.errorText || toolsClient.errorText || localTools.errorText || localDownload.errorText || localPdf.errorText || localQr.errorText || localImages.errorText ? Theme.danger : root.anyBusy ? Theme.warning : Theme.accent }
                Text {
                    text: editorProject.errorText || exporter.errorText || toolsClient.errorText || localTools.errorText || localDownload.errorText || localPdf.errorText || localQr.errorText || localImages.errorText || (exporter.busy ? exporter.stage + " " + exporter.progress + "%" : localTools.busy ? localTools.stage + " " + localTools.progress + "%" : localDownload.busy ? localDownload.stage + " " + localDownload.progress + "%" : localPdf.busy ? localPdf.stage : localQr.busy ? localQr.stage : localImages.busy ? localImages.stage : toolsClient.busy ? toolsClient.stage + " " + toolsClient.progress + "%" : root.notice || "Ready")
                    color: Theme.textSoft
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text { text: root.shareWorkspace ? "TOOLS SERVER" : "LOCAL PROCESSING"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.5 }
            }
        }
    }
    }
}
