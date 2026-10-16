import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import QtCore

Item {
    id: toolsPage
    property int section: 1
    // What the section panels reach through `page`.
    property alias audioPlayer: audioPreview
    property alias gifPlayer: gifPreview
    property alias dropArea: pageDrop
    property alias sourcePicker: sourceDialog
    property alias compressFolderPicker: compressFolderDialog
    property alias pdfPicker: pdfDialog
    property alias pdfPageModel: pageModel
    // Audio, Compress and GIF each keep their own file.
    property var sources: ({})
    readonly property url sourceUrl: sources[section] || ""
    function setSource(url) {
        var next = Object.assign({}, sources)
        next[section] = url
        sources = next
        if (section === 3 && !compressRunning) compressBatch = []
    }
    // Compress takes several files at once: all of the first file's kind,
    // each saved next to the others in one folder with these settings.
    property var compressBatch: []
    property var compressQueue: []
    property string compressFolder: ""
    property int compressTotal: 0
    property int compressFailed: 0
    property bool compressRunning: false
    property bool compressStarting: false
    property string compressSummary: ""
    function takeCompressFiles(urls) {
        var media = /\.(mp4|mov|mkv|webm|avi|m4v|gif)$/i, images = /\.(jpe?g|png|webp|bmp|tiff?)$/i
        var list = []
        for (var i = 0; i < urls.length; i++) list.push(urls[i])
        var kind = images.test(list[0].toString()) ? images : media
        list = list.filter(function(url) { return kind.test(url.toString()) })
        if (list.length === 0) return
        setSource(list[0])
        compressBatch = list.length > 1 ? list : []
        compressSummary = ""
        compressPick = ""
    }
    function startCompressBatch(folder) {
        compressFolder = folder.toString()
        compressQueue = compressBatch.slice()
        compressTotal = compressQueue.length
        compressFailed = 0
        compressSummary = ""
        compressRunning = true
        resultSection = "compress-batch"
        compressNext()
    }
    function compressNext() {
        if (compressQueue.length === 0) {
            compressRunning = false
            var done = compressTotal - compressFailed
            compressSummary = done + " of " + compressTotal + " files compressed" + (compressFailed > 0 ? " · " + compressFailed + " failed" : "")
            return
        }
        var source = compressQueue[0]
        compressQueue = compressQueue.slice(1)
        var base = decodeURIComponent(source.toString().split("/").pop()).replace(/\.[^.]*$/, "")
        var target = compressFolder + "/" + encodeURIComponent(base + "-compressed") + "." + selectedFormat
        compressStarting = true
        if (!localTools.compress(source, target, selectedFormat, compressQuality, compressToSize ? compressMB : 0,
                                 compressWidth, compressPanel.noAudioBox.checked)) compressFailed++
        compressStarting = false
        if (!localTools.busy) Qt.callLater(compressNext)
    }
    function cancelCompressBatch() {
        compressQueue = []
        localTools.cancel()
    }
    Connections {
        target: localTools
        function onChanged() {
            if (!toolsPage.compressRunning || toolsPage.compressStarting || localTools.busy) return
            if (localTools.errorText) toolsPage.compressFailed++
            toolsPage.compressStarting = true
            Qt.callLater(function() { toolsPage.compressStarting = false; if (!localTools.busy) toolsPage.compressNext() })
        }
    }
    property var pdfFiles: []
    property string pdfMode: "edit"
    property bool pdfEdited: false
    property int pdfSelected: 0
    // Extract pages: the chosen 1-based pages, mirrored in the range field.
    property var splitPages: []
    readonly property bool pdfUsesBoard: pdfMode === "merge" || pdfMode === "images-to-pdf"
    ListModel { id: pageModel }
    onPdfFilesChanged: {
        if (pdfMode === "edit" || pdfMode === "split") loadPdfPages()
        else if (pdfMode === "merge") localPdf.loadCovers(pdfFiles)
        setSplitPages([])
    }
    function setSplitPages(pages) {
        splitPages = pages
        var range = localPdf.pagesToRange(pages)
        if (pdfPanel.pagesField.text !== range && !pdfPanel.pagesField.activeFocus) pdfPanel.pagesField.text = range
    }
    // Merge and Images to PDF add to the list; the other modes take one file.
    function takePdfFiles(urls) {
        if (!pdfUsesBoard) { pdfFiles = [urls[0]]; return }
        var next = pdfFiles.slice()
        var known = pdfFiles.map(function(u) { return u.toString() })
        for (var i = 0; i < urls.length; i++)
            if (known.indexOf(urls[i].toString()) < 0) { next.push(urls[i]); known.push(urls[i].toString()) }
        pdfFiles = next
    }
    function removePdfFile(index) {
        var next = pdfFiles.slice()
        next.splice(index, 1)
        pdfFiles = next
    }
    Connections {
        target: localPdf
        function onPagesChanged() { if (!localPdf.loadingPages) toolsPage.resetPages() }
        function onPagePreviewReady(page, image) { if (page === pagePreview.page) pagePreview.image = image }
    }
    Connections {
        target: pageModel
        function onDataChanged() { toolsPage.countSelected() }
        function onCountChanged() { toolsPage.countSelected() }
    }
    function setPdfMode(mode) {
        if (mode === pdfMode) return
        var keep = (mode === "images-to-pdf") === (pdfMode === "images-to-pdf") && mode !== "merge" && pdfMode !== "merge"
        pdfMode = mode
        if (!keep) pdfFiles = []
        else if (mode === "edit" || mode === "split") loadPdfPages()
    }
    function loadPdfPages() {
        if (pdfFiles.length === 0) localPdf.clearPages()
        else if (localPdf.pagesDocument.toString() !== pdfFiles[0].toString() || localPdf.pageImages.length === 0) localPdf.loadPages(pdfFiles[0])
    }
    function resetPages() {
        pageModel.clear()
        for (var i = 0; i < localPdf.pageImages.length; i++) pageModel.append({ page: i + 1, rotation: 0, selected: false })
        pdfEdited = false
    }
    function countSelected() {
        var n = 0
        for (var i = 0; i < pageModel.count; i++) if (pageModel.get(i).selected) n++
        pdfSelected = n
    }
    function selectAllPages(on) {
        for (var i = 0; i < pageModel.count; i++) pageModel.setProperty(i, "selected", on)
    }
    function rotateSelected(angle) {
        for (var i = 0; i < pageModel.count; i++)
            if (pageModel.get(i).selected) pageModel.setProperty(i, "rotation", pageModel.get(i).rotation + angle)
        pdfEdited = true
    }
    function deleteSelected() {
        for (var i = pageModel.count - 1; i >= 0; i--) if (pageModel.get(i).selected) pageModel.remove(i)
        pdfEdited = true
    }
    // The large preview shows one card of the board; it can step through the
    // cards and rotate or remove the one it shows.
    function openPagePreview(index) {
        showPreviewAt(index)
        pagePreview.open()
    }
    function showPreviewAt(index) {
        if (index < 0 || index >= pageModel.count) return
        var item = pageModel.get(index)
        pagePreview.index = index
        pagePreview.page = item.page
        pagePreview.pageRotation = item.rotation
        pagePreview.image = localPdf.pageImages[item.page - 1] || ""
        localPdf.renderPreview(item.page)
    }
    function rotatePage(index, angle) {
        pageModel.setProperty(index, "rotation", pageModel.get(index).rotation + angle)
        pdfEdited = true
        if (pagePreview.opened && pagePreview.index === index) pagePreview.pageRotation = pageModel.get(index).rotation
    }
    function removePage(index) {
        if (pageModel.count <= 1) return
        pageModel.remove(index)
        pdfEdited = true
        countSelected()
        if (pagePreview.opened) showPreviewAt(Math.min(index, pageModel.count - 1))
    }
    function openPdfSave() {
        var base = pdfFiles.length > 0 ? decodeURIComponent(filename(pdfFiles[0])).replace(/\.[^.]+$/, "") : "document"
        var suffix = ({edit: " (edited)", merge: " (merged)", split: " (pages)", "images-to-pdf": ""})[pdfMode]
        var folder = pdfFiles.length > 0 ? pdfFiles[0].toString().replace(/\/[^\/]*$/, "") : StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        pdfSave.currentFolder = folder
        pdfSave.selectedFile = folder + "/" + base + suffix + ".pdf"
        pdfSave.open()
    }
    // Output options come back on the next run when Settings says so.
    RememberedOptions {
        target: toolsPage
        category: "toolOptions"
        names: ["audioFormatName", "audioKbps", "audioLufs", "audioMono", "compressGoal", "compressMB", "compressQuality",
                "compressWidth", "gifFps", "gifWidthPx", "gifLimitMB", "qrFg", "qrBg", "qrLevel", "qrSize", "downloadPresetIndex"]
    }
    property int downloadPresetIndex: 0
    onCompressMBChanged: if (Number(compressPanel.targetField.text) !== compressMB) compressPanel.targetField.text = String(compressMB)
    property string resultSection: ""
    property string pendingAction: ""
    property bool isImage: /\.(jpe?g|png|webp|bmp|tiff?)$/i.test(sourceUrl.toString())
    property string selectedFormat: section === 2 ? audioFormatName
                                  : section === 3 ? compressFormatName.toLowerCase() : "gif"
    // Audio settings; a loudness of 0 leaves the level alone.
    property string audioFormatName: "mp3"
    property int audioKbps: 192
    property real audioFadeIn: 0
    property real audioFadeOut: 0
    property int audioLufs: 0
    property bool audioMono: false
    readonly property bool audioLossless: audioFormatName === "wav" || audioFormatName === "flac"
    // The extra options in use, for the folded header.
    readonly property string audioExtras: {
        const parts = []
        if (audioFadeIn > 0) parts.push("fade in " + audioFadeIn + " s")
        if (audioFadeOut > 0) parts.push("fade out " + audioFadeOut + " s")
        if (audioLufs !== 0) parts.push(({ "-16": "Podcast", "-14": "Music", "-9": "Loud" })[audioLufs] + " loudness")
        if (audioMono) parts.push("mono")
        return parts.join(" · ")
    }
    readonly property real audioSelectionSec: audioPreview.duration > 0 ? Math.max(0, audioEndMs - audioStartMs) / 1000 : 0
    // Roughly what the output weighs: the bitrate over the selection, or
    // CD-quality PCM for WAV, which FLAC packs to about 60 %.
    readonly property real audioEstimateBytes: {
        const pcm = 1411 / (audioMono ? 2 : 1)
        const kbps = audioFormatName === "wav" ? pcm : audioFormatName === "flac" ? pcm * 0.6 : audioKbps
        return kbps * 125 * audioSelectionSec
    }
    // Compress aims for a size (videos) or a quality, in a format and width.
    property string compressGoal: "size"
    property real compressMB: 8
    property int compressQuality: 75
    property int compressWidth: 1280
    property string compressPick: ""
    readonly property var compressFormats: isImage ? ["WebP", "JPG", "PNG", "GIF"] : ["MP4", "WebM", "GIF"]
    readonly property string compressFormatName: compressFormats.indexOf(compressPick) >= 0 ? compressPick : compressFormats[0]
    readonly property bool compressToSize: compressGoal === "size" && !isImage && compressMB > 0
    readonly property real sourceBytes: (section === 2 || section === 3) && hasSource ? localTools.fileBytes(sourceUrl) : 0
    // What the file should weigh against what it does now, 0..1.
    readonly property real compressShare: compressToSize && sourceBytes > 0 ? Math.min(1, compressMB * 1048576 / sourceBytes) : 1
    function qualityName(quality) {
        return quality >= 90 ? "Near original" : quality >= 70 ? "Balanced" : quality >= 45 ? "Smaller" : "Smallest"
    }
    signal publishFile(url fileUrl)
    signal openInEditor(url fileUrl)
    // Enter in the link field skips the save dialog: the file goes straight to
    // Downloads under the video's title, or waits in the queue behind the
    // current download. The field empties for the next link.
    readonly property url downloadsFolder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)
    readonly property string downloadLink: downloadPanel.urlField.text.trim()
    readonly property bool linkIsPlaylist: localDownload.playlist.url === downloadLink && !!localDownload.playlist.entries
    function gifOptions() {
        return { gifStart: Number(downloadPanel.gifStartField.text), gifDuration: Number(downloadPanel.gifDurationField.text), gifFps: Number(downloadPanel.gifFpsField.text),
                 gifWidth: Number(downloadPanel.gifWidthField.text), gifTargetMB: Number(downloadPanel.gifTargetField.text) }
    }
    function quickDownload() {
        var link = downloadLink
        if (!localDownload.available || !/^https?:\/\/\S+/i.test(link)) return
        if (linkIsPlaylist) {
            downloadPlaylist()
            return
        }
        var info = localDownload.preview.url === link ? localDownload.preview : ({})
        resultSection = "download"
        localDownload.enqueue(link, downloadPanel.presetBox.currentValue, downloadsFolder, info.title || "", gifOptions())
        downloadPanel.urlField.clear()
    }
    function startDownload(target) {
        resultSection = "download"
        localDownload.download(downloadPanel.urlField.text, downloadPanel.presetBox.currentValue, target,
                               Number(downloadPanel.gifStartField.text), Number(downloadPanel.gifDurationField.text),
                               Number(downloadPanel.gifFpsField.text), Number(downloadPanel.gifWidthField.text), Number(downloadPanel.gifTargetField.text))
    }
    // Which playlist videos are ticked, by index; all of them to start with.
    property var playlistChecked: []
    readonly property int playlistSelected: playlistChecked.filter(function(checked) { return checked }).length
    function setAllPlaylist(checked) {
        var entries = localDownload.playlist.entries || []
        playlistChecked = entries.map(function() { return checked })
    }
    Connections {
        target: localDownload
        function onPlaylistChanged() { toolsPage.setAllPlaylist(true) }
        function onFinished(file, url, title) { toolsPage.rememberDownload(file, url, title) }
    }
    function downloadPlaylist() {
        var playlist = localDownload.playlist
        var entries = playlist.entries || []
        var name = localDownload.safeFileName(playlist.title || "") || "Playlist"
        var folder = downloadsFolder.toString() + "/" + name
        resultSection = "download"
        for (var i = 0; i < entries.length; ++i) {
            if (playlistChecked[i])
                localDownload.enqueue(entries[i].url, downloadPanel.presetBox.currentValue, folder, entries[i].title || "", gifOptions())
        }
        localDownload.clearPlaylist()
        downloadPanel.urlField.clear()
    }
    // Ctrl+V anywhere on the Download page fills the link field; text fields
    // keep their own paste.
    Shortcut {
        sequence: StandardKey.Paste
        enabled: toolsPage.visible && toolsPage.section === 1
                 && !(toolsPage.Window.activeFocusItem instanceof TextInput)
        onActivated: toolsPage.pasteLink()
    }
    function pasteLink() {
        downloadPanel.urlField.clear()
        downloadPanel.urlField.paste()
        downloadPanel.urlField.text = downloadPanel.urlField.text.trim()
        downloadPanel.urlField.forceActiveFocus()
    }
    readonly property bool downloadIsMedia: /\.(mp4|mkv|webm|mov|m4a|mp3|opus|ogg|wav|flac|aac)$/i.test(localDownload.outputUrl.toString())
    readonly property bool hasSource: sourceUrl.toString().length > 0
    readonly property bool fileSection: section >= 2 && section <= 5
    readonly property bool gifSourceIsGif: sourceUrl.toString().toLowerCase().endsWith(".gif")
    // GIF range in milliseconds, mirrored into the start/duration fields.
    readonly property real gifStartMs: Math.max(0, Number(gifPanel.startField.text) * 1000)
    readonly property real gifEndMs: Math.min(gifPreview.duration > 0 ? gifPreview.duration : Infinity, gifStartMs + Math.max(0.1, Number(gifPanel.durationField.text)) * 1000)
    property bool gifLooping: true
    // GIF settings; a limit of 0 leaves the size open.
    property int gifFps: 10
    property int gifWidthPx: 480
    property real gifLimitMB: 10
    property real gifSpeed: 1
    property bool gifBounce: false
    property bool gifOnce: false
    // How long the GIF runs and how tall it comes out.
    readonly property real gifOutSec: Math.max(0, gifEndMs - gifStartMs) / 1000 / gifSpeed * (gifBounce ? 2 : 1)
    readonly property int gifHeightPx: gifPanel.video.sourceRect.width > 0
                                       ? Math.round(gifWidthPx * gifPanel.video.sourceRect.height / gifPanel.video.sourceRect.width / 2) * 2 : 0
    readonly property string gifExtras: {
        const parts = []
        if (gifSpeed !== 1) parts.push(gifSpeed + "× speed")
        if (gifBounce) parts.push("bounce")
        if (gifOnce) parts.push("plays once")
        return parts.join(" · ")
    }
    // Audio trim range in milliseconds; an end of 0 means the whole file.
    readonly property real audioStartMs: Math.max(0, Number(audioPanel.startField.text) * 1000)
    readonly property real audioEndMs: Number(audioPanel.endField.text) > 0 ? Math.min(audioPreview.duration > 0 ? audioPreview.duration : Infinity, Number(audioPanel.endField.text) * 1000)
                                                               : audioPreview.duration
    property bool audioLooping: false

    function setAudioRange(startMs, endMs) {
        audioPanel.startField.text = (Math.max(0, startMs) / 1000).toFixed(2)
        audioPanel.endField.text = (Math.max(startMs + 100, endMs) / 1000).toFixed(2)
    }
    function toggleAudioPreview() {
        if (audioPreview.playbackState === MediaPlayer.PlayingState) {
            audioPreview.pause()
            return
        }
        if (audioPreview.position < audioStartMs || audioPreview.position >= audioEndMs - 50) audioPreview.position = audioStartMs
        audioPreview.play()
    }
    function clockLabel(ms) {
        var seconds = Math.max(0, ms) / 1000
        return Math.floor(seconds / 60) + ":" + (seconds % 60).toFixed(2).padStart(5, "0")
    }

    function setGifRange(startMs, endMs) {
        gifPanel.startField.text = (Math.max(0, startMs) / 1000).toFixed(2)
        gifPanel.durationField.text = (Math.max(100, endMs - startMs) / 1000).toFixed(2)
        if (gifPreview.position < startMs || gifPreview.position > endMs) gifPreview.position = startMs
    }
    function acceptDrop(urls) {
        if (!urls || urls.length === 0) return
        if (section === 5) {
            var images = pdfMode === "images-to-pdf"
            var pattern = images ? /\.(jpe?g|png|webp|bmp|tiff?)$/i : /\.pdf$/i
            var accepted = []
            for (var i = 0; i < urls.length; i++) if (pattern.test(urls[i].toString())) accepted.push(urls[i])
            if (accepted.length > 0) takePdfFiles(accepted)
        } else if (section === 3) {
            takeCompressFiles(urls)
        } else {
            setSource(urls[0])
            toolsPage.compressPick = ""
        }
    }

    MediaPlayer {
        id: audioPreview
        source: toolsPage.section === 2 ? toolsPage.sourceUrl : ""
        audioOutput: AudioOutput { volume: audioPanel.volumeControl.effectiveVolume }
        property string loadedSource: ""
        onMediaStatusChanged: {
            // A new file starts with the whole file selected.
            if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia)
                && source.toString() && source.toString() !== loadedSource) {
                loadedSource = source.toString()
                audioPanel.startField.text = "0"
                audioPanel.endField.text = "0"
            }
            if (mediaStatus === MediaPlayer.EndOfMedia) {
                position = toolsPage.audioStartMs
                if (toolsPage.audioLooping) play()
            }
        }
        onPositionChanged: {
            if (playbackState !== MediaPlayer.PlayingState || position < toolsPage.audioEndMs) return
            position = toolsPage.audioStartMs
            if (!toolsPage.audioLooping) pause()
        }
    }

    MediaPlayer {
        id: gifPreview
        source: toolsPage.section === 4 && !toolsPage.gifSourceIsGif ? toolsPage.sourceUrl : ""
        videoOutput: gifPanel.video
        audioOutput: AudioOutput { muted: true }
        loops: 1
        playbackRate: toolsPage.gifSpeed
        property string startedSource: ""
        onSourceChanged: if (!source.toString()) startedSource = ""
        onMediaStatusChanged: {
            if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia)
                && source.toString() && source.toString() !== startedSource) {
                startedSource = source.toString()
                // Fit the stored range to this file before the first loop.
                toolsPage.setGifRange(Math.min(toolsPage.gifStartMs, Math.max(0, duration - 100)), toolsPage.gifEndMs)
                position = toolsPage.gifStartMs
                if (toolsPage.gifLooping) play()
            }
            // Reaching the end of the file wraps to the range start as well.
            if (mediaStatus === MediaPlayer.EndOfMedia && toolsPage.gifLooping) {
                position = toolsPage.gifStartMs
                play()
            }
        }
        onPositionChanged: {
            if (playbackState === MediaPlayer.PlayingState && position >= toolsPage.gifEndMs)
                position = toolsPage.gifStartMs
        }
    }

    // Any tool that works on files takes them straight from a drop; the
    // downloader takes a dragged link.
    DropArea {
        id: pageDrop
        anchors.fill: parent
        z: 10
        // Only files and links: it sits above the page and file cards, whose
        // own drags must reach the slots underneath to reorder.
        keys: ["text/uri-list", "text/plain"]
        enabled: toolsPage.fileSection || toolsPage.section === 1
        // A result dragged out of Kadron passes over its own window first.
        onEntered: function(drag) { if (drag.source) drag.accepted = false }
        onDropped: function(drop) {
            if (toolsPage.section === 1) {
                var link = drop.hasUrls && !drop.urls[0].toString().startsWith("file:") ? drop.urls[0].toString() : drop.text
                if (link && !/^file:/i.test(link.trim())) downloadPanel.urlField.text = link.trim()
            } else if (drop.hasUrls) toolsPage.acceptDrop(drop.urls)
            drop.accept()
        }
    }

    // The last downloads, newest first, so a file saved an hour ago is one click away.
    readonly property var downloadHistory: {
        try { return JSON.parse(Prefs.downloadHistory) } catch (error) { return [] }
    }
    function rememberDownload(file, url, title) {
        var path = file.toString()
        var list = downloadHistory.filter(function(entry) { return entry.file !== path })
        list.unshift({ file: path, url: url, title: title || filename(file), time: Date.now() })
        Prefs.downloadHistory = JSON.stringify(list.slice(0, 20))
    }
    function forgetDownloads() { Prefs.downloadHistory = "[]" }
    function isMediaFile(url) { return /\.(mp4|mkv|webm|mov|m4a|mp3|opus|ogg|wav|flac|aac)$/i.test(url.toString()) }
    function filename(url) {
        return url.toString().split("/").pop() || "No file selected"
    }
    function sizeLabel(bytes) {
        return bytes < 1024 * 1024 ? (bytes / 1024).toFixed(1) + " KB" : (bytes / 1048576).toFixed(2) + " MB"
    }
    function beginLocal(action) {
        if (!sourceUrl.toString()) return
        pendingAction = action
        // Suggests a name next to the source, with the type spelled out, so
        // the file does not end up without an extension.
        var extension = selectedFormat
        var path = sourceUrl.toString()
        var folder = path.substring(0, path.lastIndexOf("/"))
        var base = decodeURIComponent(path.split("/").pop()).replace(/\.[^.]*$/, "")
        var sourceExtension = (path.match(/\.([^./]*)$/) || ["", ""])[1].toLowerCase()
        if (action === "compress") base += "-compressed"
        else if (sourceExtension === extension || (sourceExtension === "jpeg" && extension === "jpg")) base += "-converted"
        localSave.defaultSuffix = extension
        localSave.nameFilters = [formatLabel(extension)]
        localSave.currentFolder = folder
        localSave.selectedFile = folder + "/" + encodeURIComponent(base) + "." + extension
        localSave.open()
    }
    property string qrFg: "#000000"
    property string qrBg: "#ffffff"
    property string qrLevel: "M"
    property int qrSize: 512
    // Screenshot harness: fills the section's main text input.
    function fillText(value) {
        if (section === 6) qrPanel.textField.text = value
        else if (section === 1) downloadPanel.urlField.text = value
        else if (section === 5) pdfFiles = [value]
    }
    function openQrSave(extension) {
        qrSave.defaultSuffix = extension
        qrSave.nameFilters = [extension === "svg" ? "SVG image (*.svg)" : "PNG image (*.png)"]
        qrSave.currentFolder = StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        qrSave.selectedFile = StandardPaths.writableLocation(StandardPaths.PicturesLocation) + "/qrcode." + extension
        qrSave.open()
    }
    function formatLabel(extension) {
        return ({mp4: "MP4 video (*.mp4)", webm: "WebM video (*.webm)", gif: "GIF animation (*.gif)",
                 mp3: "MP3 audio (*.mp3)", m4a: "AAC audio (*.m4a)", flac: "FLAC audio (*.flac)", wav: "WAV audio (*.wav)", opus: "Opus audio (*.opus)",
                 webp: "WebP image (*.webp)", jpg: "JPEG image (*.jpg *.jpeg)", png: "PNG image (*.png)"})[extension]
               || extension.toUpperCase() + " file (*." + extension + ")"
    }
    function openDownloadSave() {
        var extension = downloadExtension()
        var name = localDownload.preview.fileName || "download"
        downloadSave.defaultSuffix = extension
        downloadSave.nameFilters = [formatLabel(extension)]
        downloadSave.currentFolder = StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        downloadSave.selectedFile = StandardPaths.writableLocation(StandardPaths.DownloadLocation) + "/" + name + "." + extension
        downloadSave.open()
    }
    function durationLabel(ms) {
        var total = Math.round(ms / 1000)
        var h = Math.floor(total / 3600), m = Math.floor(total % 3600 / 60), sec = total % 60
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(sec).padStart(2, "0")
    }
    function downloadExtension() {
        var preset = downloadPanel.presetBox.currentValue
        return preset === "VIDEO_GIF_SOCIAL" ? "gif" : preset.startsWith("AUDIO_") ? preset.split("_")[1].toLowerCase() : "mp4"
    }

    FileDialog {
        id: sourceDialog
        title: "Choose source media"
        fileMode: toolsPage.section === 3 ? FileDialog.OpenFiles : FileDialog.OpenFile
        nameFilters: ["Media files (*.mp4 *.mov *.mkv *.webm *.avi *.m4v *.mp3 *.wav *.flac *.m4a *.ogg *.jpg *.jpeg *.png *.webp *.bmp *.tif *.tiff *.gif)", "All files (*)"]
        onAccepted: {
            if (toolsPage.section === 3) toolsPage.takeCompressFiles(selectedFiles)
            else toolsPage.setSource(selectedFile)
            toolsPage.compressPick = ""
        }
    }
    FolderDialog {
        id: compressFolderDialog
        title: "Save the compressed files in"
        onAccepted: toolsPage.startCompressBatch(selectedFolder)
    }
    FileDialog {
        id: localSave
        title: "Save processed file"
        fileMode: FileDialog.SaveFile
        onAccepted: {
            toolsPage.resultSection = toolsPage.pendingAction
            if (toolsPage.pendingAction === "audio")
                localTools.convertAudio(toolsPage.sourceUrl, selectedFile, toolsPage.selectedFormat,
                                        toolsPage.audioKbps, toolsPage.audioLufs !== 0,
                                        Number(audioPanel.startField.text), Number(audioPanel.endField.text),
                                        { fadeIn: toolsPage.audioFadeIn, fadeOut: toolsPage.audioFadeOut,
                                          lufs: toolsPage.audioLufs || -14, mono: toolsPage.audioMono })
            else if (toolsPage.pendingAction === "compress")
                localTools.compress(toolsPage.sourceUrl, selectedFile, toolsPage.selectedFormat,
                                    toolsPage.compressQuality, toolsPage.compressToSize ? toolsPage.compressMB : 0,
                                    toolsPage.compressWidth, compressPanel.noAudioBox.checked)
            else
                localTools.createGif(toolsPage.sourceUrl, selectedFile, Number(gifPanel.startField.text),
                                     Number(gifPanel.durationField.text), toolsPage.gifFps,
                                     toolsPage.gifWidthPx, toolsPage.gifLimitMB,
                                     { speed: toolsPage.gifSpeed, bounce: toolsPage.gifBounce, once: toolsPage.gifOnce })
        }
    }
    FileDialog {
        id: downloadSave
        title: "Save download on this device"
        fileMode: FileDialog.SaveFile
        onAccepted: toolsPage.startDownload(selectedFile)
    }
    FileDialog {
        id: pdfSave
        title: "Save PDF on this device"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "pdf"
        nameFilters: ["PDF document (*.pdf)"]
        onAccepted: {
            toolsPage.resultSection = "pdf"
            if (toolsPage.pdfMode === "edit") {
                var pages = []
                for (var i = 0; i < pageModel.count; i++) pages.push({ page: pageModel.get(i).page, rotation: pageModel.get(i).rotation })
                localPdf.compose(pages, selectedFile)
            } else {
                localPdf.process(toolsPage.pdfMode, toolsPage.pdfFiles, localPdf.pagesToRange(toolsPage.splitPages), 0, selectedFile)
            }
        }
    }
    FileDialog {
        id: pdfDialog
        title: "Choose documents"
        fileMode: toolsPage.pdfMode === "edit" || toolsPage.pdfMode === "split" ? FileDialog.OpenFile : FileDialog.OpenFiles
        nameFilters: toolsPage.pdfMode === "images-to-pdf" ? ["Images (*.jpg *.jpeg *.png *.webp *.bmp *.tif *.tiff)"] : ["PDF files (*.pdf)"]
        onAccepted: toolsPage.takePdfFiles(fileMode === FileDialog.OpenFile ? [selectedFile] : selectedFiles)
    }
    Popup {
        id: pagePreview
        property int index: 0
        property int page: 1
        property int pageRotation: 0
        property url image
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 900)
        height: parent.height - 100
        modal: true
        padding: 16
        Overlay.modal: Rectangle { color: Theme.scrim }
        enter: Transition { ParallelAnimation { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.reveal } SnapSpring { property: "scale"; from: 0.94; to: 1 } } }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.fadeFast } }
        background: Rectangle { color: Theme.card; radius: Theme.radiusLarge; border.color: Theme.lineStrong }
        Shortcut { enabled: pagePreview.opened; sequences: [StandardKey.MoveToPreviousChar, "PgUp"]; onActivated: toolsPage.showPreviewAt(pagePreview.index - 1) }
        Shortcut { enabled: pagePreview.opened; sequences: [StandardKey.MoveToNextChar, "PgDown"]; onActivated: toolsPage.showPreviewAt(pagePreview.index + 1) }
        Shortcut { enabled: pagePreview.opened; sequence: "R"; onActivated: toolsPage.rotatePage(pagePreview.index, 90) }
        Shortcut { enabled: pagePreview.opened; sequence: "Shift+R"; onActivated: toolsPage.rotatePage(pagePreview.index, -90) }
        Shortcut { enabled: pagePreview.opened; sequence: StandardKey.Delete; onActivated: toolsPage.removePage(pagePreview.index) }
        contentItem: ColumnLayout {
            spacing: 10
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                Image {
                    anchors.centerIn: parent
                    readonly property bool sideways: ((pagePreview.pageRotation % 180) + 180) % 180 === 90
                    width: sideways ? parent.height : parent.width
                    height: sideways ? parent.width : parent.height
                    source: pagePreview.image
                    fillMode: Image.PreserveAspectFit
                    rotation: pagePreview.pageRotation
                    Behavior on rotation { SnapSpring { epsilon: 0.2 } }
                    asynchronous: true
                }
                // Previous and next, over the page edges.
                Repeater {
                    model: [[-1, "Previous page (←)"], [1, "Next page (→)"]]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool available: modelData[0] < 0 ? pagePreview.index > 0 : pagePreview.index < pageModel.count - 1
                        anchors.verticalCenter: parent.verticalCenter
                        x: modelData[0] < 0 ? 8 : parent.width - width - 8
                        width: 40
                        height: 40
                        radius: 20
                        visible: available
                        color: stepMouse.containsMouse ? Theme.pressed : Theme.chipScrim
                        ToolIcon { anchors.centerIn: parent; width: 18; height: 18; name: "chevron"; rotation: parent.modelData[0] < 0 ? 90 : -90; tint: "#f1f4ef" }
                        MouseArea {
                            id: stepMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: toolsPage.showPreviewAt(pagePreview.index + parent.modelData[0])
                        }
                        ToolTip.visible: stepMouse.containsMouse
                        ToolTip.delay: 400
                        ToolTip.text: modelData[1]
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    objectName: "pagePreviewLabel"
                    text: "Page " + (pagePreview.index + 1) + " of " + pageModel.count
                          + (pagePreview.page !== pagePreview.index + 1 ? "  ·  page " + pagePreview.page + " of the original" : "")
                    color: Theme.text
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: "←/→ pages · R rotate · Del remove · Esc close"
                    color: Theme.textFaint
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                }
                EditorButton { iconName: "rotateLeft"; subtle: true; onClicked: toolsPage.rotatePage(pagePreview.index, -90); ToolTip.visible: hovered; ToolTip.text: "Rotate left (Shift+R)" }
                EditorButton { iconName: "rotateRight"; subtle: true; onClicked: toolsPage.rotatePage(pagePreview.index, 90); ToolTip.visible: hovered; ToolTip.text: "Rotate right (R)" }
                EditorButton { iconName: "trash"; danger: true; subtle: true; enabled: pageModel.count > 1; onClicked: toolsPage.removePage(pagePreview.index); ToolTip.visible: hovered; ToolTip.text: "Remove this page (Del)" }
            }
        }
    }
    FileDialog {
        id: qrSave
        title: "Save QR code"
        fileMode: FileDialog.SaveFile
        onAccepted: localQr.save(selectedFile, toolsPage.qrSize, toolsPage.qrFg, toolsPage.qrBg)
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.window
    }
    ScrollView {
        id: scroll
        readonly property SoftBounds softBounds: SoftBounds { flickable: scroll.contentItem }
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: ScrollBar {
            width: 8
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle { implicitWidth: 6; radius: 3; color: Theme.textFaint }
        }
        Item {
            width: scroll.availableWidth
            implicitHeight: formColumn.implicitHeight + 100

            Rectangle {
                x: formColumn.x - 23
                y: formColumn.y + 105
                width: formColumn.width + 46
                height: Math.max(220, formColumn.implicitHeight - 105 + 16)
                radius: 14
                color: Theme.panel
                border.color: Theme.hover
            }
        ColumnLayout {
            id: formColumn
            width: Math.min(scroll.availableWidth - 90, 760)
            x: Math.max(45, (scroll.availableWidth - width) / 2)
            y: 35
            spacing: 15

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: ["", "Download a source", "Convert audio", "Reduce file size", "Make a GIF", "Work with PDFs", "Create a QR code"][toolsPage.section]
                    color: Theme.text
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                // yt-dlp status: checked against its newest release in the background;
                // the pill offers the update only when there is one.
                Rectangle {
                    id: ytdlpPill
                    objectName: "ytdlpPill"
                    visible: toolsPage.section === 1
                    readonly property bool needsAction: !localDownload.updatingYtDlp
                        && (!localDownload.ytDlpVersion || localDownload.ytDlpOutdated || localDownload.ytDlpUpdateFailed)
                    readonly property bool upToDate: !!localDownload.ytDlpVersion && !!localDownload.ytDlpLatest
                        && !localDownload.ytDlpUpdateAvailable && !localDownload.ytDlpUpdateFailed
                    Layout.preferredWidth: pillRow.implicitWidth + 22
                    Layout.preferredHeight: 28
                    Layout.rightMargin: 8
                    radius: 14
                    color: needsAction ? Theme.playheadWash : Theme.field
                    border.color: needsAction ? Theme.warning : pillMouse.containsMouse ? Theme.lineStrong : Theme.line
                    Behavior on border.color { ColorAnimation { duration: Theme.fadeFast } }
                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: localDownload.updatingYtDlp || localDownload.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            if (localDownload.updatingYtDlp || localDownload.busy) return
                            if (ytdlpPill.needsAction) localDownload.updateYtDlp()
                            else localDownload.checkYtDlpRelease(false)
                        }
                        ToolTip.visible: containsMouse
                        ToolTip.delay: 400
                        ToolTip.text: localDownload.ytDlpUpdateFailed ? localDownload.updateText
                            : !localDownload.ytDlpVersion ? "Kadron can download its own copy of yt-dlp"
                            : "Installed " + localDownload.ytDlpVersion
                              + (localDownload.ytDlpLatest ? " · newest " + localDownload.ytDlpLatest : "")
                              + (ytdlpPill.needsAction ? " · click to update" : " · click to check again")
                    }
                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 7
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: 7
                            radius: 3.5
                            color: ytdlpPill.needsAction ? Theme.warning : ytdlpPill.upToDate ? Theme.accent : Theme.textMuted
                            SequentialAnimation on opacity {
                                running: localDownload.updatingYtDlp || localDownload.checkingYtDlp
                                loops: Animation.Infinite
                                onRunningChanged: if (!running) parent.opacity = 1
                                NumberAnimation { to: 0.3; duration: 500 }
                                NumberAnimation { to: 1; duration: 500 }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: localDownload.updatingYtDlp ? localDownload.updateText
                                : !localDownload.ytDlpVersion ? "yt-dlp not found"
                                : localDownload.ytDlpUpdateFailed ? "yt-dlp update failed"
                                : localDownload.ytDlpUpdateAvailable ? "yt-dlp " + localDownload.ytDlpLatest + " available"
                                : ytdlpPill.upToDate ? "yt-dlp " + localDownload.ytDlpVersion + " · up to date"
                                : localDownload.checkingYtDlp ? "yt-dlp " + localDownload.ytDlpVersion + " · checking…"
                                : "yt-dlp " + localDownload.ytDlpVersion
                                  + (localDownload.ytDlpOutdated ? " · " + localDownload.ytDlpAgeDays + " days old" : "")
                            color: ytdlpPill.needsAction ? Theme.warning : Theme.textMuted
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: ytdlpPill.needsAction
                            text: !localDownload.ytDlpVersion ? "Install" : localDownload.ytDlpUpdateFailed ? "Retry" : "Update"
                            color: Theme.accentSoft
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.underline: pillMouse.containsMouse
                        }
                    }
                }
                Rectangle {
                    Layout.preferredWidth: scopeLabel.implicitWidth + 22
                    Layout.preferredHeight: 28
                    radius: 14
                    color: Theme.accentWash
                    Text {
                        id: scopeLabel
                        anchors.centerIn: parent
                        text: "ON DEVICE"
                        color: Theme.accentSoft
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.8
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.bottomMargin: 32
                text: ["", "Paste a media URL, choose the format, then save the result locally.", "Change format, trim a section, or normalize the sound.", "Set a size limit or quality target before processing.", "Trim a moment and control frame rate, width, and file size.", "Merge, split, rotate, or arrange your documents.", "Turn text or a link into a downloadable image."][toolsPage.section]
                color: Theme.textMuted
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            DownloadPanel {
                id: downloadPanel
                page: toolsPage
            }

            DropZone {
                visible: toolsPage.section >= 2 && toolsPage.section <= 4 && !toolsPage.hasSource
                Layout.fillWidth: true
                active: pageDrop.containsDrag
                iconName: ["drop", "drop", "audio", "compress", "gif"][Math.min(toolsPage.section, 4)]
                heading: ["", "", "Drop an audio or video file", "Drop a video or image", "Drop a video to turn into a GIF"][Math.min(toolsPage.section, 4)]
                formats: ["", "", "MP3 · WAV · FLAC · M4A · OGG · MP4 · MOV · MKV", "MP4 · MOV · MKV · WEBM · JPG · PNG · WEBP", "MP4 · MOV · MKV · WEBM · GIF"][Math.min(toolsPage.section, 4)]
                onBrowseRequested: sourceDialog.open()
            }
            ColumnLayout {
                visible: toolsPage.section >= 2 && toolsPage.section <= 4 && toolsPage.hasSource
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 54
                    radius: Theme.radius
                    color: pageDrop.containsDrag ? Theme.accentWash : Theme.field
                    border.color: pageDrop.containsDrag ? Theme.accent : Theme.line
                    Behavior on color { ColorAnimation { duration: Theme.fade } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        spacing: 10
                        ToolIcon { name: "file"; tint: Theme.accent }
                        Text {
                            Layout.fillWidth: true
                            text: pageDrop.containsDrag ? "Drop to replace"
                                : toolsPage.section === 3 && toolsPage.compressBatch.length > 1
                                  ? toolsPage.compressBatch.length + " files · " + decodeURIComponent(toolsPage.filename(toolsPage.sourceUrl)) + " and more"
                                  : decodeURIComponent(toolsPage.filename(toolsPage.sourceUrl))
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideMiddle
                        }
                        EditorButton { text: "Change"; subtle: true; onClicked: sourceDialog.open() }
                        EditorButton { iconName: "close"; subtle: true; enabled: !localTools.busy; onClicked: toolsPage.setSource(""); ToolTip.visible: hovered; ToolTip.text: "Clear file" }
                    }
                }
                Text {
                    visible: !localTools.available
                    text: "FFmpeg and FFprobe are unavailable. Set their paths before processing."
                    color: Theme.warning
                    font.pixelSize: 12
                }
            }

            AudioPanel {
                id: audioPanel
                page: toolsPage
            }

            CompressPanel {
                id: compressPanel
                page: toolsPage
            }

            GifPanel {
                id: gifPanel
                page: toolsPage
            }

            PdfPanel {
                id: pdfPanel
                page: toolsPage
            }

            QrPanel {
                id: qrPanel
                page: toolsPage
            }

            Rectangle {
                visible: localTools.busy || localTools.errorText.length > 0 || localTools.outputUrl.toString().length > 0 || localDownload.busy || localDownload.errorText.length > 0 || localDownload.outputUrl.toString().length > 0 || localPdf.busy || localPdf.errorText.length > 0 || localPdf.outputUrl.toString().length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.line
                Layout.topMargin: 8
            }
            RowLayout {
                visible: toolsPage.section >= 2 && toolsPage.section <= 4 && (localTools.busy || localTools.errorText || localTools.outputUrl.toString() || (toolsPage.section === 3 && toolsPage.compressSummary.length > 0))
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: toolsPage.section === 3 && (toolsPage.compressRunning || toolsPage.compressSummary)
                          ? (toolsPage.compressRunning ? "File " + (toolsPage.compressTotal - toolsPage.compressQueue.length) + " of " + toolsPage.compressTotal + " · " + localTools.stage
                                                       : toolsPage.compressSummary)
                          : localTools.errorText || localTools.stage
                    color: localTools.errorText && !toolsPage.compressRunning && !toolsPage.compressSummary ? Theme.danger : Theme.textSoft
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Text { text: localTools.busy ? localTools.progress + "%" : localTools.outputUrl.toString() ? toolsPage.sizeLabel(localTools.outputBytes) + (toolsPage.resultSection === "compress" && toolsPage.sourceBytes > localTools.outputBytes && localTools.outputBytes > 0 ? " · " + Math.round((1 - localTools.outputBytes / toolsPage.sourceBytes) * 100) + "% smaller" : "") : ""; color: Theme.textMuted; font.pixelSize: 12 }
                EditorButton {
                    text: toolsPage.compressRunning ? "Cancel all" : "Cancel"
                    visible: localTools.busy
                    danger: true
                    onClicked: toolsPage.compressRunning ? toolsPage.cancelCompressBatch() : localTools.cancel()
                }
                EditorButton {
                    visible: toolsPage.section === 3 && !toolsPage.compressRunning && toolsPage.compressSummary.length > 0
                    text: "Open folder"
                    iconName: "folder"
                    subtle: true
                    onClicked: Qt.openUrlExternally(toolsPage.compressFolder)
                }
            }
            StudioProgress { visible: toolsPage.section >= 2 && toolsPage.section <= 4 && localTools.busy; value: localTools.progress / 100; Layout.fillWidth: true }
            RowLayout {
                id: toolResultRow
                visible: toolsPage.section >= 2 && toolsPage.section <= 4 && toolsPage.resultSection === (toolsPage.section === 2 ? "audio" : toolsPage.section === 3 ? "compress" : "gif") && localTools.outputUrl.toString().length > 0 && !localTools.busy
                Layout.fillWidth: true
                ResultEntrance { target: toolResultRow; file: localTools.busy ? "" : localTools.outputUrl }
                Text { text: toolsPage.filename(localTools.outputUrl); color: Theme.textSoft; font.pixelSize: 12; elide: Text.ElideMiddle; Layout.fillWidth: true
                       DragOutFile { anchors.fill: parent; file: localTools.outputUrl } }
                EditorButton { iconName: "folder"; subtle: true; implicitWidth: 38; onClicked: shellIntegration.reveal(localTools.outputUrl)
                               ToolTip.visible: hovered; ToolTip.text: "Show in folder" }
                CopyButton { file: localTools.outputUrl }
                EditorButton { text: "Open file"; onClicked: Qt.openUrlExternally(localTools.outputUrl) }
                EditorButton { text: "Publish"; onClicked: toolsPage.publishFile(localTools.outputUrl) }
            }
            RowLayout {
                visible: toolsPage.section === 1 ? (localDownload.busy || localDownload.errorText || localDownload.outputUrl.toString()) : toolsPage.section === 5 && (localPdf.busy || localPdf.errorText || localPdf.outputUrl.toString())
                Layout.fillWidth: true
                spacing: 10
                Text { text: toolsPage.section === 1 ? (localDownload.errorText || (localDownload.currentTitle && localDownload.busy ? localDownload.currentTitle + " · " : "") + localDownload.stage) : (localPdf.errorText || localPdf.stage); color: toolsPage.section === 1 ? (localDownload.errorText ? Theme.danger : Theme.textSoft) : (localPdf.errorText ? Theme.danger : Theme.textSoft); font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                Text { text: toolsPage.section === 1 ? (localDownload.busy ? localDownload.progress + "%" : localDownload.outputUrl.toString() ? toolsPage.sizeLabel(localDownload.outputBytes) : "") : (localPdf.outputUrl.toString() ? toolsPage.sizeLabel(localPdf.outputBytes) : ""); color: Theme.textMuted; font.pixelSize: 12 }
                EditorButton { text: "Cancel"; visible: toolsPage.section === 1 ? localDownload.busy : localPdf.busy; danger: true; onClicked: toolsPage.section === 1 ? localDownload.cancel() : localPdf.cancel() }
            }
            StudioProgress { visible: toolsPage.section === 1 && localDownload.busy; value: localDownload.progress / 100; Layout.fillWidth: true }
            // Links waiting behind the current download.
            ColumnLayout {
                visible: toolsPage.section === 1 && localDownload.queue.length > 0
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Up next · " + localDownload.queue.length; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true }
                    EditorButton { text: "Clear queue"; subtle: true; implicitHeight: 30; onClicked: localDownload.clearQueue() }
                }
                Repeater {
                    model: localDownload.queue
                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: (index + 1) + ". " + (modelData.title || modelData.url)
                            color: Theme.textSoft
                            font.pixelSize: 12
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                        EditorButton { iconName: "close"; subtle: true; implicitHeight: 26; implicitWidth: 26; onClicked: localDownload.removeQueued(modelData.id)
                                       ToolTip.visible: hovered; ToolTip.text: "Remove from queue" }
                    }
                }
            }
            RowLayout {
                id: fileResultRow
                readonly property url file: toolsPage.section === 1 ? localDownload.outputUrl : localPdf.outputUrl
                visible: (toolsPage.section === 1 && toolsPage.resultSection === "download" && localDownload.outputUrl.toString().length > 0 && !localDownload.busy) || (toolsPage.section === 5 && toolsPage.resultSection === "pdf" && localPdf.outputUrl.toString().length > 0 && !localPdf.busy)
                Layout.fillWidth: true
                ResultEntrance { target: fileResultRow; file: localDownload.busy || localPdf.busy ? "" : fileResultRow.file }
                Text { text: toolsPage.filename(toolsPage.section === 1 ? localDownload.outputUrl : localPdf.outputUrl); color: Theme.textSoft; font.pixelSize: 12; elide: Text.ElideMiddle; Layout.fillWidth: true
                       DragOutFile { anchors.fill: parent; file: toolsPage.section === 1 ? localDownload.outputUrl : localPdf.outputUrl } }
                EditorButton { iconName: "folder"; subtle: true; implicitWidth: 38; onClicked: shellIntegration.reveal(fileResultRow.file)
                               ToolTip.visible: hovered; ToolTip.text: "Show in folder" }
                CopyButton { file: fileResultRow.file }
                EditorButton { text: "Open in editor"; iconName: "edit"; visible: toolsPage.section === 1 && toolsPage.downloadIsMedia; onClicked: toolsPage.openInEditor(localDownload.outputUrl) }
                EditorButton { text: "Open file"; onClicked: Qt.openUrlExternally(toolsPage.section === 1 ? localDownload.outputUrl : localPdf.outputUrl) }
                EditorButton { text: "Publish"; onClicked: toolsPage.publishFile(toolsPage.section === 1 ? localDownload.outputUrl : localPdf.outputUrl) }
            }
            // Recent downloads: open, find, edit or fetch them again.
            ColumnLayout {
                visible: toolsPage.section === 1 && toolsPage.downloadHistory.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    // The header folds the list away and back.
                    Item {
                        objectName: "recentDownloadsToggle"
                        Layout.fillWidth: true
                        implicitHeight: 30
                        HoverHandler { id: foldHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Prefs.downloadHistoryFolded = !Prefs.downloadHistoryFolded }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            ToolIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "chevron"
                                width: 14
                                height: 14
                                tint: foldHover.hovered ? Theme.text : Theme.textMuted
                                rotation: Prefs.downloadHistoryFolded ? -90 : 0
                                Behavior on rotation { SmoothSpring {} }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Recent downloads · " + toolsPage.downloadHistory.length
                                color: foldHover.hovered ? Theme.text : Theme.textMuted
                                font.pixelSize: 12
                            }
                        }
                    }
                    EditorButton { text: "Clear"; subtle: true; implicitHeight: 30; visible: !Prefs.downloadHistoryFolded; onClicked: toolsPage.forgetDownloads() }
                }
                Collapsible {
                    open: !Prefs.downloadHistoryFolded
                    spacing: 2
                    Repeater {
                        model: toolsPage.downloadHistory
                        delegate: Rectangle {
                            id: historyRow
                            required property var modelData
                            readonly property bool present: editorProject.fileExists(modelData.file)
                            Layout.fillWidth: true
                            implicitHeight: 38
                            radius: 8
                            color: rowHover.hovered ? Theme.hover : "transparent"
                            HoverHandler { id: rowHover }
                            DragOutFile { anchors.fill: parent; file: historyRow.present ? historyRow.modelData.file : "" }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 4
                                spacing: 4
                                ToolIcon { name: "file"; implicitWidth: 14; implicitHeight: 14; tint: Theme.textMuted; opacity: historyRow.present ? 1 : 0.4 }
                                Text {
                                    text: historyRow.modelData.title
                                    color: historyRow.present ? Theme.textSoft : Theme.textMuted
                                    font.pixelSize: 12
                                    font.strikeout: !historyRow.present
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 4
                                }
                                EditorButton { iconName: "external"; subtle: true; implicitWidth: 30; implicitHeight: 30; visible: historyRow.present
                                               onClicked: Qt.openUrlExternally(historyRow.modelData.file)
                                               ToolTip.visible: hovered; ToolTip.text: "Open" }
                                EditorButton { iconName: "folder"; subtle: true; implicitWidth: 30; implicitHeight: 30; visible: historyRow.present
                                               onClicked: shellIntegration.reveal(historyRow.modelData.file)
                                               ToolTip.visible: hovered; ToolTip.text: "Show in folder" }
                                EditorButton { iconName: "edit"; subtle: true; implicitWidth: 30; implicitHeight: 30
                                               visible: historyRow.present && toolsPage.isMediaFile(historyRow.modelData.file)
                                               onClicked: toolsPage.openInEditor(historyRow.modelData.file)
                                               ToolTip.visible: hovered; ToolTip.text: "Open in editor" }
                                EditorButton { iconName: "download"; subtle: true; implicitWidth: 30; implicitHeight: 30; visible: !!historyRow.modelData.url
                                               onClicked: {
                                                   toolsPage.resultSection = "download"
                                                   localDownload.enqueue(historyRow.modelData.url, downloadPanel.presetBox.currentValue, toolsPage.downloadsFolder,
                                                                         historyRow.modelData.title, toolsPage.gifOptions())
                                               }
                                               ToolTip.visible: hovered; ToolTip.text: "Download again" }
                            }
                        }
                    }
                }
            }
            Item { Layout.preferredHeight: 8 }
        }
        }
    }
}
