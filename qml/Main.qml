import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import QtQuick.Effects
import QtCore

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
    readonly property bool dialogOpen: quitDialog.visible || replaceDialog.visible || closeDialog.visible || recoveryDialog.visible || exportSheet.visible || settingsDialog.visible || commandPalette.visible
    property bool closeAfterSaveProject: false
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
    // The active clip, and slider values while they are dragged (-1 when not).
    readonly property var activeClip: editorProject.activeClipIndex >= 0 ? editorProject.clips[editorProject.activeClipIndex] || null : null
    property real clipVolumeDrag: -1
    property real transitionDrag: -1
    property real audioVolumeDrag: -1
    // The selected audio track item, and the one under the playhead for the preview.
    readonly property var activeText: editorProject.activeTextIndex >= 0 ? editorProject.textItems[editorProject.activeTextIndex] || null : null
    readonly property var activeAudio:editorProject.activeAudioIndex >= 0 ? editorProject.audioItems[editorProject.activeAudioIndex] || null : null
    // Two preview players, so two overlapping items are both heard. A slot
    // keeps its item while it plays on, so nothing reloads mid-sound.
    property var audioSlots: [-1, -1]
    function audioIndicesAt(ms) {
        var items = editorProject.audioItems, found = []
        for (var i = items.length - 1; i >= 0; i--)
            if (ms >= items[i].startMs && ms < items[i].startMs + items[i].lengthMs) found.push(i)
        return found
    }
    function slotItem(slot) {
        var index = audioSlots[slot]
        return index >= 0 ? editorProject.audioItems[index] || null : null
    }
    // Item volume shaped by its fades, and lowered under the clip's own sound.
    function audioGain(slot) {
        var item = slotItem(slot)
        if (!item) return 0
        var index = audioSlots[slot]
        var level = audioVolumeDrag >= 0 && index === editorProject.activeAudioIndex ? audioVolumeDrag : item.volume
        var t = sequencePositionMs - item.startMs
        if (item.fadeInMs > 0 && t < item.fadeInMs) level *= Math.sin(Math.max(0, t) / item.fadeInMs * Math.PI / 2)
        var left = item.lengthMs - t
        if (item.fadeOutMs > 0 && left < item.fadeOutMs) level *= Math.sin(Math.max(0, left) / item.fadeOutMs * Math.PI / 2)
        return Math.min(1, level) * (editorProject.musicDuck && clipGain > 0 ? 0.4 : 1)
    }
    // Where "Add audio" puts the chosen file on the sequence.
    property real audioAddMs: 0
    readonly property real clipGain: !activeClip ? 1 : activeClip.muted ? 0 : Math.min(1, clipVolumeDrag >= 0 ? clipVolumeDrag : activeClip.volume)
    // How dark the preview gets near a join: a fade through black goes all
    // the way, a crossfade is hinted with a light dip.
    readonly property real transitionDim: {
        var index = editorProject.activeClipIndex
        if (editorProject.transition === "cut" || editorProject.clipCount < 2 || index < 0 || !activeClip) return 0
        var half = (transitionDrag >= 0 ? transitionDrag : editorProject.transitionMs) / 2
        var position = sequencePositionMs - clipStartMs(index)
        var distance = Infinity
        if (index > 0) distance = Math.min(distance, position)
        if (index < editorProject.clipCount - 1) distance = Math.min(distance, activeClip.lengthMs - position)
        if (distance >= half) return 0
        // Eased like the export (smoothstep).
        var level = Math.max(0, distance) / half
        var depth = 1 - level * level * (3 - 2 * level)
        return editorProject.transition === "fade" ? depth : depth * 0.35
    }
    // Everything an export depends on, to tell when a result is stale.
    function editState() { return JSON.stringify([editorProject.clips, editorProject.exportOptions()]) }
    // Keeps the audio track preview in step with the sequence while it plays.
    function syncMusic() {
        var playing = player.playbackState === MediaPlayer.PlayingState || (sequencePlaying && sequenceAdvancing)
        if (playing) {
            var here = audioIndicesAt(sequencePositionMs)
            var slots = audioSlots.slice()
            for (var s = 0; s < 2; s++) if (here.indexOf(slots[s]) < 0) slots[s] = -1
            for (var k = 0; k < here.length; k++) {
                if (slots.indexOf(here[k]) >= 0) continue
                var free = slots.indexOf(-1)
                if (free >= 0) slots[free] = here[k]
            }
            if (slots[0] !== audioSlots[0] || slots[1] !== audioSlots[1]) audioSlots = slots
        }
        syncAudioPlayer(audioPlayerA, 0, playing)
        syncAudioPlayer(audioPlayerB, 1, playing)
    }
    function syncAudioPlayer(target, slot, playing) {
        var item = slotItem(slot)
        if (!playing || !item || target.duration <= 0) {
            if (target.playbackState === MediaPlayer.PlayingState) target.pause()
            return
        }
        var position = item.inMs + sequencePositionMs - item.startMs
        if (target.playbackState !== MediaPlayer.PlayingState) {
            target.position = position
            target.play()
        } else if (Math.abs(target.position - position) > 400) target.position = position
    }
    // A crash left unsaved work behind: offer it once, after the intro.
    property bool recoveryOffered: false
    property var recovery: ({})
    function offerRecovery() {
        if (recoveryOffered) return
        recoveryOffered = true
        recovery = editorProject.recoveryInfo()
        if (recovery.name && !editorProject.hasMedia) recoveryDialog.open()
        else if (recovery.name) editorProject.discardRecovery()
        if (!Prefs.tutorialDone && !recoveryDialog.opened && !editorProject.hasMedia) tutorial.start()
    }
    property int inspectorMode: 0
    property int workspace: 0
    property url uploadFile: ""
    property url pendingOpenUrl: ""
    property bool pendingIsProject: false
    readonly property string sectionTitle: ["Editor", "Download", "Audio", "Compress", "GIF Studio", "PDF Tools", "QR Code", "Clips", "Drop", "Shortener", "Images", "Reframe"][workspace]
    // Workspaces 7-9 publish to the Tools server; 10 (Images) and 11 (Reframe) are local like 1-6.
    readonly property bool shareWorkspace: workspace >= 7 && workspace <= 9
    readonly property bool anyBusy: exporter.busy || toolsClient.busy || localTools.busy || localDownload.busy || localPdf.busy || localQr.busy || localImages.busy || localReframe.busy
    onWorkspaceChanged: {
        if (workspace === 0) editorEnter.restart()
        else if (workspace === 10) imagesEnter.restart()
        else if (workspace === 11) reframeEnter.restart()
        else if (shareWorkspace) shareEnter.restart()
        else toolsEnter.restart()
    }
    onInspectorModeChanged: inspectorEnter.restart()
    function revealAfterIntro() {
        recoveryTimer.start()
        if (workspace === 0) editorEnter.restart()
        else if (workspace === 10) imagesEnter.restart()
        else if (workspace === 11) reframeEnter.restart()
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
            parts.push(items[i].url.toString() + ":" + items[i].inMs + ":" + items[i].outMs + ":" + items[i].volume + ":" + items[i].muted + ":" + items[i].speed)
        return parts.join("|") + JSON.stringify(editorProject.exportOptions())
    }
    // Files dropped or picked for the audio track go one after another from startMs.
    function addAudioFiles(urls, startMs) {
        var added = 0
        for (var i = 0; i < urls.length; i++) {
            var index = editorProject.addAudio(urls[i], startMs)
            if (index < 0) continue
            added++
            var item = editorProject.audioItems[index]
            startMs += item && item.lengthMs > 0 ? item.lengthMs : 0
        }
        if (added > 0) root.notice = added === 1 ? "Added to the audio track at " + root.timecode(editorProject.audioItems[editorProject.activeAudioIndex].startMs)
                                                  : added + " files added to the audio track"
    }
    function addMedia(url) {
        if (exporter.busy) {
            root.notice = "Wait for the export before adding a clip"
            return
        }
        if (editorProject.hasMedia ? editorProject.appendMedia(url) : editorProject.importMedia(url))
            root.notice = "Clip added to sequence"
    }
    // New text goes on at the given time and opens for typing on the video.
    function addTextAt(ms) {
        const index = editorProject.addText(ms)
        if (index >= 0) typeText(index)
    }
    function typeText(index) {
        if (player.playbackState === MediaPlayer.PlayingState) root.togglePlayback()
        editorProject.selectText(index)
        Qt.callLater(function() { captionLayer.edit(index) })
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
    readonly property real activeSpeed: {
        var clip = editorProject.clips[editorProject.activeClipIndex]
        return clip && clip.speed ? clip.speed : 1
    }
    // Only touched while playing: setting playbackRate during load stops the FFmpeg backend from showing video.
    onActiveSpeedChanged: applySpeed()
    function applySpeed() {
        if (player.playbackState !== MediaPlayer.PlayingState) return
        if (player.playbackRate !== activeSpeed) player.playbackRate = activeSpeed
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
        return clipStartMs(index) + offset / activeSpeed
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
        var source = Math.max(clip.inMs, Math.min(clip.outMs - 1, clip.inMs + (ms - start) * (clip.speed || 1)))
        if (index !== editorProject.activeClipIndex || pendingCueIndex >= 0) {
            pendingSourceMs = source
            if (index !== editorProject.activeClipIndex) editorProject.selectClip(index)
        } else requestSourceSeek(source)
    }
    // Frame rate of the active clip, for frame stepping; 30 when unknown.
    readonly property real frameRate: {
        var rate = Number(player.metaData.value(MediaMetaData.VideoFrameRate))
        return rate > 1 && rate < 1000 ? rate : 30
    }
    // Keyboard seeking: pauses, jumps by `deltaMs` on the sequence, like one scrub step.
    function nudgeSequence(deltaMs) {
        beginScrub(Math.max(0, Math.min(editorProject.sequenceDurationMs - 1, sequencePositionMs + deltaMs)))
        scrubbing = false
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
    readonly property var recentFiles: {
        try {
            var list = JSON.parse(Prefs.recentFiles)
            return Array.isArray(list) ? list.filter(function(item) { return item && item.url && editorProject.fileExists(item.url) }) : []
        } catch (error) { return [] }
    }
    function rememberRecent(url, isProject) {
        var key = url.toString()
        var list = recentFiles.filter(function(item) { return item.url !== key })
        list.unshift({ url: key, project: isProject })
        Prefs.recentFiles = JSON.stringify(list.slice(0, 6))
    }
    function applyOpen(url, isProject) {
        var opened = isProject ? editorProject.openProject(url) : editorProject.importMedia(url)
        if (opened) {
            root.rememberRecent(url, isProject)
            exporter.resetResult()
            root.playerError = ""
            root.notice = isProject ? "Project opened" : "Media imported"
            root.uploadFile = ""
        }
    }
    // Close the project and let go of its media, so the files can be moved or deleted.
    function closeEditing() {
        if (exporter.busy) {
            root.notice = "Finish or cancel the export before closing the project"
            return
        }
        // Work that was just exported is done: only unexported edits ask first.
        if (editorProject.dirty && editState() !== exportedClips) closeDialog.open()
        else applyClose()
    }
    // The sequence as it was when the last export finished.
    property string exportedClips: ""
    Connections {
        target: exporter
        function onChanged() {
            if (!exporter.busy && exporter.outputUrl.toString().length > 0 && !exporter.errorText)
                root.exportedClips = root.editState()
        }
    }
    function applyClose() {
        player.stop()
        editorProject.closeProject()
        exporter.resetResult()
        exportedClips = ""
        root.playerError = ""
        root.notice = "Project closed · its files are free to move or delete"
    }
    // Files from Explorer's Kadron menu or the command line, batched per tool.
    function openWith(tool, urls) {
        if (!urls || urls.length === 0) return
        if (tool === "project") {
            workspace = 0
            requestOpen(urls[0], true)
        } else if (tool === "edit") {
            workspace = 0
            for (var i = 0; i < urls.length; i++) addMedia(urls[i])
        } else if (tool === "reframe") {
            workspace = 11
            if (!reframeArea.load(urls[0])) notice = localReframe.busy ? "Wait for the current reframe to finish" : "Reframe takes a video file"
        } else if (tool === "images") {
            workspace = 10
            imagesArea.addFiles(urls)
        } else if (tool === "pdf" || tool === "images-to-pdf") {
            workspace = 5
            toolsArea.setPdfMode(tool === "images-to-pdf" ? "images-to-pdf" : urls.length > 1 ? "merge" : "edit")
            toolsArea.takePdfFiles(urls)
        } else {
            var sections = { audio: 2, compress: 3, gif: 4 }
            if (sections[tool] === undefined) return
            workspace = sections[tool]
            toolsArea.acceptDrop([urls[0]])
            if (urls.length > 1) notice = sectionTitle + " takes one file at a time · opened " + decodeURIComponent(urls[0].toString().split("/").pop())
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

    Component.onCompleted: {
        syncRangeFields()
        if (!startupIntroActive) recoveryTimer.start()
    }
    Timer { id: recoveryTimer; interval: 700; onTriggered: root.offerRecovery() }
    function stopAllWork() {
        exporter.cancel()
        toolsClient.cancel()
        localTools.cancel()
        localDownload.cancel()
        localPdf.cancel()
        localQr.cancel()
        localImages.cancel()
        localReframe.cancel()
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
    // Set when the close should really quit rather than hide to the tray.
    property bool quitting: false
    readonly property bool trayAvailable: typeof trayIcon !== "undefined" && trayIcon.supported
    function quitApp() {
        quitting = true
        if (!visible) show()
        close()
    }
    function showFromTray() {
        if (!visible) show()
        else if (visibility === Window.Minimized) showNormal()
        raise()
        requestActivate()
    }
    function hideToTray() {
        if (player.playbackState === MediaPlayer.PlayingState) player.pause()
        hide()
        if (!Prefs.trayHintShown && Prefs.notifications) {
            Prefs.trayHintShown = true
            trayIcon.showMessage("Kadron is still running", "Click the tray icon to open it again. You can change this in Settings.")
        }
    }
    Binding { target: root.trayAvailable ? trayIcon : null; property: "visible"; value: Prefs.closeToTray }
    Binding { target: root.trayAvailable ? trayIcon : null; property: "dark"; value: Theme.dark }
    // Long jobs show on the taskbar button; one ending in the background flashes
    // it and raises a Windows notification (unless turned off in Settings)
    // whose click opens the result.
    readonly property int jobProgress: exporter.busy ? exporter.progress
        : localDownload.busy ? localDownload.progress
        : localTools.busy ? localTools.progress
        : localReframe.busy ? localReframe.progress
        : toolsClient.busy ? toolsClient.progress : -1
    readonly property string jobName: exporter.busy ? "Export" : localDownload.busy ? "Download"
        : localTools.busy ? "Conversion" : localReframe.busy ? "Reframe" : toolsClient.busy ? "Upload"
        : localPdf.busy ? "PDF" : localImages.busy ? "Images" : ""
    property string runningJob: ""
    property url notifiedFile: ""
    function jobOutput(name) {
        switch (name) {
        case "Export": return exporter.outputUrl
        case "Download": return localDownload.outputUrl
        case "Conversion": return localTools.outputUrl
        case "Reframe": return localReframe.outputUrl
        case "PDF": return localPdf.outputUrl
        case "Images": return localImages.outputFolder
        }
        return ""
    }
    onJobProgressChanged: taskbar.setProgress(root, jobProgress)
    onJobNameChanged: {
        if (jobName) {
            runningJob = jobName
            return
        }
        var finished = runningJob
        runningJob = ""
        if (!finished || root.active) return
        // A queued download follows at once: one notice when the queue is done.
        if (finished === "Download" && localDownload.queue.length > 0) return
        var error = editorProject.errorText || exporter.errorText || toolsClient.errorText || localTools.errorText
            || localDownload.errorText || localPdf.errorText || localImages.errorText || localReframe.errorText
        if (root.visible) taskbar.flash(root)
        if (!root.trayAvailable || !Prefs.notifications) return
        var output = error ? "" : jobOutput(finished)
        notifiedFile = output && editorProject.fileExists(output) ? output : ""
        var name = notifiedFile.toString() ? decodeURIComponent(notifiedFile.toString().split("/").pop()) : ""
        trayIcon.showMessage(finished + (error ? " failed" : " finished"),
                             error || (name ? name + "\nClick to open it." : root.notice || "Open Kadron to see the result."))
    }
    Connections {
        target: root.trayAvailable ? trayIcon : null
        function onActivated() { root.showFromTray() }
        function onMessageClicked() {
            if (root.notifiedFile.toString() && editorProject.fileExists(root.notifiedFile)) Qt.openUrlExternally(root.notifiedFile)
            else root.showFromTray()
            root.notifiedFile = ""
        }
        function onQuitRequested() { root.quitApp() }
    }
    onClosing: function(event) {
        if (forceClose) return
        event.accepted = false
        const quit = quitting
        quitting = false
        if (!quit && trayAvailable && Prefs.closeToTray) {
            hideToTray()
            return
        }
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
        function onSilenceRemoved(parts, removedMs) {
            root.notice = removedMs > 0 ? "Removed " + (removedMs / 1000).toFixed(1) + " s of silence · " + parts + (parts === 1 ? " part" : " parts") + " left"
                                        : "No silence long enough to cut"
        }
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
    Shortcut { sequence: "Ctrl+,"; onActivated: settingsDialog.visible ? settingsDialog.close() : settingsDialog.open() }
    Shortcut { sequences: ["Ctrl+P", "Ctrl+Shift+P"]; onActivated: commandPalette.visible ? commandPalette.close() : commandPalette.show() }
    Shortcut { sequence: "Ctrl+W"; enabled: root.workspace === 0 && editorProject.hasMedia && !root.dialogOpen; onActivated: root.closeEditing() }
    // Frame steps, J/K/L and one-second jumps; the timeline keeps its own arrows while focused.
    readonly property bool keyboardSeek: workspace === 0 && editorProject.hasMedia && !dialogOpen && !exporter.busy
    Shortcut { sequence: ","; enabled: root.keyboardSeek; autoRepeat: true; onActivated: root.nudgeSequence(-1000 / root.frameRate) }
    Shortcut { sequence: "."; enabled: root.keyboardSeek; autoRepeat: true; onActivated: root.nudgeSequence(1000 / root.frameRate) }
    Shortcut { sequence: "Shift+Left"; enabled: root.keyboardSeek && !sequenceTimeline.activeFocus; autoRepeat: true; onActivated: root.nudgeSequence(-1000) }
    Shortcut { sequence: "Shift+Right"; enabled: root.keyboardSeek && !sequenceTimeline.activeFocus; autoRepeat: true; onActivated: root.nudgeSequence(1000) }
    Shortcut {
        sequence: "J"
        enabled: root.keyboardSeek
        autoRepeat: true
        onActivated: {
            var resume = player.playbackState === MediaPlayer.PlayingState
            root.nudgeSequence(-5000)
            if (resume) root.togglePlayback()
        }
    }
    Shortcut { sequence: "K"; enabled: root.keyboardSeek && player.playbackState === MediaPlayer.PlayingState; onActivated: root.togglePlayback() }
    Shortcut { sequence: "L"; enabled: root.keyboardSeek && player.playbackState !== MediaPlayer.PlayingState; onActivated: root.togglePlayback() }
    Shortcut { sequence: "Ctrl+Shift+S"; enabled: root.keyboardSeek; onActivated: root.saveFrame() }
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
    // The preview frame as a full-size picture, named after the clip and the moment.
    function saveFrame() {
        if (!editorProject.hasMedia) return
        var name = decodeURIComponent(editorProject.mediaUrl.toString().replace(/^.*\//, "").replace(/\.[^.]*$/, ""))
        frameDialog.sourceMs = player.position
        frameDialog.selectedFile = StandardPaths.writableLocation(StandardPaths.PicturesLocation) + "/" + name + " " + root.timecode(root.sequencePositionMs).replace(/:/g, "-") + ".png"
        frameDialog.open()
    }
    FileDialog {
        id: frameDialog
        property real sourceMs: 0
        title: "Save frame"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "png"
        nameFilters: ["PNG image (*.png)", "JPEG image (*.jpg)"]
        onAccepted: editorProject.saveFrame(sourceMs, selectedFile)
    }
    Connections {
        target: editorProject
        function onFrameSaved(file, error) {
            root.notice = error ? error : "Frame saved · " + decodeURIComponent(file.toString().replace(/^.*\//, ""))
        }
    }
    FileDialog {
        id: saveDialog
        title: "Save Kadron project"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "kadr"
        nameFilters: ["Kadron project (*.kadr)"]
        onAccepted: {
            if (editorProject.saveProject(selectedFile)) {
                root.rememberRecent(selectedFile, true)
                root.notice = "Project saved"
                if (root.closeAfterSave) root.fadeAndClose()
                else if (root.closeAfterSaveProject) root.applyClose()
            }
            root.closeAfterSave = false
            root.closeAfterSaveProject = false
        }
        onRejected: { root.closeAfterSave = false; root.closeAfterSaveProject = false }
    }
    FileDialog {
        id: exportDialog
        title: "Export MP4"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "mp4"
        nameFilters: ["MP4 video (*.mp4)"]
        onAccepted: {
            var options = editorProject.exportOptions()
            options.preset = Prefs.exportPreset
            options.loudnorm = Prefs.exportLoudnorm
            // A single clip with nothing added is a plain trim, or a lossless cut.
            if (exportSheet.losslessCut && !editorProject.mixed)
                exporter.start(editorProject.mediaUrl, selectedFile, editorProject.inMs, editorProject.outMs, { copy: true })
            else if (editorProject.mixed) exporter.startSequence(editorProject.clips, selectedFile, options)
            else exporter.start(editorProject.mediaUrl, selectedFile, editorProject.inMs, editorProject.outMs, options)
        }
    }

    SettingsDialog {
        id: settingsDialog
        objectName: "settingsDialog"
        onTutorialRequested: tutorial.start()
        onUpdateRequested: updateCard.act()
    }

    Tutorial {
        id: tutorial
        objectName: "tutorial"
        onPageRequested: function(page) { root.workspace = page; root.inspectorMode = 0 }
    }

    CommandPalette {
        id: commandPalette
        objectName: "commandPalette"
        source: root.paletteCommands
    }
    function paletteCommands() {
        var editing = editorProject.hasMedia && !exporter.busy
        var commands = [
            { title: "Open project…", group: "File", run: function() { openDialog.open() } },
            { title: "Import media…", group: "File", keys: "Ctrl+O", run: function() { mediaDialog.open() } },
            { title: "Save project", group: "File", keys: "Ctrl+S", enabled: editorProject.hasMedia, run: root.saveProject },
            { title: "Export MP4…", group: "File", enabled: editorProject.canExport && !exporter.busy && exporter.available, run: function() { root.workspace = 0; exportSheet.open() } },
            { title: "Close project", group: "File", keys: "Ctrl+W", enabled: editorProject.hasMedia, run: root.closeEditing },
            { title: "Settings", group: "App", keys: "Ctrl+,", run: function() { settingsDialog.open() } },
            { title: "Show the tutorial", group: "App", run: function() { tutorial.start() } },
            { title: "About Kadron", group: "App", run: function() { settingsDialog.show(3) } }
        ]
        var pages = ["Editor", "Download", "Audio", "Compress", "GIF Studio", "PDF Tools", "QR Code", "Clips", "Drop", "Shortener", "Images", "Reframe"]
        for (var i = 0; i < pages.length; ++i)
            commands.push({ title: "Go to " + pages[i], group: "Page", run: (function(page) { return function() { root.workspace = page } })(i) })
        var edit = [
            ["Play / pause", "Space", root.togglePlayback],
            ["Add clip…", "", function() { addClipDialog.open() }],
            ["Split at playhead", "Ctrl+K", function() { editorProject.splitAt(player.position) }],
            ["Mark in", "I", function() { editorProject.setInMs(player.position) }],
            ["Mark out", "O", function() { editorProject.setOutMs(player.position) }],
            ["Undo", "Ctrl+Z", function() { editorProject.undo() }],
            ["Redo", "Ctrl+Y", function() { editorProject.redo() }],
            ["Save frame as image…", "Ctrl+Shift+S", root.saveFrame],
            ["Remove silence from clip", "", function() { editorProject.removeSilence(editorProject.activeClipIndex) }],
            ["Previous / next frame", ", .", null],
            ["Jump one second", "Shift+← →", null],
            ["Back 5 s / pause / play", "J K L", null]
        ]
        for (var e = 0; e < edit.length; ++e)
            commands.push({ title: edit[e][0], group: "Editor", keys: edit[e][1], enabled: editing,
                            run: edit[e][2] ? (function(action) { return function() { root.workspace = 0; action() } })(edit[e][2]) : null })
        for (var r = 0; r < root.recentFiles.length; ++r) {
            var recent = root.recentFiles[r]
            var name = decodeURIComponent(recent.url.toString().split("/").pop())
            commands.push({ title: name, group: "Recent", run: (function(item) { return function() { root.workspace = 0; root.requestOpen(item.url, item.project) } })(recent) })
        }
        return commands
    }

    StudioDialog {
        id: exportSheet
        objectName: "exportSheet"
        property bool losslessCut: false
        readonly property var presets: [
            ["source", "Source", "Original size and frame rate"],
            ["1080p60", "1080p60", "Full HD, up to 60 fps"],
            ["discord", "Discord", "Under 10 MB, 720p"],
            ["vertical", "Vertical", "1080×1920 for Shorts and Reels"]
        ]
        readonly property int discordKbps: exporter.discordVideoKbps(editorProject.sequenceDurationMs)
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
                enabled: !exportSheet.losslessCut
                opacity: enabled ? 1 : 0.45
                Repeater {
                    model: exportSheet.presets
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
                visible: Prefs.exportPreset === "discord" && !exportSheet.losslessCut
                text: exportSheet.discordKbps < 400 ? "Long for 10 MB: about " + exportSheet.discordKbps + " kbit/s, expect a soft picture."
                                                    : "About " + exportSheet.discordKbps + " kbit/s for " + root.timecode(editorProject.sequenceDurationMs) + "."
                color: exportSheet.discordKbps < 400 ? Theme.warning : Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            },
            ToolCheck {
                text: "Even out loudness (-16 LUFS)"
                enabled: !exportSheet.losslessCut
                checked: Prefs.exportLoudnorm
                onToggled: Prefs.exportLoudnorm = checked
            },
            ToolCheck {
                visible: !editorProject.mixed
                text: "Fast lossless cut: no re-encode, starts at the nearest keyframe"
                checked: exportSheet.losslessCut
                onToggled: exportSheet.losslessCut = checked
            }
        ]
        EditorButton {
            text: "Choose file…"
            primary: true
            onClicked: { exportSheet.close(); exportDialog.open() }
        }
        EditorButton { text: "Cancel"; subtle: true; onClicked: exportSheet.close() }
    }
    FileDialog {
        id: musicDialog
        title: "Add to the audio track"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Audio files (*.mp3 *.wav *.flac *.m4a *.aac *.ogg *.opus)", "All files (*)"]
        onAccepted: root.addAudioFiles(selectedFiles, root.audioAddMs)
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
        id: recoveryDialog
        objectName: "recoveryDialog"
        heading: "Restore unsaved work?"
        message: "Kadron closed before " + (root.recovery.name || "a project") + " was saved. A copy from " + (root.recovery.savedAt || "earlier")
                 + " has " + (root.recovery.clipCount || 0) + (root.recovery.clipCount === 1 ? " clip." : " clips.")
        iconName: "undo"
        EditorButton {
            text: "Restore"
            iconName: "undo"
            primary: true
            onClicked: {
                recoveryDialog.close()
                root.workspace = 0
                if (editorProject.restoreRecovery()) root.notice = "Unsaved work restored · save it to keep it"
            }
        }
        EditorButton {
            text: "Discard"
            danger: true
            onClicked: {
                recoveryDialog.close()
                editorProject.discardRecovery()
            }
        }
    }

    StudioDialog {
        id: closeDialog
        objectName: "closeDialog"
        heading: "Close this project?"
        message: "It has unsaved changes. Save them first or close without saving."
        iconName: "close"
        warning: true
        EditorButton {
            text: "Save and close"
            primary: true
            onClicked: {
                closeDialog.close()
                if (editorProject.projectUrl.toString()) {
                    if (editorProject.saveProject()) root.applyClose()
                } else {
                    root.closeAfterSaveProject = true
                    saveDialog.open()
                }
            }
        }
        EditorButton { text: "Close without saving"; danger: true; onClicked: { closeDialog.close(); root.applyClose() } }
        EditorButton { text: "Keep editing"; subtle: true; onClicked: closeDialog.close() }
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
        audioOutput: AudioOutput { volume: editorVolume.effectiveVolume * root.clipGain * (editorProject.transition === "fade" ? 1 - root.transitionDim : 1) }
        videoOutput: videoOutput
        onPlaybackStateChanged: { root.applySpeed(); root.syncMusic() }
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

    // Audio track preview: follows the sequence; ducking is approximated by
    // lowering it whenever the active clip has sound.
    MediaPlayer {
        id: audioPlayerA
        objectName: "musicPlayer"
        source: root.slotItem(0) ? root.slotItem(0).url : ""
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia) root.syncMusic()
        audioOutput: AudioOutput { volume: editorVolume.effectiveVolume * root.audioGain(0) }
    }
    MediaPlayer {
        id: audioPlayerB
        source: root.slotItem(1) ? root.slotItem(1).url : ""
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia) root.syncMusic()
        audioOutput: AudioOutput { volume: editorVolume.effectiveVolume * root.audioGain(1) }
    }
    Timer {
        interval: 250
        repeat: true
        running: editorProject.audioCount > 0 && root.workspace === 0
        onTriggered: root.syncMusic()
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
                readonly property Item target: [navEditor, navDownload, navAudio, navCompress, navGif, navPdf, navQr, navClips, navDrop, navShortener, navImages, navReframe][root.workspace] || null
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
                Item { Layout.preferredHeight: root.height < 820 ? 10 : 23 }
                Text { text: "WORKSPACE"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2; Layout.leftMargin: 13; Layout.bottomMargin: 7 }
                NavItem { id: navEditor; Layout.fillWidth: true; title: "Editor"; iconName: "edit"; active: root.workspace === 0 && root.inspectorMode === 0; onClicked: { root.workspace = 0; root.inspectorMode = 0 } }
                NavItem { id: navDownload; Layout.fillWidth: true; title: "Download"; iconName: "download"; active: root.workspace === 1; onClicked: root.workspace = 1 }
                NavItem { id: navAudio; Layout.fillWidth: true; title: "Audio"; iconName: "audio"; active: root.workspace === 2; onClicked: root.workspace = 2 }
                NavItem { id: navCompress; Layout.fillWidth: true; title: "Compress"; iconName: "compress"; active: root.workspace === 3; onClicked: root.workspace = 3 }
                NavItem { id: navGif; Layout.fillWidth: true; title: "GIF Studio"; iconName: "gif"; active: root.workspace === 4; onClicked: root.workspace = 4 }
                NavItem { id: navReframe; objectName: "navReframe"; Layout.fillWidth: true; title: "Reframe"; iconName: "reframe"; active: root.workspace === 11; onClicked: root.workspace = 11 }
                NavItem { id: navImages; objectName: "navImages"; Layout.fillWidth: true; title: "Images"; iconName: "image"; active: root.workspace === 10; onClicked: root.workspace = 10 }
                Item { Layout.preferredHeight: root.height < 820 ? 12 : 20 }
                Text { text: "UTILITIES"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2; Layout.leftMargin: 13; Layout.bottomMargin: 7 }
                NavItem { id: navPdf; Layout.fillWidth: true; title: "PDF Tools"; iconName: "pdf"; active: root.workspace === 5; onClicked: root.workspace = 5 }
                NavItem { id: navQr; Layout.fillWidth: true; title: "QR Code"; iconName: "qr"; active: root.workspace === 6; onClicked: root.workspace = 6 }
                Item { Layout.preferredHeight: root.height < 820 ? 12 : 20 }
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
                    // Everything else in the sidebar stays put; the card shrinks
                    // to one row when the full one would push Settings off screen.
                    compact: navColumn.implicitHeight - implicitHeight + fullHeight > navColumn.height
                    onRestartRequested: root.quitApp()
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    Layout.leftMargin: 4
                    spacing: 8
                    // Settings, with the running version beside it (click the version to look for an update).
                    Rectangle {
                        id: settingsButton
                        objectName: "settingsButton"
                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Theme.radiusSmall
                        color: settingsMouse.containsMouse || settingsDialog.visible ? Theme.hover : Theme.hoverClear
                        Accessible.role: Accessible.Button
                        Accessible.name: "Settings"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 5
                            spacing: 9
                            ToolIcon { name: "sliders"; tint: settingsMouse.containsMouse || settingsDialog.visible ? Theme.text : Theme.textMuted }
                            Text { text: "Settings"; color: settingsMouse.containsMouse || settingsDialog.visible ? Theme.text : Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true }
                        }
                        MouseArea {
                            id: settingsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: settingsDialog.open()
                        }
                        ToolTip.visible: settingsMouse.containsMouse
                        ToolTip.delay: 600
                        ToolTip.text: "Settings  Ctrl+,"
                    }
                    Text {
                        objectName: "versionLink"
                        Layout.rightMargin: 6
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
                    Layout.minimumWidth: 0
                    spacing: 2
                    Text { text: root.workspace === 0 && root.inspectorMode === 1 ? "Publish" : root.sectionTitle; color: Theme.text; font.pixelSize: 18; font.weight: Font.DemiBold }
                    // The open file, with a close button beside it like a document tab.
                    Row {
                        width: parent.width
                        spacing: 4
                        Text {
                            id: headerSubtitle
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, parent.width - (closeProjectButton.visible ? closeProjectButton.width + 4 : 0))
                            text: root.workspace === 0 ? (editorProject.hasMedia ? editorProject.mediaName : "Create a project or import media") : root.shareWorkspace ? "Connected tools · your server" : "Private processing · on this device"
                            color: Theme.textMuted
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                        ToolButton {
                            id: closeProjectButton
                            objectName: "closeProjectButton"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.workspace === 0 && editorProject.hasMedia
                            enabled: !exporter.busy
                            implicitWidth: 18
                            implicitHeight: 18
                            padding: 0
                            onClicked: root.closeEditing()
                            Accessible.name: "Close project"
                            ToolTip.visible: hovered
                            ToolTip.delay: 400
                            ToolTip.text: "Close project (Ctrl+W)"
                            contentItem: ToolIcon { name: "close"; strokeWidth: 1.8; tint: closeProjectButton.hovered ? Theme.text : Theme.textFaint }
                            background: Rectangle { radius: 5; color: closeProjectButton.hovered ? Theme.hover : Theme.hoverClear }
                        }
                    }
                }
                Rectangle { visible: root.workspace === 0 && editorProject.dirty; width: 7; height: 7; radius: 4; color: Theme.warning }
                Text { visible: root.workspace === 0 && editorProject.dirty; text: "Unsaved"; color: Theme.warning; font.pixelSize: 11; Layout.rightMargin: 6 }
                // File actions as one group, so only Export stands out.
                Rectangle {
                    visible: root.workspace === 0
                    implicitWidth: fileActions.implicitWidth + 2
                    implicitHeight: 38
                    radius: Theme.radius
                    color: Theme.control
                    border.width: 1
                    border.color: Theme.lineStrong
                    Row {
                        id: fileActions
                        anchors.centerIn: parent
                        Repeater {
                            model: [["Open", "folder"], ["Import", "plus"], ["Save", "save"]]
                            delegate: Row {
                                required property var modelData
                                required property int index
                                Rectangle { visible: index > 0; width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: Theme.lineStrong }
                                ToolButton {
                                    id: fileAction
                                    implicitHeight: 36
                                    leftPadding: 14
                                    rightPadding: 15
                                    enabled: modelData[0] !== "Save" || editorProject.hasMedia
                                    onClicked: {
                                        if (modelData[0] === "Open") openDialog.open()
                                        else if (modelData[0] === "Import") mediaDialog.open()
                                        else root.saveProject()
                                    }
                                    contentItem: Row {
                                        spacing: 7
                                        ToolIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 15; height: 15
                                            name: fileAction.modelData[1]
                                            tint: !fileAction.enabled ? Theme.textDisabled : fileAction.hovered ? Theme.text : Theme.textMuted
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: fileAction.modelData[0]
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                            color: fileAction.enabled ? Theme.text : Theme.textDisabled
                                        }
                                    }
                                    background: Rectangle {
                                        color: fileAction.down ? Theme.pressed : fileAction.hovered ? Theme.hover : Theme.hoverClear
                                        radius: Theme.radius - 1
                                        Behavior on color { ColorAnimation { duration: Theme.fadeFast } }
                                    }
                                    readonly property var modelData: parent.modelData
                                }
                            }
                        }
                    }
                }
                EditorButton { text: "Export MP4"; visible: root.workspace === 0; primary: true; enabled: editorProject.canExport && !exporter.busy && exporter.available; onClicked: exportSheet.open() }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        }

        RevealAnimation { id: editorEnter; target: editorArea; shift: editorShift }
        RevealAnimation { id: toolsEnter; target: toolsArea; shift: toolsShift }
        RevealAnimation { id: shareEnter; target: shareArea; shift: shareShift }
        RevealAnimation { id: imagesEnter; target: imagesArea; shift: imagesShift }
        RevealAnimation { id: reframeEnter; target: reframeArea; shift: reframeShift }
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
                    Rectangle {
                        objectName: "transitionDim"
                        visible: player.hasVideo && root.transitionDim > 0
                        x: videoOutput.x + videoOutput.contentRect.x
                        y: videoOutput.y + videoOutput.contentRect.y
                        width: videoOutput.contentRect.width
                        height: videoOutput.contentRect.height
                        color: "black"
                        opacity: root.transitionDim
                    }
                    // Captions, laid out like the export draws them; drag one to place it.
                    TextOverlayLayer {
                        id: captionLayer
                        objectName: "captionLayer"
                        visible: player.hasVideo
                        x: videoOutput.x + videoOutput.contentRect.x
                        y: videoOutput.y + videoOutput.contentRect.y
                        width: videoOutput.contentRect.width
                        height: videoOutput.contentRect.height
                        texts: editorProject.textItems
                        timeMs: root.sequencePositionMs
                        selectedIndex: editorProject.activeTextIndex
                        draftSize: captionStyle.draftSize
                        editable: !exporter.busy
                        onPicked: function(index) { editorProject.selectText(index) }
                        onMoved: function(index, x, y) { editorProject.setTextStyle(index, { x: x, y: y }) }
                        onEdited: function(index, text) { editorProject.setTextContent(index, text) }
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
                        // Recent projects and media, one click to pick up where you left off.
                        Column {
                            objectName: "recentList"
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: !editorProject.hasMedia && root.recentFiles.length > 0
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
                                model: root.recentFiles.slice(0, 5)
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
                                        onClicked: root.requestOpen(recentRow.modelData.url, recentRow.modelData.project)
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
                        EditorButton {
                            objectName: "saveFrameButton"
                            subtle: true
                            iconName: "camera"
                            enabled: editorProject.hasMedia
                            onClicked: root.saveFrame()
                            ToolTip.visible: hovered
                            ToolTip.delay: 600
                            ToolTip.text: "Save this frame as an image  Ctrl+Shift+S"
                        }
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
                    // Always shown when the settings run past the bottom, so it is
                    // clear there is more below.
                    ScrollBar.vertical: ScrollBar {
                        width: 7
                        policy: inspectorScroll.contentHeight > inspectorScroll.availableHeight + 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                        contentItem: Rectangle { implicitWidth: 5; radius: 2; color: Theme.scrollThumb }
                    }
                    ColumnLayout {
                    width: inspectorScroll.availableWidth - 7
                    spacing: 11
                    Text { text: root.inspectorMode !== 0 ? "Publish & share" : root.activeText ? "Text settings" : "Clip settings"; color: Theme.text; font.pixelSize: 16; font.weight: Font.DemiBold }
                    Text { text: root.inspectorMode !== 0 ? "Send only when you choose to" : root.activeText ? "Click beside the text or Done to go back" : "Adjust the active clip"; color: Theme.textMuted; font.pixelSize: 11 }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.topMargin: 5; Layout.bottomMargin: 5 }

                    ColumnLayout {
                        visible: root.inspectorMode === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10
                        // A selected text takes the panel; the clip settings come back
                        // when it is let go.
                        ColumnLayout {
                            visible: root.activeText === null
                            Layout.fillWidth: true
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
                                Text { text: root.timecode((editorProject.outMs - editorProject.inMs) / root.activeSpeed); color: Theme.accentSoft; font.pixelSize: 17; font.weight: Font.DemiBold }
                            }
                            EditorButton {
                                Layout.fillWidth: true
                                text: "Split at playhead  Ctrl+K"
                                enabled: editorProject.hasMedia && !exporter.busy && player.position > editorProject.inMs + 100 && player.position < editorProject.outMs - 100
                                onClicked: editorProject.splitAt(player.position)
                            }

                            // Clip volume.
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Clip volume"; color: Theme.textMuted; font.pixelSize: 11; Layout.fillWidth: true }
                                    Text {
                                        objectName: "clipVolumeLabel"
                                        text: !root.activeClip ? "" : root.activeClip.muted ? "Muted" : Math.round((root.clipVolumeDrag >= 0 ? root.clipVolumeDrag : root.activeClip.volume) * 100) + "%"
                                        color: root.activeClip && root.activeClip.muted ? Theme.warning : Theme.text
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    EditorButton {
                                        objectName: "clipMuteButton"
                                        iconName: root.activeClip && root.activeClip.muted ? "mute" : "volume"
                                        subtle: true
                                        enabled: editorProject.hasMedia && !exporter.busy
                                        onClicked: editorProject.setClipMuted(editorProject.activeClipIndex, !root.activeClip.muted)
                                        ToolTip.visible: hovered
                                        ToolTip.delay: 500
                                        ToolTip.text: root.activeClip && root.activeClip.muted ? "Unmute this clip" : "Mute this clip"
                                    }
                                    ToolSlider {
                                        objectName: "clipVolumeSlider"
                                        Layout.fillWidth: true
                                        from: 0
                                        to: 2
                                        stepSize: 0.05
                                        enabled: editorProject.hasMedia && !exporter.busy
                                        value: root.activeClip ? root.activeClip.volume : 1
                                        opacity: root.activeClip && root.activeClip.muted ? 0.5 : 1
                                        onMoved: {
                                            if (pressed) root.clipVolumeDrag = value
                                            else editorProject.setClipVolume(editorProject.activeClipIndex, value)
                                        }
                                        onPressedChanged: {
                                            if (pressed || root.clipVolumeDrag < 0) return
                                            editorProject.setClipVolume(editorProject.activeClipIndex, root.clipVolumeDrag)
                                            root.clipVolumeDrag = -1
                                        }
                                    }
                                }
                            }

                            // Clip speed.
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 4
                                Text { text: "Speed"; color: Theme.textMuted; font.pixelSize: 11 }
                                SegmentedControl {
                                    Layout.fillWidth: true
                                    namePrefix: "clipSpeed"
                                    options: [0.5, 1, 1.5, 2].map(function(speed) {
                                        return { label: speed + "×", value: speed, glyph: speed > 1 ? "bolt" : "", bolts: speed >= 2 ? 2 : 1 }
                                    })
                                    current: root.activeSpeed
                                    enabled: editorProject.hasMedia && !exporter.busy
                                    onActivated: function(speed) { editorProject.setClipSpeed(editorProject.activeClipIndex, speed) }
                                }
                            }
                            EditorButton {
                                objectName: "removeSilenceButton"
                                Layout.fillWidth: true
                                text: editorProject.findingSilence ? "Listening for silence…" : "Remove silence"
                                iconName: "audio"
                                subtle: true
                                enabled: editorProject.hasMedia && !exporter.busy && !editorProject.findingSilence && !(root.activeClip && root.activeClip.muted)
                                onClicked: editorProject.removeSilence(editorProject.activeClipIndex)
                                ToolTip.visible: hovered
                                ToolTip.delay: 500
                                ToolTip.text: "Cut parts quieter than -35 dB lasting over 0.6 s. Undo brings them back."
                            }

                            // How clips meet.
                            ColumnLayout {
                                visible: editorProject.clipCount > 1
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.bottomMargin: 4 }
                                Text { text: "Between clips"; color: Theme.textMuted; font.pixelSize: 11 }
                                ToolCombo {
                                    objectName: "transitionCombo"
                                    Layout.fillWidth: true
                                    enabled: !exporter.busy
                                    textRole: "label"
                                    valueRole: "value"
                                    model: [{ value: "cut", label: "Cut" }, { value: "fade", label: "Fade through black" }, { value: "crossfade", label: "Crossfade" }]
                                    currentIndex: ["cut", "fade", "crossfade"].indexOf(editorProject.transition)
                                    onActivated: editorProject.setTransition(currentValue)
                                }
                                RowLayout {
                                    visible: editorProject.transition !== "cut"
                                    Layout.fillWidth: true
                                    spacing: 8
                                    ToolSlider {
                                        objectName: "transitionSlider"
                                        Layout.fillWidth: true
                                        from: 200
                                        to: 2000
                                        stepSize: 100
                                        enabled: !exporter.busy
                                        value: editorProject.transitionMs
                                        onMoved: {
                                            if (pressed) root.transitionDrag = value
                                            else editorProject.setTransitionMs(value)
                                        }
                                        onPressedChanged: {
                                            if (pressed || root.transitionDrag < 0) return
                                            editorProject.setTransitionMs(root.transitionDrag)
                                            root.transitionDrag = -1
                                        }
                                    }
                                    Text {
                                        text: ((root.transitionDrag >= 0 ? root.transitionDrag : editorProject.transitionMs) / 1000).toFixed(1) + " s"
                                        color: Theme.text
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        Layout.preferredWidth: 34
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }

                            // Audio track: music and sounds placed on the sequence.
                            ColumnLayout {
                                visible: editorProject.hasMedia
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.bottomMargin: 4 }
                                Text { text: "Audio track"; color: Theme.textMuted; font.pixelSize: 11 }
                                EditorButton {
                                    objectName: "addMusicButton"
                                    Layout.fillWidth: true
                                    text: "Add audio at playhead…"
                                    iconName: "music"
                                    enabled: !exporter.busy
                                    onClicked: {
                                        root.audioAddMs = root.sequencePositionMs
                                        musicDialog.open()
                                    }
                                }
                                RowLayout {
                                    visible: root.activeAudio !== null
                                    Layout.fillWidth: true
                                    spacing: 4
                                    ToolIcon { name: "music"; tint: Theme.accent; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                                    Text {
                                        objectName: "musicName"
                                        text: root.activeAudio ? root.activeAudio.name : ""
                                        color: Theme.text
                                        font.pixelSize: 12
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 4
                                    }
                                    EditorButton {
                                        objectName: "removeMusicButton"
                                        iconName: "close"
                                        subtle: true
                                        enabled: !exporter.busy
                                        onClicked: editorProject.removeAudio(editorProject.activeAudioIndex)
                                        ToolTip.visible: hovered
                                        ToolTip.delay: 500
                                        ToolTip.text: "Remove from the audio track (Delete)"
                                    }
                                }
                                Text {
                                    visible: root.activeAudio !== null
                                    text: root.activeAudio ? "From " + root.timecode(root.activeAudio.startMs) + " for " + root.timecode(root.activeAudio.lengthMs) : ""
                                    color: Theme.textFaint
                                    font.pixelSize: 11
                                    // Fill and wrap, so the text never widens the panel.
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                                RowLayout {
                                    visible: root.activeAudio !== null
                                    Layout.fillWidth: true
                                    spacing: 8
                                    ToolSlider {
                                        objectName: "musicVolumeSlider"
                                        Layout.fillWidth: true
                                        from: 0
                                        to: 2
                                        stepSize: 0.05
                                        enabled: !exporter.busy
                                        value: root.activeAudio ? root.activeAudio.volume : 0.5
                                        onMoved: {
                                            if (pressed) root.audioVolumeDrag = value
                                            else editorProject.setAudioVolume(editorProject.activeAudioIndex, value)
                                        }
                                        onPressedChanged: {
                                            if (pressed || root.audioVolumeDrag < 0) return
                                            editorProject.setAudioVolume(editorProject.activeAudioIndex, root.audioVolumeDrag)
                                            root.audioVolumeDrag = -1
                                        }
                                    }
                                    Text {
                                        text: root.activeAudio ? Math.round((root.audioVolumeDrag >= 0 ? root.audioVolumeDrag : root.activeAudio.volume) * 100) + "%" : ""
                                        color: Theme.text
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        Layout.preferredWidth: 34
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                                Text {
                                    visible: root.activeAudio !== null
                                    text: root.activeAudio ? "Fade in " + (root.activeAudio.fadeInMs / 1000).toFixed(1) + " s · fade out " + (root.activeAudio.fadeOutMs / 1000).toFixed(1) + " s"
                                                             + (root.activeAudio.fadeInMs + root.activeAudio.fadeOutMs === 0 ? " · drag the dots at the top corners" : "") : ""
                                    color: Theme.textFaint
                                    font.pixelSize: 11
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                                ToolCheck {
                                    objectName: "musicDuckCheck"
                                    visible: editorProject.audioCount > 0
                                    text: "Quieter while someone speaks"
                                    enabled: !exporter.busy
                                    checked: editorProject.musicDuck
                                    onToggled: editorProject.setMusicDuck(checked)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: editorProject.audioCount === 0
                                          ? "Drop music or sounds on the audio track under the clips, or add them here."
                                          : "Drag items on the audio track to move them and their edges to trim. Sound past the end of the video fades out."
                                    wrapMode: Text.WordWrap
                                    color: Theme.textFaint
                                    font.pixelSize: 10
                                }
                            }
                        }

                        // Text track: captions drawn over the video.
                        ColumnLayout {
                            visible: editorProject.hasMedia
                            Layout.fillWidth: true
                            spacing: 6
                            Rectangle { visible: root.activeText === null; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line; Layout.bottomMargin: 4 }
                            Text { text: "Text on video"; color: Theme.textMuted; font.pixelSize: 11 }
                            EditorButton {
                                objectName: "addTextButton"
                                visible: root.activeText === null
                                Layout.fillWidth: true
                                text: "Add text at playhead"
                                iconName: "plus"
                                enabled: !exporter.busy && editorProject.sequenceDurationMs >= 200
                                onClicked: root.addTextAt(root.sequencePositionMs)
                            }
                            TextArea {
                                id: captionField
                                objectName: "captionField"
                                visible: root.activeText !== null
                                Layout.fillWidth: true
                                enabled: !exporter.busy
                                wrapMode: TextEdit.Wrap
                                color: Theme.text
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.accentInk
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                padding: 9
                                background: Rectangle {
                                    radius: 8
                                    color: Theme.field
                                    border.width: captionField.activeFocus ? 2 : 1
                                    border.color: captionField.activeFocus ? Theme.accent : Theme.lineStrong
                                }
                                // Follows the selected caption until the user types.
                                readonly property string savedText: root.activeText ? root.activeText.text : ""
                                onSavedTextChanged: if (text !== savedText) text = savedText
                                Component.onCompleted: text = savedText
                                // Typed characters go into the text, not to the J/K/L/Space shortcuts.
                                Keys.onShortcutOverride: function(event) {
                                    event.accepted = event.text.length > 0 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))
                                }
                                // Enter keeps the text, Shift+Enter starts a new line.
                                Keys.onPressed: function(event) {
                                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                        event.accepted = true
                                        editingFinished()
                                        sequenceTimeline.forceActiveFocus()
                                    }
                                }
                                onEditingFinished: {
                                    if (!root.activeText) return
                                    if (!editorProject.setTextContent(editorProject.activeTextIndex, text)) text = savedText
                                }
                            }
                            TextStyleEditor {
                                id: captionStyle
                                visible: root.activeText !== null
                                Layout.fillWidth: true
                                enabled: !exporter.busy
                                item: root.activeText
                                onChangeRequested: function(changes) { editorProject.setTextStyle(editorProject.activeTextIndex, changes) }
                            }
                            RowLayout {
                                visible: root.activeText !== null
                                Layout.fillWidth: true
                                spacing: 6
                                EditorButton {
                                    objectName: "removeTextButton"
                                    Layout.fillWidth: true
                                    text: "Remove text"
                                    iconName: "close"
                                    subtle: true
                                    enabled: !exporter.busy
                                    onClicked: editorProject.removeText(editorProject.activeTextIndex)
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 500
                                    ToolTip.text: "Remove the text (Delete on the timeline)"
                                }
                                EditorButton {
                                    objectName: "doneTextButton"
                                    Layout.fillWidth: true
                                    text: "Done"
                                    onClicked: editorProject.selectText(-1)
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.activeText
                                      ? "Shown from " + root.timecode(root.activeText.startMs) + " for " + root.timecode(root.activeText.lengthMs) + ". Drag it on the picture to place it, on the text track to retime it."
                                      : editorProject.textItems.length === 0
                                        ? "Titles and captions, burnt into the export. Double-click the text track to add one."
                                        : "Click a caption on the text track to edit it."
                                wrapMode: Text.WordWrap
                                color: Theme.textFaint
                                font.pixelSize: 10
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
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
            Layout.preferredHeight: 274
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
                    Text { text: editorProject.hasMedia ? "Drag edges to trim, drag clips to reorder, drop audio on the track below, Ctrl + wheel to zoom" : "No clip loaded"; color: Theme.textFaint; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                    EditorButton { iconName: "undo"; subtle: true; enabled: editorProject.canUndo && !exporter.busy; onClicked: editorProject.undo(); ToolTip.visible: hovered; ToolTip.text: "Undo (Ctrl+Z)" }
                    EditorButton { iconName: "redo"; subtle: true; enabled: editorProject.canRedo && !exporter.busy; onClicked: editorProject.redo(); ToolTip.visible: hovered; ToolTip.text: "Redo (Ctrl+Shift+Z)" }
                    EditorButton { text: "Add clip"; iconName: "plus"; enabled: !exporter.busy; onClicked: addClipDialog.open() }
                    EditorButton {
                        objectName: "timelineTextButton"
                        text: "Text"
                        iconName: "edit"
                        enabled: editorProject.hasMedia && !exporter.busy && editorProject.sequenceDurationMs >= 200
                        onClicked: root.addTextAt(root.sequencePositionMs)
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: "Add text at the playhead and type it on the video"
                    }
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
                    transition: editorProject.transition
                    audioItems: editorProject.audioItems
                    audioIndex: editorProject.activeAudioIndex
                    onAudioSelectRequested: function(index) { editorProject.selectAudio(index) }
                    onAudioPlaceRequested: function(index, startMs, inMs, outMs) { editorProject.setAudioPlacement(index, startMs, inMs, outMs) }
                    onAudioFadeRequested: function(index, fadeInMs, fadeOutMs) { editorProject.setAudioFades(index, fadeInMs, fadeOutMs) }
                    onAudioRemoveRequested: function(index) { editorProject.removeAudio(index) }
                    onAudioSplitRequested: function(index, atMs) { editorProject.splitAudio(index, Math.round(atMs)) }
                    onAudioAddRequested: function(startMs) {
                        root.audioAddMs = startMs
                        musicDialog.open()
                    }
                    onAudioDropped: function(urls, startMs) { root.addAudioFiles(urls, startMs) }
                    textItems: editorProject.textItems
                    textIndex: editorProject.activeTextIndex
                    onTextSelectRequested: function(index) { editorProject.selectText(index) }
                    onTextPlaceRequested: function(index, startMs, endMs) { editorProject.setTextPlacement(index, startMs, endMs) }
                    onTextRemoveRequested: function(index) { editorProject.removeText(index) }
                    onTextSplitRequested: function(index, atMs) { editorProject.splitText(index, Math.round(atMs)) }
                    onTextDuplicateRequested: function(index) { editorProject.duplicateText(index) }
                    onTextAddRequested: function(startMs) { root.addTextAt(startMs) }
                    onTextEditRequested: function(index) { root.typeText(index) }
                    onScrubRequested: function(ms) { root.beginScrub(ms) }
                    onScrubFinished: root.scrubbing = false
                    onSelectRequested: function(index) {
                        root.sequencePlaying = false
                        root.sequenceAdvancing = false
                        editorProject.selectAudio(-1)
                        editorProject.selectText(-1)
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
            onOpenInEditor: function(fileUrl) {
                root.workspace = 0
                root.requestOpen(fileUrl, false)
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

        ReframeWorkspace {
            id: reframeArea
            transform: Translate { id: reframeShift }
            visible: root.workspace === 11
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
                Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: editorProject.errorText || exporter.errorText || toolsClient.errorText || localTools.errorText || localDownload.errorText || localPdf.errorText || localQr.errorText || localImages.errorText || localReframe.errorText ? Theme.danger : root.anyBusy ? Theme.warning : Theme.accent }
                Text {
                    text: editorProject.errorText || exporter.errorText || toolsClient.errorText || localTools.errorText || localDownload.errorText || localPdf.errorText || localQr.errorText || localImages.errorText || localReframe.errorText || (exporter.busy ? exporter.stage + " " + exporter.progress + "%" : localTools.busy ? localTools.stage + " " + localTools.progress + "%" : localDownload.busy ? localDownload.stage + " " + localDownload.progress + "%" : localPdf.busy ? localPdf.stage : localQr.busy ? localQr.stage : localImages.busy ? localImages.stage : localReframe.busy ? localReframe.stage + " " + localReframe.progress + "%" : toolsClient.busy ? toolsClient.stage + " " + toolsClient.progress + "%" : root.notice || "Ready")
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
