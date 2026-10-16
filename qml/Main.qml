import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import QtQuick.Effects
import QtCore
import Kadron.Backend

ApplicationWindow {
    id: root
    width: 1440
    height: 900
    minimumWidth: 1020
    minimumHeight: 680
    // With the startup intro, main.cpp shows the window when the intro hands off.
    visible: !Core.startupIntroActive
    color: Theme.window
    // Read by WindowChrome to paint the native Windows caption in the app's colors.
    readonly property color captionColor: Theme.rail
    readonly property color captionTextColor: Theme.textSoft
    readonly property bool captionDark: Theme.dark
    title: "Kadron" + (Core.editorProject.projectUrl.toString() ? " - " + Core.editorProject.projectUrl.toString().split("/").pop() : "")

    property bool forceClose: false
    property bool closeAfterSave: false
    readonly property bool dialogOpen: quitDialog.visible || replaceDialog.visible || closeDialog.visible || recoveryDialog.visible || exportSheet.visible || settingsDialog.visible || commandPalette.visible || markerNameDialog.visible
    property bool closeAfterSaveProject: false
    property string currentMediaKey: ""
    property int currentClipIndex: -1
    property string editSignature: ""
    property bool sequencePlaying: false
    // Source time where playing a pending trim stops, or -1.
    property real trimPlayStopMs: -1
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
    readonly property var activeClip: Core.editorProject.activeClipIndex >= 0 ? Core.editorProject.clips[Core.editorProject.activeClipIndex] || null : null
    property real clipVolumeDrag: -1
    // Freeze frames: a still clip is "played" by this clock while the player
    // rests on its frame.
    readonly property bool stillActive: !!activeClip && (activeClip.holdMs || 0) > 0
    property real stillClockMs: 0
    readonly property bool stillRunning: stillActive && sequencePlaying && pendingCueIndex < 0 && !scrubbing
    readonly property bool previewPlaying: player.playbackState === MediaPlayer.PlayingState || stillRunning
    Timer {
        id: stillTimer
        interval: 40
        repeat: true
        running: root.stillRunning
        property real last: 0
        onRunningChanged: last = Date.now()
        onTriggered: {
            var now = Date.now()
            root.stillClockMs = Math.min(root.activeClip ? root.activeClip.holdMs : 0, root.stillClockMs + now - last)
            last = now
            root.syncMusic()
            if (root.activeClip && root.stillClockMs >= root.activeClip.holdMs) {
                if (Core.editorProject.activeClipIndex + 1 >= Core.editorProject.clipCount) root.sequencePlaying = false
                else root.advanceSequence()
            }
        }
    }
    // Rotation, crop and colour of the active clip as the preview shows them;
    // colour follows a slider while it is dragged.
    property bool cropEditing: false
    property int cropRevision: 0
    property var lookDrag: null
    readonly property var clipLook: {
        var clip = activeClip
        if (!clip) return { rotation: 0, x: 0, y: 0, w: 1, h: 1, brightness: 0, contrast: 0, saturation: 0 }
        var colour = lookDrag || clip
        return { rotation: clip.rotation || 0, x: clip.cropX || 0, y: clip.cropY || 0, w: clip.cropWidth || 1, h: clip.cropHeight || 1,
                 brightness: colour.brightness || 0, contrast: colour.contrast || 0, saturation: colour.saturation || 0 }
    }
    readonly property bool lookActive: player.hasVideo && (cropEditing || clipLook.rotation !== 0 || clipLook.x > 0 || clipLook.y > 0 || clipLook.w < 1 || clipLook.h < 1
                                                           || clipLook.brightness !== 0 || clipLook.contrast !== 0 || clipLook.saturation !== 0)
    // The crop in the source picture (0..1): it is drawn in the turned frame.
    readonly property var lookSourceCrop: {
        var l = clipLook
        var X = cropEditing ? 0 : l.x, Y = cropEditing ? 0 : l.y, W = cropEditing ? 1 : l.w, H = cropEditing ? 1 : l.h
        if (l.rotation === 90) return { u: Y, v: 1 - X - W, w: H, h: W }
        if (l.rotation === 180) return { u: 1 - X - W, v: 1 - Y - H, w: W, h: H }
        if (l.rotation === 270) return { u: 1 - Y - H, v: X, w: H, h: W }
        return { u: X, v: Y, w: W, h: H }
    }
    // Editor exports queued while another one runs, started one after another.
    property var exportQueue: []
    property bool exportQueueStarting: false
    property real transitionDrag: -1
    property real audioVolumeDrag: -1
    // The selected audio track item, and the one under the playhead for the preview.
    readonly property var activeText: Core.editorProject.activeTextIndex >= 0 ? Core.editorProject.textItems[Core.editorProject.activeTextIndex] || null : null
    readonly property var activeAudio:Core.editorProject.activeAudioIndex >= 0 ? Core.editorProject.audioItems[Core.editorProject.activeAudioIndex] || null : null
    // Two preview players, so two overlapping items are both heard. A slot
    // keeps its item while it plays on, so nothing reloads mid-sound.
    property var audioSlots: [-1, -1]
    function audioIndicesAt(ms) {
        var items = Core.editorProject.audioItems, found = []
        for (var i = items.length - 1; i >= 0; i--)
            if (ms >= items[i].startMs && ms < items[i].startMs + items[i].lengthMs) found.push(i)
        return found
    }
    function slotItem(slot) {
        var index = audioSlots[slot]
        return index >= 0 ? Core.editorProject.audioItems[index] || null : null
    }
    // Item volume shaped by its fades, and lowered under the clip's own sound.
    function audioGain(slot) {
        var item = slotItem(slot)
        if (!item) return 0
        var index = audioSlots[slot]
        var level = audioVolumeDrag >= 0 && index === Core.editorProject.activeAudioIndex ? audioVolumeDrag : item.volume
        var t = sequencePositionMs - item.startMs
        if (item.fadeInMs > 0 && t < item.fadeInMs) level *= Math.sin(Math.max(0, t) / item.fadeInMs * Math.PI / 2)
        var left = item.lengthMs - t
        if (item.fadeOutMs > 0 && left < item.fadeOutMs) level *= Math.sin(Math.max(0, left) / item.fadeOutMs * Math.PI / 2)
        return Math.min(1, level) * (Core.editorProject.musicDuck && clipGain > 0 ? 0.4 : 1)
    }
    // Where "Add audio" puts the chosen file on the sequence.
    property real audioAddMs: 0
    readonly property real clipGain: !activeClip ? 1 : activeClip.muted ? 0 : Math.min(1, clipVolumeDrag >= 0 ? clipVolumeDrag : activeClip.volume)
    // How dark the preview gets near a join: a fade through black goes all
    // the way, a crossfade is hinted with a light dip.
    readonly property real transitionDim: {
        var index = Core.editorProject.activeClipIndex
        if (Core.editorProject.transition === "cut" || Core.editorProject.clipCount < 2 || index < 0 || !activeClip) return 0
        var half = (transitionDrag >= 0 ? transitionDrag : Core.editorProject.transitionMs) / 2
        var position = sequencePositionMs - clipStartMs(index)
        var distance = Infinity
        if (index > 0) distance = Math.min(distance, position)
        if (index < Core.editorProject.clipCount - 1) distance = Math.min(distance, activeClip.lengthMs - position)
        if (distance >= half) return 0
        // Eased like the export (smoothstep).
        var level = Math.max(0, distance) / half
        var depth = 1 - level * level * (3 - 2 * level)
        return Core.editorProject.transition === "fade" ? depth : depth * 0.35
    }
    // Everything an export depends on, to tell when a result is stale.
    function editState() { return JSON.stringify([Core.editorProject.clips, Core.editorProject.exportOptions()]) }
    // Keeps the audio track preview in step with the sequence while it plays.
    function syncMusic() {
        var playing = player.playbackState === MediaPlayer.PlayingState || stillRunning || (sequencePlaying && sequenceAdvancing)
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
        recovery = Core.editorProject.recoveryInfo()
        if (recovery.name && !Core.editorProject.hasMedia) recoveryDialog.open()
        else if (recovery.name) Core.editorProject.discardRecovery()
        if (!Prefs.tutorialDone && !recoveryDialog.opened && !Core.editorProject.hasMedia) tutorial.start()
    }
    property int inspectorMode: 0
    property int workspace: 0
    property url uploadFile: ""
    property url pendingOpenUrl: ""
    property bool pendingIsProject: false
    readonly property string sectionTitle: ["Editor", "Download", "Audio", "Compress", "GIF Studio", "PDF Tools", "QR Code", "Clips", "Drop", "Shortener", "Images", "Reframe"][workspace]
    // Workspaces 7-9 publish to the Tools server; 10 (Images) and 11 (Reframe) are local like 1-6.
    readonly property bool shareWorkspace: workspace >= 7 && workspace <= 9
    readonly property bool anyBusy: Core.exporter.busy || Core.toolsClient.busy || Core.localTools.busy || Core.localDownload.busy || Core.localPdf.busy || Core.localQr.busy || Core.localImages.busy || Core.localReframe.busy
    onWorkspaceChanged: {
        if (workspace !== 0) previewFullscreen = false
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
        if (Core.editorProject.projectUrl.toString()) Core.editorProject.saveProject()
        else saveDialog.open()
    }
    function syncRangeFields() {
        clipInspector.syncRangeFields()
    }
    function publishSource() {
        return uploadFile.toString() ? uploadFile : Core.exporter.outputUrl
    }
    function sequenceSignature() {
        var parts = []
        var items = Core.editorProject.clips
        for (var i = 0; i < items.length; i++)
            parts.push(items[i].url.toString() + ":" + items[i].inMs + ":" + items[i].outMs + ":" + items[i].volume + ":" + items[i].muted + ":" + items[i].speed
                       + ":" + items[i].holdMs + ":" + items[i].rotation + ":" + items[i].cropX + ":" + items[i].cropY + ":" + items[i].cropWidth + ":" + items[i].cropHeight
                       + ":" + items[i].brightness + ":" + items[i].contrast + ":" + items[i].saturation)
        return parts.join("|") + JSON.stringify(Core.editorProject.exportOptions())
    }
    // Files dropped or picked for the audio track go one after another from startMs.
    function addAudioFiles(urls, startMs) {
        var added = 0
        for (var i = 0; i < urls.length; i++) {
            var index = Core.editorProject.addAudio(urls[i], startMs)
            if (index < 0) continue
            added++
            var item = Core.editorProject.audioItems[index]
            startMs += item && item.lengthMs > 0 ? item.lengthMs : 0
        }
        if (added > 0) root.notice = added === 1 ? "Added to the audio track at " + root.timecode(Core.editorProject.audioItems[Core.editorProject.activeAudioIndex].startMs)
                                                  : added + " files added to the audio track"
    }
    function addMedia(url) {
        if (Core.exporter.busy) {
            root.notice = "Wait for the export before adding a clip"
            return
        }
        if (Core.editorProject.hasMedia ? Core.editorProject.appendMedia(url) : Core.editorProject.importMedia(url))
            root.notice = "Clip added to sequence"
    }
    // New text goes on at the given time and opens for typing on the video.
    function addTextAt(ms) {
        const index = Core.editorProject.addText(ms)
        if (index >= 0) typeText(index)
    }
    function typeText(index) {
        if (root.previewPlaying) root.togglePlayback()
        Core.editorProject.selectText(index)
        Qt.callLater(function() { previewPane.editCaption(index) })
    }
    function togglePlayback() {
        if (stillActive) {
            if (player.playbackState === MediaPlayer.PlayingState) player.pause()
            sequenceAdvancing = false
            if (sequencePlaying) { sequencePlaying = false; return }
            if (stillClockMs >= activeClip.holdMs - 20) stillClockMs = 0
            sequencePlaying = true
            return
        }
        if (player.playbackState === MediaPlayer.PlayingState) {
            sequencePlaying = false
            sequenceAdvancing = false
            player.pause()
        }
        else {
            // Play runs on through the following clips, like the timeline reads.
            sequencePlaying = true
            sequenceAdvancing = false
            if (player.position < Core.editorProject.inMs || player.position >= Core.editorProject.outMs - 20)
                player.position = Core.editorProject.inMs
            player.play()
        }
    }
    readonly property real activeSpeed: {
        var clip = Core.editorProject.clips[Core.editorProject.activeClipIndex]
        return clip && clip.speed ? clip.speed : 1
    }
    // Only touched while playing: setting playbackRate during load stops the FFmpeg backend from showing video.
    onActiveSpeedChanged: applySpeed()
    function applySpeed() {
        if (player.playbackState !== MediaPlayer.PlayingState) return
        if (player.playbackRate !== activeSpeed) player.playbackRate = activeSpeed
    }
    function clipStartMs(index) {
        var items = Core.editorProject.clips, total = 0
        for (var i = 0; i < index && i < items.length; i++) total += Math.max(0, items[i].lengthMs)
        return total
    }
    readonly property real sequencePositionMs: {
        if (scrubbing) return scrubTargetMs
        var index = Core.editorProject.activeClipIndex
        if (index < 0) return 0
        if (stillActive) return clipStartMs(index) + Math.min(stillClockMs, activeClip.holdMs)
        var source = pendingCueIndex >= 0 && pendingSourceMs >= 0 ? pendingSourceMs : player.position
        var offset = Math.max(0, Math.min(Core.editorProject.outMs - Core.editorProject.inMs, source - Core.editorProject.inMs))
        return clipStartMs(index) + offset / activeSpeed
    }
    function seekSequence(ms) {
        var items = Core.editorProject.clips
        if (items.length === 0) return
        var start = 0, index = items.length - 1
        for (var i = 0; i < items.length; i++) {
            var length = Math.max(0, items[i].lengthMs)
            if (ms < start + length || i === items.length - 1) { index = i; break }
            start += length
        }
        var clip = items[index]
        var still = (clip.holdMs || 0) > 0
        var source = still ? clip.inMs : Math.max(clip.inMs, Math.min(clip.outMs - 1, clip.inMs + (ms - start) * (clip.speed || 1)))
        if (index !== Core.editorProject.activeClipIndex || pendingCueIndex >= 0) {
            pendingSourceMs = source
            if (index !== Core.editorProject.activeClipIndex) Core.editorProject.selectClip(index)
        } else requestSourceSeek(source)
        if (still) stillClockMs = Math.max(0, Math.min(clip.holdMs, ms - start))
    }
    // Frame rate of the active clip, for frame stepping; 30 when unknown.
    readonly property real frameRate: {
        var rate = Number(player.metaData.value(MediaMetaData.VideoFrameRate))
        return rate > 1 && rate < 1000 ? rate : 30
    }
    // Keyboard seeking: pauses, jumps by `deltaMs` on the sequence, like one scrub step.
    function nudgeSequence(deltaMs) {
        beginScrub(Math.max(0, Math.min(Core.editorProject.sequenceDurationMs - 1, sequencePositionMs + deltaMs)))
        endScrub()
    }
    // A seek made while playing carries on playing from the new spot once the
    // mouse lets go; dragging the playhead pauses in between.
    property bool scrubResume: false
    function endScrub() {
        scrubbing = false
        if (!scrubResume) return
        scrubResume = false
        if (pendingCueIndex >= 0) { sequencePlaying = true; return }
        if (!previewPlaying) togglePlayback()
    }
    function beginScrub(ms) {
        if (!scrubbing) scrubResume = previewPlaying
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
        pendingCueIndex = Core.editorProject.activeClipIndex
        Qt.callLater(function() { root.finishCue() })
    }
    function finishCue() {
        if (pendingCueIndex !== Core.editorProject.activeClipIndex || pendingCueIndex < 0) return
        if (player.source.toString() !== Core.editorProject.mediaUrl.toString()) return
        if (player.mediaStatus !== MediaPlayer.LoadedMedia && player.mediaStatus !== MediaPlayer.BufferedMedia) return
        pendingCueIndex = -1
        player.position = pendingSourceMs >= 0 ? pendingSourceMs : Core.editorProject.inMs
        pendingSourceMs = -1
        if (stillActive) player.pause()
        else if (sequencePlaying) player.play()
        sequenceAdvancing = false
    }
    function previewSequence() {
        if (!Core.editorProject.canExport) return
        sequencePlaying = true
        sequenceAdvancing = true
        if (Core.editorProject.activeClipIndex !== 0) Core.editorProject.selectClip(0)
        else cueActiveClip()
    }
    function stopSequence() {
        sequencePlaying = false
        sequenceAdvancing = false
        player.pause()
    }
    function advanceSequence() {
        if (!sequencePlaying || sequenceAdvancing) return
        if (Core.editorProject.activeClipIndex + 1 >= Core.editorProject.clipCount) {
            sequencePlaying = false
            player.pause()
            return
        }
        sequenceAdvancing = true
        Core.editorProject.selectClip(Core.editorProject.activeClipIndex + 1)
    }
    readonly property var recentFiles: {
        try {
            var list = JSON.parse(Prefs.recentFiles)
            return Array.isArray(list) ? list.filter(function(item) { return item && item.url && Core.editorProject.fileExists(item.url) }) : []
        } catch (error) { return [] }
    }
    function rememberRecent(url, isProject) {
        var key = url.toString()
        var list = recentFiles.filter(function(item) { return item.url !== key })
        list.unshift({ url: key, project: isProject })
        Prefs.recentFiles = JSON.stringify(list.slice(0, 6))
    }
    onRecentFilesChanged: Core.taskbar.setJumpList(recentFiles)
    function applyOpen(url, isProject) {
        var opened = isProject ? Core.editorProject.openProject(url) : Core.editorProject.importMedia(url)
        if (opened) {
            root.rememberRecent(url, isProject)
            Core.exporter.resetResult()
            root.playerError = ""
            root.notice = isProject ? "Project opened" : "Media imported"
            root.uploadFile = ""
        }
    }
    // Close the project and let go of its media, so the files can be moved or deleted.
    function closeEditing() {
        if (Core.exporter.busy) {
            root.notice = "Finish or cancel the export before closing the project"
            return
        }
        // Work that was just exported is done: only unexported edits ask first.
        if (Core.editorProject.dirty && editState() !== exportedClips) closeDialog.open()
        else applyClose()
    }
    // The sequence as it was when the last export finished.
    property string exportedClips: ""
    Connections {
        target: Core.exporter
        function onChanged() {
            if (!Core.exporter.busy && Core.exporter.outputUrl.toString().length > 0 && !Core.exporter.errorText)
                root.exportedClips = root.editState()
            if (Core.exporter.busy || root.exportQueueStarting || root.exportQueue.length === 0) return
            if (Core.exporter.errorText) {
                root.exportQueue = []
                root.notice = "Export failed · the queue was stopped"
            } else if (Core.exporter.outputUrl.toString().length > 0) {
                var next = root.exportQueue[0]
                root.exportQueue = root.exportQueue.slice(1)
                root.exportQueueStarting = true
                Qt.callLater(function() { root.exportQueueStarting = false; root.runExportJob(next) })
            }
        }
    }
    function applyClose() {
        player.stop()
        Core.editorProject.closeProject()
        Core.exporter.resetResult()
        exportedClips = ""
        root.playerError = ""
        root.notice = "Project closed · its files are free to move or delete"
    }
    // Files from Explorer's Kadron menu or the command line, batched per tool.
    function openWith(tool, urls) {
        // The jump list's tasks name only a tool.
        if (!urls || urls.length === 0) {
            var places = { edit: 0, download: 1, audio: 2, compress: 3, gif: 4, pdf: 5, images: 10, reframe: 11 }
            if (places[tool] !== undefined) workspace = places[tool]
            return
        }
        if (tool === "project") {
            workspace = 0
            requestOpen(urls[0], true)
        } else if (tool === "open") {
            workspace = 0
            requestOpen(urls[0], false)
        } else if (tool === "edit") {
            workspace = 0
            for (var i = 0; i < urls.length; i++) addMedia(urls[i])
        } else if (tool === "reframe") {
            workspace = 11
            if (!reframeArea.load(urls[0])) notice = Core.localReframe.busy ? "Wait for the current reframe to finish" : "Reframe takes a video file"
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
        if (Core.editorProject.dirty) {
            pendingOpenUrl = url
            pendingIsProject = isProject
            replaceDialog.open()
        } else applyOpen(url, isProject)
    }

    Component.onCompleted: {
        syncRangeFields()
        Core.taskbar.setJumpList(recentFiles)
        if (!Core.startupIntroActive) recoveryTimer.start()
    }
    Timer { id: recoveryTimer; interval: 700; onTriggered: root.offerRecovery() }
    function stopAllWork() {
        exportQueue = []
        Core.exporter.cancel()
        Core.toolsClient.cancel()
        Core.localTools.cancel()
        Core.localDownload.cancel()
        Core.localPdf.cancel()
        Core.localQr.cancel()
        Core.localImages.cancel()
        Core.localReframe.cancel()
    }
    // Every close fades the window out; the real close runs once the fade ends.
    function fadeAndClose() {
        stopAllWork()
        forceClose = true
        quitDialog.close()
        closeFade.start()
    }
    function saveAndClose() {
        if (Core.editorProject.projectUrl.toString()) {
            if (Core.editorProject.saveProject()) fadeAndClose()
        } else {
            closeAfterSave = true
            saveDialog.open()
        }
    }
    // Set when the close should really quit rather than hide to the tray.
    property bool quitting: false
    readonly property bool trayAvailable: typeof Core.trayIcon !== "undefined" && Core.trayIcon.supported
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
            Core.trayIcon.showMessage("Kadron is still running", "Click the tray icon to open it again. You can change this in Settings.")
        }
    }
    Binding { target: root.trayAvailable ? Core.trayIcon : null; property: "visible"; value: Prefs.closeToTray }
    Binding { target: root.trayAvailable ? Core.trayIcon : null; property: "dark"; value: Theme.dark }
    // Long jobs show on the taskbar button (a moving bar when the length is
    // unknown); one ending in the background flashes it and raises a Windows
    // notification (unless turned off in Settings) whose click opens the
    // result. A failure leaves the button red until Kadron is opened.
    readonly property int jobProgress: Core.exporter.busy ? Core.exporter.progress
        : Core.localDownload.busy ? Core.localDownload.progress
        : Core.localTools.busy ? Core.localTools.progress
        : Core.localReframe.busy ? Core.localReframe.progress
        : Core.toolsClient.busy ? Core.toolsClient.progress
        : Core.localImages.busy ? Core.localImages.progress
        : Core.localPdf.busy ? -2 : -1
    readonly property string jobName: Core.exporter.busy ? "Export" : Core.localDownload.busy ? "Download"
        : Core.localTools.busy ? "Conversion" : Core.localReframe.busy ? "Reframe" : Core.toolsClient.busy ? "Upload"
        : Core.localPdf.busy ? "PDF" : Core.localImages.busy ? "Images" : ""
    property string runningJob: ""
    property url notifiedFile: ""
    function jobOutput(name) {
        switch (name) {
        case "Export": return Core.exporter.outputUrl
        case "Download": return Core.localDownload.outputUrl
        case "Conversion": return Core.localTools.outputUrl
        case "Reframe": return Core.localReframe.outputUrl
        case "PDF": return Core.localPdf.outputUrl
        case "Images": return Core.localImages.outputFolder
        }
        return ""
    }
    onJobProgressChanged: Core.taskbar.setProgress(root, jobProgress)
    onActiveChanged: if (active && jobProgress === -1) Core.taskbar.setProgress(root, -1)
    onJobNameChanged: {
        if (jobName) {
            runningJob = jobName
            return
        }
        var finished = runningJob
        runningJob = ""
        if (!finished || root.active) return
        // A queued download follows at once: one notice when the queue is done.
        if (finished === "Download" && Core.localDownload.queue.length > 0) return
        var error = Core.editorProject.errorText || Core.exporter.errorText || Core.toolsClient.errorText || Core.localTools.errorText
            || Core.localDownload.errorText || Core.localPdf.errorText || Core.localImages.errorText || Core.localReframe.errorText
        if (error) Core.taskbar.setProgress(root, 100, true)
        if (root.visible) Core.taskbar.flash(root)
        if (!root.trayAvailable || !Prefs.notifications) return
        var output = error ? "" : jobOutput(finished)
        notifiedFile = output && Core.editorProject.fileExists(output) ? output : ""
        var name = notifiedFile.toString() ? decodeURIComponent(notifiedFile.toString().split("/").pop()) : ""
        Core.trayIcon.showMessage(finished + (error ? " failed" : " finished"),
                             error || (name ? name + "\nClick to open it." : root.notice || "Open Kadron to see the result."))
    }
    Connections {
        target: root.trayAvailable ? Core.trayIcon : null
        function onActivated() { root.showFromTray() }
        function onMessageClicked() {
            if (root.notifiedFile.toString() && Core.editorProject.fileExists(root.notifiedFile)) Qt.openUrlExternally(root.notifiedFile)
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
        if (Core.editorProject.dirty || root.anyBusy) quitDialog.open()
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
        target: Core.editorProject
        function onSilenceRemoved(parts, removedMs) {
            root.notice = removedMs > 0 ? "Removed " + (removedMs / 1000).toFixed(1) + " s of silence · " + parts + (parts === 1 ? " part" : " parts") + " left"
                                        : "No silence long enough to cut"
        }
        function onChanged() {
            root.syncRangeFields()
            var signature = root.sequenceSignature()
            if (signature !== root.editSignature) {
                root.editSignature = signature
                Core.exporter.resetResult()
            }
            if (root.currentClipIndex !== Core.editorProject.activeClipIndex) {
                root.currentClipIndex = Core.editorProject.activeClipIndex
                root.stillClockMs = 0
                root.cropEditing = false
                root.lookDrag = null
                if (!root.sequencePlaying) player.pause()
                root.cueActiveClip()
            }
            var mediaKey = Core.editorProject.mediaUrl.toString()
            if (mediaKey !== root.currentMediaKey) {
                root.currentMediaKey = mediaKey
            }
            if (Core.editorProject.hasMedia && Core.editorProject.durationMs > 0)
                Core.thumbnails.generate(Core.editorProject.mediaUrl, Core.editorProject.durationMs)
        }
    }

    Shortcut { sequence: StandardKey.Open; onActivated: mediaDialog.open() }
    Shortcut { sequence: StandardKey.Save; enabled: Core.editorProject.hasMedia; onActivated: root.saveProject() }
    Shortcut { sequence: "Space"; enabled: root.workspace === 0 && Core.editorProject.hasMedia; onActivated: root.togglePlayback() }
    Shortcut { sequence: "I"; enabled: root.workspace === 0 && Core.editorProject.hasMedia && !Core.exporter.busy; onActivated: Core.editorProject.setInMs(player.position) }
    Shortcut { sequence: "O"; enabled: root.workspace === 0 && Core.editorProject.hasMedia && !Core.exporter.busy; onActivated: Core.editorProject.setOutMs(player.position) }
    Shortcut { sequences: [StandardKey.Undo]; enabled: root.workspace === 0 && Core.editorProject.canUndo && !Core.exporter.busy; onActivated: Core.editorProject.undo() }
    Shortcut { sequences: [StandardKey.Redo, "Ctrl+Shift+Z"]; enabled: root.workspace === 0 && Core.editorProject.canRedo && !Core.exporter.busy; onActivated: Core.editorProject.redo() }
    Shortcut { sequence: "Ctrl+,"; onActivated: settingsDialog.visible ? settingsDialog.close() : settingsDialog.open() }
    Shortcut { sequence: "Ctrl+/"; onActivated: settingsDialog.visible && settingsDialog.section === 3 ? settingsDialog.close() : settingsDialog.show(3) }
    Shortcut { sequences: ["Ctrl+P", "Ctrl+Shift+P"]; onActivated: commandPalette.visible ? commandPalette.close() : commandPalette.show() }
    Shortcut { sequence: "Ctrl+W"; enabled: root.workspace === 0 && Core.editorProject.hasMedia && !root.dialogOpen; onActivated: root.closeEditing() }
    // Frame steps, J/K/L and one-second jumps; the timeline keeps its own arrows while focused.
    readonly property bool keyboardSeek: workspace === 0 && Core.editorProject.hasMedia && !dialogOpen && !Core.exporter.busy
    Shortcut { sequence: ","; enabled: root.keyboardSeek; autoRepeat: true; onActivated: root.nudgeSequence(-1000 / root.frameRate) }
    Shortcut { sequence: "."; enabled: root.keyboardSeek; autoRepeat: true; onActivated: root.nudgeSequence(1000 / root.frameRate) }
    Shortcut { sequence: "Shift+Left"; enabled: root.keyboardSeek && !timelinePanel.timeline.activeFocus; autoRepeat: true; onActivated: root.nudgeSequence(-1000) }
    Shortcut { sequence: "Shift+Right"; enabled: root.keyboardSeek && !timelinePanel.timeline.activeFocus; autoRepeat: true; onActivated: root.nudgeSequence(1000) }
    Shortcut {
        sequence: "J"
        enabled: root.keyboardSeek
        autoRepeat: true
        onActivated: {
            root.nudgeSequence(-5000)
        }
    }
    Shortcut { sequence: "K"; enabled: root.keyboardSeek && root.previewPlaying; onActivated: root.togglePlayback() }
    Shortcut { sequence: "L"; enabled: root.keyboardSeek && !root.previewPlaying; onActivated: root.togglePlayback() }
    Shortcut { sequence: "Ctrl+Shift+S"; enabled: root.keyboardSeek; onActivated: root.saveFrame() }
    Shortcut { sequence: "Ctrl+Shift+C"; enabled: root.keyboardSeek; onActivated: root.copyFrame() }
    // Markers: N drops or lifts one at the playhead, [ and ] jump between them.
    Shortcut { sequence: "N"; enabled: root.keyboardSeek; onActivated: root.toggleMarker() }
    Shortcut { sequence: "["; enabled: root.keyboardSeek && Core.editorProject.markers.length > 0; autoRepeat: true; onActivated: root.jumpMarker(-1) }
    Shortcut { sequence: "]"; enabled: root.keyboardSeek && Core.editorProject.markers.length > 0; autoRepeat: true; onActivated: root.jumpMarker(1) }
    // Preview sound: M mutes, Up and Down step the level unless a field or list has the keys.
    readonly property bool keyboardVolume: workspace === 0 && Core.editorProject.hasMedia && !dialogOpen
    readonly property bool arrowsFree: {
        var item = root.activeFocusItem
        return !item || item === timelinePanel.timeline || (item.cursorPosition === undefined && item.currentIndex === undefined && item.value === undefined)
    }
    Shortcut { sequence: "M"; enabled: root.keyboardVolume; onActivated: root.toggleMute() }
    Shortcut { sequence: "Up"; enabled: root.keyboardVolume && root.arrowsFree; autoRepeat: true; onActivated: root.stepVolume(0.05) }
    Shortcut { sequence: "Down"; enabled: root.keyboardVolume && root.arrowsFree; autoRepeat: true; onActivated: root.stepVolume(-0.05) }
    // Preview fills the screen: F or a double-click, Escape to come back.
    Shortcut { sequence: "F"; enabled: root.workspace === 0 && Core.editorProject.hasMedia && !root.dialogOpen; onActivated: root.previewFullscreen = !root.previewFullscreen }
    Shortcut { sequence: "Esc"; enabled: root.previewFullscreen; onActivated: root.previewFullscreen = false }
    function toggleMute() {
        if (Prefs.previewVolume <= 0.001) {
            Prefs.previewVolume = 0.7
            Prefs.previewMuted = false
        } else {
            Prefs.previewMuted = !Prefs.previewMuted
        }
        root.notice = Prefs.previewMuted ? "Preview muted" : "Preview volume " + Math.round(Prefs.previewVolume * 100) + "%"
    }
    function stepVolume(delta) {
        var level = Prefs.previewMuted ? 0 : Prefs.previewVolume
        Prefs.previewVolume = Math.max(0, Math.min(1, Math.round((level + delta) * 20) / 20))
        Prefs.previewMuted = false
        root.notice = "Preview volume " + Math.round(Prefs.previewVolume * 100) + "%"
    }
    function toggleMarker() {
        var count = Core.editorProject.markers.length
        if (!Core.editorProject.toggleMarker(Math.round(root.sequencePositionMs))) return
        root.notice = Core.editorProject.markers.length > count ? "Marker at " + root.timecode(root.sequencePositionMs) + " · [ and ] jump between markers" : "Marker removed"
    }
    // The stretch between the markers around ms: from the last one at or before
    // it (else the start) to the next one (else the end); null without markers.
    function markerRangeAt(ms) {
        var list = Core.editorProject.markers
        if (list.length === 0) return null
        var from = 0, to = Core.editorProject.sequenceDurationMs
        for (var i = 0; i < list.length; i++) {
            var mark = Number(list[i])
            if (mark <= ms + 40) from = mark
            else { to = mark; break }
        }
        return to - from >= 100 ? { startMs: from, endMs: to } : null
    }
    function jumpMarker(direction) {
        var list = Core.editorProject.markers, here = root.sequencePositionMs, target = -1
        for (var i = 0; i < list.length; i++) {
            var ms = Number(list[i])
            if (direction > 0 && ms > here + 40) { target = ms; break }
            if (direction < 0 && ms < here - 40) target = ms
        }
        if (target < 0) return
        root.beginScrub(target)
        root.endScrub()
    }
    Shortcut { sequence: "Ctrl+K"; enabled: root.workspace === 0 && Core.editorProject.hasMedia && !Core.exporter.busy; onActivated: Core.editorProject.splitAt(player.position) }

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
        if (!Core.editorProject.hasMedia) return
        var name = decodeURIComponent(Core.editorProject.mediaUrl.toString().replace(/^.*\//, "").replace(/\.[^.]*$/, ""))
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
        onAccepted: Core.editorProject.saveFrame(sourceMs, selectedFile)
    }
    // Fullscreen preview: the window goes fullscreen and the preview covers it.
    property bool previewFullscreen: false
    property int visibilityBeforeFullscreen: Window.Windowed
    onPreviewFullscreenChanged: {
        if (previewFullscreen) {
            visibilityBeforeFullscreen = visibility
            showFullScreen()
            fullscreenHint.restart()
        } else if (visibility === Window.FullScreen) {
            if (visibilityBeforeFullscreen === Window.Maximized) showMaximized()
            else showNormal()
        }
    }
    onVisibilityChanged: if (previewFullscreen && visibility !== Window.FullScreen && visibility !== Window.Hidden) previewFullscreen = false
    Item {
        id: fullscreenHost
        anchors.fill: parent
        z: 900
        visible: root.previewFullscreen
        Rectangle {
            id: fullscreenHintBox
            z: 10
            anchors.horizontalCenter: parent.horizontalCenter
            y: 24
            width: fullscreenHintText.implicitWidth + 28
            height: 32
            radius: 16
            color: "#cc000000"
            opacity: 0
            Text {
                id: fullscreenHintText
                anchors.centerIn: parent
                text: "Esc or F to exit fullscreen"
                color: "#e6ffffff"
                font.pixelSize: 12
            }
            SequentialAnimation {
                id: fullscreenHint
                NumberAnimation { target: fullscreenHintBox; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
                PauseAnimation { duration: 1600 }
                NumberAnimation { target: fullscreenHintBox; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InOutQuad }
            }
        }
    }
    // The preview frame onto the clipboard, through a temporary PNG.
    property string frameCopyTarget: ""
    function sameFile(a, b) {
        try { return decodeURIComponent(a) === decodeURIComponent(b) } catch (e) { return a === b }
    }
    function copyFrame() {
        if (!Core.editorProject.hasMedia) return
        var name = decodeURIComponent(Core.editorProject.mediaUrl.toString().replace(/^.*\//, "").replace(/\.[^.]*$/, ""))
        var target = StandardPaths.writableLocation(StandardPaths.TempLocation) + "/" + name + " " + root.timecode(root.sequencePositionMs).replace(/:/g, "-") + ".png"
        root.frameCopyTarget = target.toString()
        Core.editorProject.saveFrame(player.position, target)
    }
    Connections {
        target: Core.editorProject
        function onFrameSaved(file, error) {
            var copying = root.frameCopyTarget.length > 0 && root.sameFile(file.toString(), root.frameCopyTarget)
            root.frameCopyTarget = ""
            if (error) root.notice = error
            else if (copying) root.notice = Core.shellIntegration.copyFile(file) ? "Frame copied · paste it with Ctrl+V" : "Couldn't copy the frame"
            else root.notice = "Frame saved · " + decodeURIComponent(file.toString().replace(/^.*\//, ""))
        }
    }
    FileDialog {
        id: saveDialog
        title: "Save Kadron project"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "kadr"
        nameFilters: ["Kadron project (*.kadr)"]
        onAccepted: {
            if (Core.editorProject.saveProject(selectedFile)) {
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
            var job = root.exportJob(selectedFile)
            if (!Core.exporter.busy && !root.exportQueueStarting) { root.runExportJob(job); return }
            root.exportQueue = root.exportQueue.concat([job])
            root.notice = "Export queued · " + root.exportQueue.length + " waiting"
        }
    }
    // Everything an export needs, taken now, so a queued one keeps the choices
    // made when it was added.
    function exportJob(target) {
        var options = Core.editorProject.exportOptions()
        options.preset = Prefs.exportPreset
        options.loudnorm = Prefs.exportLoudnorm
        var range = exportSheet.range
        if (range) { options.rangeStartMs = range.startMs; options.rangeEndMs = range.endMs }
        var lossless = exportSheet.losslessCut && !Core.editorProject.mixed
        if (!lossless && Prefs.watermarkEnabled && Prefs.watermarkPath.length > 0) {
            if (Core.editorProject.fileExists(Prefs.watermarkPath))
                options.watermark = { path: Prefs.watermarkPath, corner: Prefs.watermarkCorner, opacity: Prefs.watermarkOpacity, size: Prefs.watermarkSize }
            else root.notice = "The logo from Settings is missing · exporting without it"
        }
        // A single clip with nothing added is a plain trim, or a lossless cut;
        // its timeline starts at the clip's in point.
        return { target: target, lossless: lossless, mixed: Core.editorProject.mixed, clips: Core.editorProject.clips, mediaUrl: Core.editorProject.mediaUrl,
                 inMs: range ? Core.editorProject.inMs + range.startMs : Core.editorProject.inMs,
                 outMs: range ? Core.editorProject.inMs + range.endMs : Core.editorProject.outMs, options: options }
    }
    // The one file a finished export was cut from, or "" when it mixed several.
    property url exportSourceUrl: ""
    function singleSource(job) {
        if (!job.mixed) return job.mediaUrl
        var first = job.clips.length > 0 ? job.clips[0].url.toString() : ""
        for (var i = 1; i < job.clips.length; i++) if (job.clips[i].url.toString() !== first) return ""
        return first
    }
    readonly property bool canReplaceSource: exportSourceUrl.toString().length > 0 && !Core.exporter.busy && !Core.exporter.errorText
                                             && Core.exporter.outputUrl.toString().length > 0 && Core.exporter.outputUrl.toString() !== exportSourceUrl.toString()
                                             && Core.editorProject.fileExists(exportSourceUrl) && Core.editorProject.fileExists(Core.exporter.outputUrl)
    // The player lets go of the file first, so Windows allows moving it.
    property bool releasingMedia: false
    function replaceSource() {
        var original = exportSourceUrl, replacement = Core.exporter.outputUrl
        stopSequence()
        releasingMedia = true
        replaceTimer.original = original
        replaceTimer.replacement = replacement
        replaceTimer.start()
    }
    Timer {
        id: replaceTimer
        property url original
        property url replacement
        interval: 400
        onTriggered: {
            var result = Core.shellIntegration.replaceFile(original, replacement)
            root.releasingMedia = false
            if (result.toString().length === 0) {
                root.notice = "Couldn't move the original to the Recycle Bin · it may be open in another app"
                return
            }
            root.exportSourceUrl = ""
            Core.editorProject.importMedia(result)
            root.notice = "Original replaced · " + decodeURIComponent(result.toString().replace(/^.*\//, "")) + " is open in the editor"
        }
    }
    function runExportJob(job) {
        exportSourceUrl = singleSource(job)
        if (job.lossless) Core.exporter.start(job.mediaUrl, job.target, job.inMs, job.outMs, { copy: true })
        else if (job.mixed) Core.exporter.startSequence(job.clips, job.target, job.options)
        else Core.exporter.start(job.mediaUrl, job.target, job.inMs, job.outMs, job.options)
    }
    function cancelExport() {
        var dropped = exportQueue.length
        exportQueue = []
        Core.exporter.cancel()
        if (dropped > 0) notice = "Export cancelled · " + dropped + (dropped === 1 ? " queued export dropped" : " queued exports dropped")
    }
    function copyChapters() {
        var list = Core.editorProject.chapterList()
        root.notice = Core.editorProject.markers.length > 0 && Core.shellIntegration.copyText(list)
                ? "Chapters copied · paste them into a YouTube description" : "Add markers first: each one starts a chapter"
    }
    function freezeFrame() {
        if (root.stillActive) return
        if (Core.editorProject.insertFreeze(Core.editorProject.activeClipIndex, player.position))
            root.notice = "Frame held for 2 s · set the length under Picture"
    }
    property int renamingMarker: -1
    function renameMarker(index) {
        var item = Core.editorProject.markerItems[index]
        if (!item) return
        renamingMarker = index
        markerNameField.text = item.name || ""
        markerNameDialog.open()
    }

    SettingsDialog {
        id: settingsDialog
        objectName: "settingsDialog"
        onTutorialRequested: tutorial.start()
        onUpdateRequested: sidebar.installUpdate()
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
        var editing = Core.editorProject.hasMedia && !Core.exporter.busy
        var commands = [
            { title: "Open project…", group: "File", run: function() { openDialog.open() } },
            { title: "Import media…", group: "File", keys: "Ctrl+O", run: function() { mediaDialog.open() } },
            { title: "Save project", group: "File", keys: "Ctrl+S", enabled: Core.editorProject.hasMedia, run: root.saveProject },
            { title: Core.exporter.busy ? "Queue another export…" : "Export MP4…", group: "File", enabled: Core.editorProject.canExport && Core.exporter.available, run: function() { root.workspace = 0; exportSheet.open() } },
            { title: "Copy chapters", group: "File", enabled: Core.editorProject.markers.length > 0, run: root.copyChapters },
            { title: "Import subtitles (SRT, VTT)…", group: "File", enabled: Core.editorProject.hasMedia && !Core.exporter.busy, run: function() { root.workspace = 0; subtitleImportDialog.open() } },
            { title: "Export subtitles as SRT…", group: "File", enabled: Core.editorProject.textItems.length > 0, run: function() { root.workspace = 0; subtitleExportDialog.open() } },
            { title: "Close project", group: "File", keys: "Ctrl+W", enabled: Core.editorProject.hasMedia, run: root.closeEditing },
            { title: "Settings", group: "App", keys: "Ctrl+,", run: function() { settingsDialog.open() } },
            { title: "Keyboard shortcuts", group: "App", keys: "Ctrl+/", run: function() { settingsDialog.show(3) } },
            { title: "Show the tutorial", group: "App", run: function() { tutorial.start() } },
            { title: "About Kadron", group: "App", run: function() { settingsDialog.show(4) } }
        ]
        var pages = ["Editor", "Download", "Audio", "Compress", "GIF Studio", "PDF Tools", "QR Code", "Clips", "Drop", "Shortener", "Images", "Reframe"]
        for (var i = 0; i < pages.length; ++i)
            commands.push({ title: "Go to " + pages[i], group: "Page", run: (function(page) { return function() { root.workspace = page } })(i) })
        var edit = [
            ["Play / pause", "Space", root.togglePlayback],
            ["Add clip…", "", function() { addClipDialog.open() }],
            ["Split at playhead", "Ctrl+K", function() { Core.editorProject.splitAt(player.position) }],
            ["Mark in", "I", function() { Core.editorProject.setInMs(player.position) }],
            ["Mark out", "O", function() { Core.editorProject.setOutMs(player.position) }],
            ["Undo", "Ctrl+Z", function() { Core.editorProject.undo() }],
            ["Redo", "Ctrl+Y", function() { Core.editorProject.redo() }],
            ["Save frame as image…", "Ctrl+Shift+S", root.saveFrame],
            ["Copy frame", "Ctrl+Shift+C", root.copyFrame],
            ["Add or remove marker", "N", root.toggleMarker],
            ["Previous marker", "[", function() { root.jumpMarker(-1) }],
            ["Next marker", "]", function() { root.jumpMarker(1) }],
            ["Clear markers", "", function() { Core.editorProject.clearMarkers() }],
            ["Freeze frame at playhead", "", root.freezeFrame],
            ["Rotate clip right", "", function() { Core.editorProject.setClipRotation(Core.editorProject.activeClipIndex, root.clipLook.rotation + 90) }],
            ["Crop clip", "", function() { root.cropEditing = true }],
            ["Fullscreen preview", "F", function() { root.previewFullscreen = true }],
            ["Mute preview", "M", root.toggleMute],
            ["Remove silence from clip", "", function() { Core.editorProject.removeSilence(Core.editorProject.activeClipIndex) }],
            ["Previous / next frame", ", .", null],
            ["Jump one second", "Shift+← →", null],
            ["Back 5 s / pause / play", "J K L", null],
            ["Preview volume", "↑ ↓", null]
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

    ExportSheet {
        id: exportSheet
        objectName: "exportSheet"
        app: root
        onChooseFile: exportDialog.open()
    }
    StudioDialog {
        id: replaceSourceDialog
        objectName: "replaceSourceDialog"
        heading: "Replace the original?"
        message: decodeURIComponent(root.exportSourceUrl.toString().replace(/^.*\//, "")) + " goes to the Recycle Bin and the export takes its name. "
                 + "The editor then opens the new file; your edits are already in it."
        iconName: "file"
        EditorButton { text: "Replace"; primary: true; onClicked: { replaceSourceDialog.close(); root.replaceSource() } }
        EditorButton { text: "Cancel"; subtle: true; onClicked: replaceSourceDialog.close() }
    }
    StudioDialog {
        id: markerNameDialog
        objectName: "markerNameDialog"
        heading: "Name the marker"
        message: "The name becomes the chapter title in exports and copied chapters."
        iconName: "marker"
        onOpened: { markerNameField.forceActiveFocus(); markerNameField.selectAll() }
        body: [
            EditorField {
                id: markerNameField
                objectName: "markerNameField"
                Layout.fillWidth: true
                placeholderText: "Chapter title"
                maximumLength: 80
                onAccepted: { Core.editorProject.setMarkerName(root.renamingMarker, text); markerNameDialog.close() }
            }
        ]
        EditorButton { text: "Save"; primary: true; onClicked: { Core.editorProject.setMarkerName(root.renamingMarker, markerNameField.text); markerNameDialog.close() } }
        EditorButton { text: "Cancel"; subtle: true; onClicked: markerNameDialog.close() }
    }
    FileDialog {
        id: subtitleImportDialog
        title: "Import subtitles"
        nameFilters: ["Subtitles (*.srt *.vtt)", "All files (*)"]
        onAccepted: {
            var count = Core.editorProject.importSubtitles(selectedFile, 0)
            if (count > 0) root.notice = count + (count === 1 ? " caption added" : " captions added") + " to the text track"
            else if (count === 0) root.notice = "No captions found in that file"
        }
    }
    FileDialog {
        id: subtitleExportDialog
        title: "Export subtitles"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "srt"
        nameFilters: ["SubRip subtitles (*.srt)"]
        onAccepted: if (Core.editorProject.exportSubtitles(selectedFile)) root.notice = "Subtitles saved · " + decodeURIComponent(selectedFile.toString().replace(/^.*\//, ""))
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
                if (Core.editorProject.restoreRecovery()) root.notice = "Unsaved work restored · save it to keep it"
            }
        }
        EditorButton {
            text: "Discard"
            danger: true
            onClicked: {
                recoveryDialog.close()
                Core.editorProject.discardRecovery()
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
                if (Core.editorProject.projectUrl.toString()) {
                    if (Core.editorProject.saveProject()) root.applyClose()
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
        heading: Core.editorProject.dirty ? "Save changes before closing?" : "Stop work and close?"
        message: root.anyBusy
                 ? (Core.editorProject.dirty ? "Your project has unsaved changes, and running work will stop. A server upload already submitted may continue processing."
                                        : "Running work will stop. A server upload already submitted may continue processing.")
                 : "Your project has unsaved changes. Save them now or close without saving."
        iconName: Core.editorProject.dirty ? "save" : "close"
        warning: !Core.editorProject.dirty
        EditorButton {
            visible: Core.editorProject.dirty
            text: "Save and close"
            iconName: "save"
            primary: true
            enabled: Core.editorProject.hasMedia
            onClicked: root.saveAndClose()
        }
        EditorButton {
            text: Core.editorProject.dirty ? "Don't save" : "Stop and close"
            danger: true
            subtle: Core.editorProject.dirty
            onClicked: root.fadeAndClose()
        }
        Item { Layout.fillWidth: true }
        EditorButton { text: "Keep working"; subtle: true; onClicked: quitDialog.close() }
    }

    // A seek is settled when the decoder delivers a frame, or after a short
    // fallback for audio-only media.
    Timer { id: seekSettle; interval: 90; onTriggered: root.settleSeek() }
    Connections {
        target: previewPane.videoOutput.videoSink
        function onVideoFrameChanged() { if (root.seekInFlight) root.settleSeek() }
    }

    MediaPlayer {
        id: player
        objectName: "editorPlayer"
        source: root.releasingMedia ? "" : Core.editorProject.mediaUrl
        audioOutput: AudioOutput { volume: editorVolume.effectiveVolume * root.clipGain * (Core.editorProject.transition === "fade" ? 1 - root.transitionDim : 1) }
        videoOutput: previewPane.videoOutput
        onPlaybackStateChanged: {
            if (playbackState !== MediaPlayer.PlayingState) root.trimPlayStopMs = -1
            root.applySpeed()
            root.syncMusic()
        }
        onDurationChanged: function(duration) { if (source.toString() === Core.editorProject.mediaUrl.toString()) Core.editorProject.setDurationMs(duration) }
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) root.finishCue()
        onPositionChanged: {
            if (playbackState === MediaPlayer.PlayingState && root.stillActive) pause()
            else if (root.trimPlayStopMs >= 0) { if (playbackState === MediaPlayer.PlayingState && position >= root.trimPlayStopMs) pause() }
            else if (playbackState === MediaPlayer.PlayingState && Core.editorProject.outMs > Core.editorProject.inMs && position >= Core.editorProject.outMs) {
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
        running: Core.editorProject.audioCount > 0 && root.workspace === 0
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

        Sidebar {
            id: sidebar
            app: root
            Layout.preferredWidth: 188
            Layout.fillHeight: true
            settingsOpen: settingsDialog.visible
            onOpenSettings: settingsDialog.open()
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
                            text: root.workspace === 0 ? (Core.editorProject.hasMedia ? Core.editorProject.mediaName : "Create a project or import media") : root.shareWorkspace ? "Connected tools · your server" : "Private processing · on this device"
                            color: Theme.textMuted
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                        ToolButton {
                            id: closeProjectButton
                            objectName: "closeProjectButton"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.workspace === 0 && Core.editorProject.hasMedia
                            enabled: !Core.exporter.busy
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
                Rectangle { visible: root.workspace === 0 && Core.editorProject.dirty; width: 7; height: 7; radius: 4; color: Theme.warning }
                Text { visible: root.workspace === 0 && Core.editorProject.dirty; text: "Unsaved"; color: Theme.warning; font.pixelSize: 11; Layout.rightMargin: 6 }
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
                                    enabled: modelData[0] !== "Save" || Core.editorProject.hasMedia
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
                EditorButton { text: Core.exporter.busy ? "Queue export" : "Export MP4"; visible: root.workspace === 0; primary: true; enabled: Core.editorProject.canExport && Core.exporter.available; onClicked: exportSheet.open() }
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
                // The preview moves into a full-window host while it fills the screen.
                Item {
                    id: previewSlot
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
                PreviewPane {
                    id: previewPane
                    app: root
                    mediaPlayer: player
                    parent: root.previewFullscreen ? fullscreenHost : previewSlot
                    anchors.fill: parent
                    captionDraftSize: clipInspector.captionDraftSize
                    onImportMedia: mediaDialog.open()
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
                        EditorButton { text: root.previewPlaying ? "Pause" : "Play"; iconName: root.previewPlaying ? "pause" : "play"; enabled: Core.editorProject.hasMedia; onClicked: root.togglePlayback() }
                        Text { text: root.timecode(root.sequencePositionMs); color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Text { text: "/ " + root.timecode(Core.editorProject.sequenceDurationMs); color: Theme.textMuted; font.pixelSize: 12 }
                        Item { Layout.fillWidth: true }
                        EditorButton {
                            objectName: "saveFrameButton"
                            subtle: true
                            iconName: "camera"
                            enabled: Core.editorProject.hasMedia
                            onClicked: root.saveFrame()
                            ToolTip.visible: hovered
                            ToolTip.delay: 600
                            ToolTip.text: "Save this frame as an image  Ctrl+Shift+S · copy it with Ctrl+Shift+C"
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
                    readonly property SoftBounds softBounds: SoftBounds { flickable: inspectorScroll.contentItem }
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

                    ClipInspector {
                        id: clipInspector
                        app: root
                        mediaPlayer: player
                        visible: root.inspectorMode === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        onChooseMusic: musicDialog.open()
                        onImportSubtitles: subtitleImportDialog.open()
                        onExportSubtitles: subtitleExportDialog.open()
                        onReplaceSource: replaceSourceDialog.open()
                        onTextDone: timelinePanel.timeline.forceActiveFocus()
                    }

                    PublishPanel {
                        visible: root.inspectorMode === 1
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        source: root.publishSource()
                        onChooseFile: uploadDialog.open()
                    }
                    }
                }
            }
        }

        TimelinePanel {
            id: timelinePanel
            app: root
            mediaPlayer: player
            visible: root.workspace === 0
            Layout.fillWidth: true
            Layout.preferredHeight: 274
            onAddClip: addClipDialog.open()
            onAddMusic: musicDialog.open()
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
            onFileDropped: function(fileUrl) { root.uploadFile = fileUrl }
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
                Rectangle { Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: Core.editorProject.errorText || Core.exporter.errorText || Core.toolsClient.errorText || Core.localTools.errorText || Core.localDownload.errorText || Core.localPdf.errorText || Core.localQr.errorText || Core.localImages.errorText || Core.localReframe.errorText ? Theme.danger : root.anyBusy ? Theme.warning : Theme.accent }
                Text {
                    text: Core.editorProject.errorText || Core.exporter.errorText || Core.toolsClient.errorText || Core.localTools.errorText || Core.localDownload.errorText || Core.localPdf.errorText || Core.localQr.errorText || Core.localImages.errorText || Core.localReframe.errorText || (Core.exporter.busy ? Core.exporter.stage + " " + Core.exporter.progress + "%" : Core.localTools.busy ? Core.localTools.stage + " " + Core.localTools.progress + "%" : Core.localDownload.busy ? Core.localDownload.stage + " " + Core.localDownload.progress + "%" : Core.localPdf.busy ? Core.localPdf.stage : Core.localQr.busy ? Core.localQr.stage : Core.localImages.busy ? Core.localImages.stage : Core.localReframe.busy ? Core.localReframe.stage + " " + Core.localReframe.progress + "%" : Core.toolsClient.busy ? Core.toolsClient.stage + " " + Core.toolsClient.progress + "%" : root.notice || "Ready")
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
