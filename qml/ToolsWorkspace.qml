import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import QtCore

Item {
    id: toolsPage
    property int section: 1
    property url sourceUrl: ""
    property var pdfFiles: []
    property string pdfMode: "edit"
    property bool pdfEdited: false
    property int pdfSelected: 0
    ListModel { id: pageModel }
    onPdfFilesChanged: if (pdfMode === "edit") loadPdfPages()
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
        else if (mode === "edit") loadPdfPages()
    }
    function loadPdfPages() {
        if (pdfFiles.length > 0) localPdf.loadPages(pdfFiles[0])
        else localPdf.clearPages()
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
    function openPagePreview(page, rotation) {
        pagePreview.page = page
        pagePreview.pageRotation = rotation
        pagePreview.image = localPdf.pageImages[page - 1] || ""
        pagePreview.open()
        localPdf.renderPreview(page)
    }
    function openPdfSave() {
        var base = pdfFiles.length > 0 ? decodeURIComponent(filename(pdfFiles[0])).replace(/\.[^.]+$/, "") : "document"
        var suffix = ({edit: " (edited)", merge: " (merged)", split: " (pages)", "images-to-pdf": ""})[pdfMode]
        var folder = pdfFiles.length > 0 ? pdfFiles[0].toString().replace(/\/[^\/]*$/, "") : StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        pdfSave.currentFolder = folder
        pdfSave.selectedFile = folder + "/" + base + suffix + ".pdf"
        pdfSave.open()
    }
    property string resultSection: ""
    property string pendingAction: ""
    property bool isImage: /\.(jpe?g|png|webp|bmp|tiff?)$/i.test(sourceUrl.toString())
    property string selectedFormat: section === 2 ? audioFormat.currentText.toLowerCase()
                                  : section === 3 ? compressFormat.currentText.toLowerCase() : "gif"
    signal publishFile(url fileUrl)
    readonly property bool hasSource: sourceUrl.toString().length > 0
    readonly property bool fileSection: section >= 2 && section <= 5
    readonly property bool gifSourceIsGif: sourceUrl.toString().toLowerCase().endsWith(".gif")
    // GIF range in milliseconds, mirrored into the start/duration fields.
    readonly property real gifStartMs: Math.max(0, Number(gifStart.text) * 1000)
    readonly property real gifEndMs: Math.min(gifPreview.duration > 0 ? gifPreview.duration : Infinity, gifStartMs + Math.max(0.1, Number(gifDuration.text)) * 1000)
    property bool gifLooping: true
    // Audio trim range in milliseconds; an end of 0 means the whole file.
    readonly property real audioStartMs: Math.max(0, Number(audioStart.text) * 1000)
    readonly property real audioEndMs: Number(audioEnd.text) > 0 ? Math.min(audioPreview.duration > 0 ? audioPreview.duration : Infinity, Number(audioEnd.text) * 1000)
                                                               : audioPreview.duration
    property bool audioLooping: false

    function setAudioRange(startMs, endMs) {
        audioStart.text = (Math.max(0, startMs) / 1000).toFixed(2)
        audioEnd.text = (Math.max(startMs + 100, endMs) / 1000).toFixed(2)
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
        gifStart.text = (Math.max(0, startMs) / 1000).toFixed(2)
        gifDuration.text = (Math.max(100, endMs - startMs) / 1000).toFixed(2)
        if (gifPreview.position < startMs || gifPreview.position > endMs) gifPreview.position = startMs
    }
    function acceptDrop(urls) {
        if (!urls || urls.length === 0) return
        if (section === 5) {
            var images = pdfMode === "images-to-pdf"
            var pattern = images ? /\.(jpe?g|png|webp|bmp|tiff?)$/i : /\.pdf$/i
            var accepted = []
            for (var i = 0; i < urls.length; i++) if (pattern.test(urls[i].toString())) accepted.push(urls[i])
            if (accepted.length > 0) pdfFiles = accepted
        } else {
            sourceUrl = urls[0]
            compressFormat.currentIndex = 0
        }
    }

    MediaPlayer {
        id: audioPreview
        source: toolsPage.section === 2 ? toolsPage.sourceUrl : ""
        audioOutput: AudioOutput {}
        property string loadedSource: ""
        onMediaStatusChanged: {
            // A new file starts with the whole file selected.
            if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia)
                && source.toString() && source.toString() !== loadedSource) {
                loadedSource = source.toString()
                audioStart.text = "0"
                audioEnd.text = "0"
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
        videoOutput: gifVideo
        audioOutput: AudioOutput { muted: true }
        loops: 1
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
        enabled: toolsPage.fileSection || toolsPage.section === 1
        onDropped: function(drop) {
            if (toolsPage.section === 1) {
                var link = drop.hasUrls && !drop.urls[0].toString().startsWith("file:") ? drop.urls[0].toString() : drop.text
                if (link) downloadUrl.text = link.trim()
            } else if (drop.hasUrls) toolsPage.acceptDrop(drop.urls)
            drop.accept()
        }
    }

    function filename(url) {
        return url.toString().split("/").pop() || "No file selected"
    }
    function sizeLabel(bytes) {
        return bytes < 1024 * 1024 ? (bytes / 1024).toFixed(1) + " KB" : (bytes / 1048576).toFixed(2) + " MB"
    }
    function beginLocal(action) {
        if (!sourceUrl.toString()) return
        pendingAction = action
        localSave.defaultSuffix = selectedFormat
        localSave.open()
    }
    property string qrFg: "#000000"
    property string qrBg: "#ffffff"
    property string qrLevel: "M"
    property int qrSize: 512
    // Screenshot harness: fills the section's main text input.
    function fillText(value) {
        if (section === 6) qrText.text = value
        else if (section === 1) downloadUrl.text = value
        else if (section === 5) pdfFiles = [value]
    }
    function openQrSave(extension) {
        qrSave.defaultSuffix = extension
        qrSave.nameFilters = [extension === "svg" ? "SVG image (*.svg)" : "PNG image (*.png)"]
        qrSave.currentFolder = StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        qrSave.selectedFile = StandardPaths.writableLocation(StandardPaths.PicturesLocation) + "/qrcode." + extension
        qrSave.open()
    }
    function downloadLabel(extension) {
        return ({mp4: "MP4 video (*.mp4)", gif: "GIF animation (*.gif)", mp3: "MP3 audio (*.mp3)",
                 flac: "FLAC audio (*.flac)", wav: "WAV audio (*.wav)", opus: "Opus audio (*.opus)"})[extension] || "*." + extension
    }
    function openDownloadSave() {
        var extension = downloadExtension()
        var name = localDownload.preview.fileName || "download"
        downloadSave.defaultSuffix = extension
        downloadSave.nameFilters = [downloadLabel(extension)]
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
        var preset = downloadPreset.currentValue
        return preset === "VIDEO_GIF_SOCIAL" ? "gif" : preset.startsWith("AUDIO_") ? preset.split("_")[1].toLowerCase() : "mp4"
    }

    FileDialog {
        id: sourceDialog
        title: "Choose source media"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Media files (*.mp4 *.mov *.mkv *.webm *.avi *.m4v *.mp3 *.wav *.flac *.m4a *.ogg *.jpg *.jpeg *.png *.webp *.bmp *.tif *.tiff *.gif)", "All files (*)"]
        onAccepted: {
            toolsPage.sourceUrl = selectedFile
            compressFormat.currentIndex = 0
        }
    }
    FileDialog {
        id: localSave
        title: "Save processed file"
        fileMode: FileDialog.SaveFile
        onAccepted: {
            toolsPage.resultSection = toolsPage.pendingAction
            if (toolsPage.pendingAction === "audio")
                localTools.convertAudio(toolsPage.sourceUrl, selectedFile, toolsPage.selectedFormat,
                                        Number(audioBitrate.text), audioNormalize.checked,
                                        Number(audioStart.text), Number(audioEnd.text))
            else if (toolsPage.pendingAction === "compress")
                localTools.compress(toolsPage.sourceUrl, selectedFile, toolsPage.selectedFormat,
                                    Number(compressQuality.text), Number(compressTarget.text),
                                    Number(compressWidth.text), compressNoAudio.checked)
            else
                localTools.createGif(toolsPage.sourceUrl, selectedFile, Number(gifStart.text),
                                     Number(gifDuration.text), Number(gifFps.text),
                                     Number(gifWidth.text), Number(gifTarget.text))
        }
    }
    FileDialog {
        id: downloadSave
        title: "Save download on this device"
        fileMode: FileDialog.SaveFile
        onAccepted: {
            toolsPage.resultSection = "download"
            localDownload.download(downloadUrl.text, downloadPreset.currentValue, selectedFile,
                                   Number(downloadStart.text), Number(downloadDuration.text),
                                   Number(downloadFps.text), Number(downloadWidth.text), Number(downloadTarget.text))
        }
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
                localPdf.process(toolsPage.pdfMode, toolsPage.pdfFiles, pdfPages.text, 0, selectedFile)
            }
        }
    }
    FileDialog {
        id: pdfDialog
        title: "Choose documents"
        fileMode: toolsPage.pdfMode === "edit" || toolsPage.pdfMode === "split" ? FileDialog.OpenFile : FileDialog.OpenFiles
        nameFilters: toolsPage.pdfMode === "images-to-pdf" ? ["Images (*.jpg *.jpeg *.png *.webp *.bmp *.tif *.tiff)"] : ["PDF files (*.pdf)"]
        onAccepted: toolsPage.pdfFiles = fileMode === FileDialog.OpenFile ? [selectedFile] : selectedFiles
    }
    Popup {
        id: pagePreview
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
        contentItem: Item {
            Image {
                anchors.centerIn: parent
                readonly property bool sideways: ((pagePreview.pageRotation % 180) + 180) % 180 === 90
                width: sideways ? parent.height : parent.width
                height: sideways ? parent.width : parent.height - 30
                source: pagePreview.image
                fillMode: Image.PreserveAspectFit
                rotation: pagePreview.pageRotation
                asynchronous: true
            }
            Text { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: "Page " + pagePreview.page + " · Esc to close"; color: Theme.textMuted; font.pixelSize: 12 }
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

            ColumnLayout {
                visible: toolsPage.section === 1
                Layout.fillWidth: true
                spacing: 12
                Text { text: "Source URL"; color: Theme.textMuted; font.pixelSize: 12 }
                EditorField {
                    id: downloadUrl
                    Layout.fillWidth: true
                    placeholderText: "Paste a link from YouTube, TikTok, Instagram, X, Vimeo…"
                    onTextChanged: probeDelay.restart()
                }
                Timer { id: probeDelay; interval: 450; onTriggered: localDownload.probe(downloadUrl.text) }
                // What the link points to, looked up locally before downloading.
                Rectangle {
                    id: linkPreview
                    readonly property var info: localDownload.preview.url === downloadUrl.text.trim() ? localDownload.preview : ({})
                    readonly property bool lookingUp: localDownload.probing || probeDelay.running
                    visible: /^https?:\/\/\S+\.\S+/.test(downloadUrl.text.trim())
                    Layout.fillWidth: true
                    implicitHeight: 124
                    radius: Theme.radius
                    color: Theme.field
                    border.color: Theme.line
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.fade } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 14
                        Rectangle {
                            Layout.preferredWidth: 184
                            Layout.fillHeight: true
                            radius: Theme.radiusSmall
                            color: Theme.canvas
                            clip: true
                            Image {
                                id: thumb
                                anchors.fill: parent
                                source: linkPreview.info.thumbnail || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Theme.reveal } }
                            }
                            SkeletonBlock { anchors.fill: parent; radius: 0; visible: thumb.status !== Image.Ready && (linkPreview.lookingUp || thumb.status === Image.Loading) }
                            ToolIcon { anchors.centerIn: parent; visible: thumb.status !== Image.Ready && !linkPreview.lookingUp && thumb.status !== Image.Loading; name: "gif"; tint: Theme.textFaint; width: 26; height: 26 }
                            Rectangle {
                                visible: (linkPreview.info.durationMs || 0) > 0
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 6
                                width: durationText.implicitWidth + 10
                                height: 18
                                radius: 4
                                color: Theme.chipScrim
                                Text { id: durationText; anchors.centerIn: parent; text: toolsPage.durationLabel(linkPreview.info.durationMs || 0); color: Theme.text; font.pixelSize: 10; font.weight: Font.DemiBold }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: linkPreview.info.title || (!linkPreview.lookingUp && linkPreview.info.error ? "Could not read this link" : "")
                                color: linkPreview.info.error && !linkPreview.info.title ? Theme.danger : Theme.text
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: [linkPreview.info.uploader, linkPreview.info.source].filter(function(part) { return part }).join(" · ")
                                color: Theme.textMuted
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: !localDownload.probing && !!linkPreview.info.error
                                text: "yt-dlp: " + (linkPreview.info.error || "") + (localDownload.ytDlpOutdated ? " — try updating yt-dlp" : "")
                                color: Theme.warning
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            // Title and byline skeleton while the link is looked up.
                            SkeletonBlock { Layout.alignment: Qt.AlignLeft; visible: linkPreview.lookingUp && !linkPreview.info.title; Layout.preferredWidth: 260; Layout.preferredHeight: 14 }
                            SkeletonBlock { Layout.alignment: Qt.AlignLeft; visible: linkPreview.lookingUp && !linkPreview.info.title; Layout.preferredWidth: 180; Layout.preferredHeight: 14 }
                            SkeletonBlock { Layout.alignment: Qt.AlignLeft; visible: linkPreview.lookingUp && !linkPreview.info.uploader; Layout.preferredWidth: 120; Layout.preferredHeight: 10 }
                            Item { Layout.fillWidth: true; Layout.preferredHeight: 0 }
                        }
                    }
                }
                Text { visible: !localDownload.available; text: "Install yt-dlp and FFmpeg locally, or set KADRON_YTDLP and KADRON_FFMPEG."; color: Theme.warning; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: Theme.radius
                    color: localDownload.ytDlpOutdated ? Theme.playheadWash : Theme.field
                    border.color: localDownload.ytDlpOutdated ? Theme.warning : Theme.line
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 6
                        spacing: 10
                        Text {
                            Layout.fillWidth: true
                            text: localDownload.updatingYtDlp || localDownload.updateText ? localDownload.updateText
                                  : !localDownload.ytDlpVersion ? "yt-dlp not found — Kadron can install its own copy"
                                  : "yt-dlp " + localDownload.ytDlpVersion + (localDownload.ytDlpAgeDays >= 0 ? " · " + localDownload.ytDlpAgeDays + " days old" : "")
                                    + (localDownload.ytDlpOutdated ? " — sites change often, update before downloading" : "")
                            color: localDownload.ytDlpOutdated ? Theme.warning : Theme.textMuted
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        EditorButton {
                            text: localDownload.updatingYtDlp ? "Updating…" : "Update yt-dlp"
                            iconName: "download"
                            primary: localDownload.ytDlpOutdated || !localDownload.ytDlpVersion
                            subtle: !localDownload.ytDlpOutdated && localDownload.ytDlpVersion.length > 0
                            enabled: !localDownload.updatingYtDlp && !localDownload.busy
                            onClicked: localDownload.updateYtDlp()
                        }
                    }
                }
                Text { text: "Format"; color: Theme.textMuted; font.pixelSize: 12 }
                ToolCombo {
                    id: downloadPreset
                    Layout.preferredWidth: 360
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        {label: "MP4 · best", value: "VIDEO_MP4_BEST"},
                        {label: "MP4 · 720p", value: "VIDEO_MP4_720P"},
                        {label: "MP4 · smaller file", value: "VIDEO_MP4_DISCORD"},
                        {label: "GIF · social", value: "VIDEO_GIF_SOCIAL"},
                        {label: "MP3 · 320 kbps", value: "AUDIO_MP3_320"},
                        {label: "MP3 · 192 kbps", value: "AUDIO_MP3_192"},
                        {label: "FLAC", value: "AUDIO_FLAC_BEST"},
                        {label: "WAV", value: "AUDIO_WAV_BEST"},
                        {label: "Opus · 96 kbps", value: "AUDIO_OPUS_96"},
                        {label: "Opus · best", value: "AUDIO_OPUS_BEST"}
                    ]
                }
                GridLayout {
                    visible: downloadPreset.currentValue === "VIDEO_GIF_SOCIAL"
                    columns: 4
                    columnSpacing: 12
                    rowSpacing: 7
                    Text { text: "Start (s)"; color: Theme.textMuted; font.pixelSize: 12 }
                    Text { text: "Duration (s)"; color: Theme.textMuted; font.pixelSize: 12 }
                    Text { text: "FPS"; color: Theme.textMuted; font.pixelSize: 12 }
                    Text { text: "Width (px)"; color: Theme.textMuted; font.pixelSize: 12 }
                    EditorField { id: downloadStart; text: "0"; validator: DoubleValidator { bottom: 0 }
                        Layout.preferredWidth: 120 }
                    EditorField { id: downloadDuration; text: "8"; validator: DoubleValidator { bottom: 1; top: 20 }
                        Layout.preferredWidth: 120 }
                    EditorField { id: downloadFps; text: "10"; validator: IntValidator { bottom: 5; top: 15 }
                        Layout.preferredWidth: 120 }
                    EditorField { id: downloadWidth; text: "480"; validator: IntValidator { bottom: 160; top: 720 }
                        Layout.preferredWidth: 120 }
                }
                RowLayout {
                    visible: downloadPreset.currentValue === "VIDEO_GIF_SOCIAL"
                    Text { text: "Max file size (MB)"; color: Theme.textMuted; font.pixelSize: 12 }
                    EditorField { id: downloadTarget; text: "8"; validator: DoubleValidator { bottom: 1; top: 25 }
                        Layout.preferredWidth: 120 }
                }
                EditorButton {
                    text: "Download"
                    primary: true
                    enabled: !localDownload.busy && downloadUrl.text.length > 0 && localDownload.available
                    onClicked: toolsPage.openDownloadSave()
                }
            }

            DropZone {
                visible: toolsPage.section >= 2 && toolsPage.section <= 4 && !toolsPage.hasSource
                Layout.fillWidth: true
                active: pageDrop.containsDrag
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
                            text: pageDrop.containsDrag ? "Drop to replace" : decodeURIComponent(toolsPage.filename(toolsPage.sourceUrl))
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideMiddle
                        }
                        EditorButton { text: "Change"; subtle: true; onClicked: sourceDialog.open() }
                        EditorButton { iconName: "close"; subtle: true; enabled: !localTools.busy; onClicked: toolsPage.sourceUrl = ""; ToolTip.visible: hovered; ToolTip.text: "Clear file" }
                    }
                }
                Text {
                    visible: !localTools.available
                    text: "FFmpeg and FFprobe are unavailable. Set their paths before processing."
                    color: Theme.warning
                    font.pixelSize: 12
                }
            }

            ColumnLayout {
                visible: toolsPage.section === 2 && toolsPage.hasSource
                Layout.fillWidth: true
                spacing: 12
                // Visual trimmer: the waveform with a draggable selection.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    EditorButton {
                        objectName: "audioPlayButton"
                        iconName: audioPreview.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
                        enabled: audioPreview.duration > 0
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 50
                        onClicked: toolsPage.toggleAudioPreview()
                    }
                    RangeStrip {
                        id: audioStrip
                        objectName: "audioStrip"
                        Layout.fillWidth: true
                        implicitHeight: 134
                        waveLoading: audioPreview.duration > 0 && waveform.length === 0
                        waveform: audioPreview.duration > 0 && thumbnails.revision >= 0 ? thumbnails.waveformFor(toolsPage.sourceUrl) : ""
                        durationMs: audioPreview.duration
                        startMs: toolsPage.audioStartMs
                        endMs: toolsPage.audioEndMs
                        positionMs: audioPreview.position
                        onRangeRequested: function(startMs, endMs) { toolsPage.setAudioRange(startMs, endMs) }
                        onSeekRequested: function(ms) { audioPreview.position = ms }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    Text {
                        text: audioPreview.duration > 0
                              ? "Selection " + toolsPage.clockLabel(toolsPage.audioEndMs - toolsPage.audioStartMs) + " of " + toolsPage.clockLabel(audioPreview.duration)
                              : audioPreview.mediaStatus === MediaPlayer.InvalidMedia ? "This file cannot be previewed; the range fields still apply." : "Reading the file…"
                        color: Theme.textSoft
                        font.pixelSize: 12
                        font.features: { "tnum": 1 }
                    }
                    Item { Layout.fillWidth: true }
                    ToolCheck { text: "Loop"; checked: toolsPage.audioLooping; onToggled: toolsPage.audioLooping = checked }
                    EditorButton {
                        text: "Whole file"
                        subtle: true
                        enabled: audioPreview.duration > 0 && (toolsPage.audioStartMs > 0 || toolsPage.audioEndMs < audioPreview.duration)
                        onClicked: { audioStart.text = "0"; audioEnd.text = "0" }
                    }
                }
                Text { text: "Output format"; color: Theme.textMuted; font.pixelSize: 12 }
                ToolCombo { id: audioFormat; model: ["MP3", "WAV", "FLAC", "Opus"]; Layout.preferredWidth: 250 }
                GridLayout {
                    columns: 3
                    columnSpacing: 14
                    rowSpacing: 7
                    Text { text: "Bitrate (kbps)"; color: Theme.textMuted; font.pixelSize: 12 }
                    Text { text: "Start (s)"; color: Theme.textMuted; font.pixelSize: 12 }
                    Text { text: "End (s, 0 = full)"; color: Theme.textMuted; font.pixelSize: 12 }
                    EditorField { id: audioBitrate; text: "192"; validator: IntValidator { bottom: 64; top: 320 }
                        Layout.preferredWidth: 155 }
                    EditorField { id: audioStart; text: "0"; validator: DoubleValidator { bottom: 0 }
                        Layout.preferredWidth: 155 }
                    EditorField { id: audioEnd; text: "0"; validator: DoubleValidator { bottom: 0 }
                        Layout.preferredWidth: 155 }
                }
                ToolCheck { id: audioNormalize; text: "Normalize loudness"; checked: false }
                EditorButton {
                    text: "Convert audio"
                    primary: true
                    enabled: toolsPage.sourceUrl.toString() && localTools.available && !localTools.busy
                    onClicked: toolsPage.beginLocal("audio")
                }
            }

            ColumnLayout {
                visible: toolsPage.section === 3 && toolsPage.hasSource
                Layout.fillWidth: true
                spacing: 12
                Text { text: "Output format"; color: Theme.textMuted; font.pixelSize: 12 }
                ToolCombo { id: compressFormat; model: toolsPage.isImage ? ["WebP", "JPG", "PNG", "GIF"] : ["MP4", "WebM", "GIF"]; Layout.preferredWidth: 250 }
                GridLayout {
                    columns: 3
                    columnSpacing: 14
                    rowSpacing: 7
                    Text { text: "Target size (MB, 0 = quality)"; color: Theme.textMuted; font.pixelSize: 12 }
                    Text { text: "Quality (1–100)"; color: Theme.textMuted; font.pixelSize: 12 }
                    Text { text: "Max width (px, 0 = original)"; color: Theme.textMuted; font.pixelSize: 12 }
                    EditorField { id: compressTarget; text: "8"; validator: DoubleValidator { bottom: 0 }
                        Layout.preferredWidth: 200 }
                    EditorField { id: compressQuality; text: "75"; validator: IntValidator { bottom: 1; top: 100 }
                        Layout.preferredWidth: 165 }
                    EditorField { id: compressWidth; text: "1280"; validator: IntValidator { bottom: 0 }
                        Layout.preferredWidth: 185 }
                }
                ToolCheck { id: compressNoAudio; visible: !toolsPage.isImage; text: "Remove audio" }
                EditorButton {
                    text: "Compress"
                    primary: true
                    enabled: toolsPage.sourceUrl.toString() && localTools.available && !localTools.busy
                    onClicked: toolsPage.beginLocal("compress")
                }
            }

            ColumnLayout {
                visible: toolsPage.section === 4 && toolsPage.hasSource
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 280
                    radius: 10
                    color: Theme.canvas
                    clip: true
                    VideoOutput { id: gifVideo; anchors.fill: parent; visible: gifPreview.hasVideo; fillMode: VideoOutput.PreserveAspectFit }
                    AnimatedImage { anchors.fill: parent; visible: toolsPage.gifSourceIsGif; source: visible ? toolsPage.sourceUrl : ""; fillMode: Image.PreserveAspectFit }
                    Rectangle {
                        visible: gifPreview.hasVideo
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 10
                        width: loopLabel.implicitWidth + 30
                        height: 24
                        radius: 12
                        color: Theme.chipScrim
                        ToolIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 13; height: 13; name: "loop"; tint: toolsPage.gifLooping ? Theme.accent : Theme.textMuted }
                        Text {
                            id: loopLabel
                            x: 25
                            anchors.verticalCenter: parent.verticalCenter
                            text: (toolsPage.gifLooping ? "Looping " : "Paused · ") + ((toolsPage.gifEndMs - toolsPage.gifStartMs) / 1000).toFixed(2) + " s"
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
                        iconName: gifPreview.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
                        enabled: gifPreview.hasVideo
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 29
                        onClicked: {
                            if (gifPreview.playbackState === MediaPlayer.PlayingState) {
                                toolsPage.gifLooping = false
                                gifPreview.pause()
                            } else {
                                toolsPage.gifLooping = true
                                if (gifPreview.position < toolsPage.gifStartMs || gifPreview.position >= toolsPage.gifEndMs) gifPreview.position = toolsPage.gifStartMs
                                gifPreview.play()
                            }
                        }
                    }
                    RangeStrip {
                        Layout.fillWidth: true
                        frames: gifPreview.duration > 0 && thumbnails.revision >= 0 ? thumbnails.framesFor(toolsPage.sourceUrl, gifPreview.duration) : []
                        durationMs: gifPreview.duration
                        startMs: toolsPage.gifStartMs
                        endMs: toolsPage.gifEndMs
                        positionMs: gifPreview.position
                        onRangeRequested: function(startMs, endMs) { toolsPage.setGifRange(startMs, endMs) }
                        onSeekRequested: function(ms) { gifPreview.position = ms }
                    }
                }
                GridLayout {
                    columns: 3
                    columnSpacing: 14
                    rowSpacing: 7
                    Text { text: "Start (s)"; color: Theme.textMuted; font.pixelSize: 12 }
                    Text { text: "Duration (s)"; color: Theme.textMuted; font.pixelSize: 12 }
                    Text { text: "FPS"; color: Theme.textMuted; font.pixelSize: 12 }
                    EditorField { id: gifStart; text: "0"; validator: DoubleValidator { bottom: 0 }
                        Layout.preferredWidth: 160 }
                    EditorField { id: gifDuration; text: "8"; validator: DoubleValidator { bottom: 0.1 }
                        Layout.preferredWidth: 160 }
                    EditorField { id: gifFps; text: "10"; validator: IntValidator { bottom: 5; top: 30 }
                        Layout.preferredWidth: 160 }
                    Text { text: "Width (px)"; color: Theme.textMuted; font.pixelSize: 12 }
                    Text { text: "Max file size (MB, 0 = none)"; color: Theme.textMuted; font.pixelSize: 12 }
                    Item { Layout.preferredWidth: 160; Layout.preferredHeight: 1 }
                    EditorField { id: gifWidth; text: "480"; validator: IntValidator { bottom: 120; top: 1080 }
                        Layout.preferredWidth: 160 }
                    EditorField { id: gifTarget; text: "8"; validator: DoubleValidator { bottom: 0 }
                        Layout.preferredWidth: 160 }
                }
                EditorButton {
                    text: "Create GIF"
                    primary: true
                    enabled: toolsPage.sourceUrl.toString() && localTools.available && !localTools.busy
                    onClicked: toolsPage.beginLocal("gif")
                }
                Text { visible: toolsPage.resultSection === "gif" && localTools.outputUrl.toString().length > 0 && !localTools.busy; text: "Result preview · " + toolsPage.sizeLabel(localTools.outputBytes); color: Theme.textMuted; font.pixelSize: 12 }
                Rectangle {
                    visible: toolsPage.resultSection === "gif" && localTools.outputUrl.toString().length > 0 && !localTools.busy
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? 252 : 0
                    radius: 10
                    color: Theme.canvas
                    clip: true
                    AnimatedImage { anchors.fill: parent; source: parent.visible ? localTools.outputUrl : ""; fillMode: Image.PreserveAspectFit }
                }
            }

            ColumnLayout {
                visible: toolsPage.section === 5
                Layout.fillWidth: true
                spacing: 12
                // Modes mirror the web PDF editor.
                Row {
                    spacing: 6
                    Repeater {
                        model: [["edit", "Edit pages", "pdf"], ["merge", "Merge", "plus"], ["split", "Extract pages", "split"], ["images-to-pdf", "Images to PDF", "file"]]
                        delegate: EditorButton {
                            required property var modelData
                            text: modelData[1]
                            iconName: modelData[2]
                            primary: toolsPage.pdfMode === modelData[0]
                            subtle: toolsPage.pdfMode !== modelData[0]
                            onClicked: toolsPage.setPdfMode(modelData[0])
                        }
                    }
                }
                DropZone {
                    visible: toolsPage.pdfFiles.length === 0
                    Layout.fillWidth: true
                    implicitHeight: 220
                    active: pageDrop.containsDrag
                    iconName: toolsPage.pdfMode === "images-to-pdf" ? "drop" : "pdf"
                    heading: toolsPage.pdfMode === "images-to-pdf" ? "Drop images to combine" : toolsPage.pdfMode === "merge" ? "Drop the PDFs to merge" : "Drop a PDF"
                    formats: toolsPage.pdfMode === "images-to-pdf" ? "JPG · PNG · WEBP · BMP · TIFF" : toolsPage.pdfMode === "edit" ? "PDF · reorder, rotate and remove pages visually" : "PDF"
                    onBrowseRequested: pdfDialog.open()
                }
                Rectangle {
                    visible: toolsPage.pdfFiles.length > 0
                    Layout.fillWidth: true
                    implicitHeight: 54
                    radius: Theme.radius
                    color: pageDrop.containsDrag ? Theme.accentWash : Theme.field
                    border.color: pageDrop.containsDrag ? Theme.accent : Theme.line
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        spacing: 10
                        ToolIcon { name: "pdf"; tint: Theme.accent }
                        Text {
                            Layout.fillWidth: true
                            text: pageDrop.containsDrag ? "Drop to replace" : toolsPage.pdfFiles.map(function(file) { return decodeURIComponent(toolsPage.filename(file)) }).join(", ")
                            color: Theme.text
                            font.pixelSize: 13
                            elide: Text.ElideMiddle
                        }
                        Text {
                            text: toolsPage.pdfMode === "edit" ? (localPdf.loadingPages ? "Reading pages…" : localPdf.pageImages.length + " pages")
                                  : toolsPage.pdfFiles.length + (toolsPage.pdfFiles.length === 1 ? " file" : " files")
                            color: Theme.textMuted
                            font.pixelSize: 11
                        }
                        EditorButton { text: "Change"; subtle: true; onClicked: pdfDialog.open() }
                        EditorButton { iconName: "close"; subtle: true; enabled: !localPdf.busy; onClicked: toolsPage.pdfFiles = [] }
                    }
                }
                Text { visible: !localPdf.qpdfAvailable && toolsPage.pdfMode !== "images-to-pdf"; text: "Install qpdf locally or set KADRON_QPDF for this operation."; color: Theme.warning; font.pixelSize: 12 }
                Text { visible: toolsPage.pdfMode === "edit" && localPdf.pagesError.length > 0; text: localPdf.pagesError; color: Theme.danger; font.pixelSize: 12 }

                // Visual page editor.
                RowLayout {
                    visible: toolsPage.pdfMode === "edit" && pageModel.count > 0
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: pageModel.count + " pages" + (toolsPage.pdfSelected > 0 ? " · " + toolsPage.pdfSelected + " selected" : " · click to select, drag to reorder, double-click to preview")
                        color: Theme.textMuted
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    EditorButton { text: toolsPage.pdfSelected === pageModel.count ? "Select none" : "Select all"; subtle: true; onClicked: toolsPage.selectAllPages(toolsPage.pdfSelected !== pageModel.count) }
                    EditorButton { iconName: "rotateLeft"; subtle: true; enabled: toolsPage.pdfSelected > 0; onClicked: toolsPage.rotateSelected(-90); ToolTip.visible: hovered; ToolTip.text: "Rotate selected left" }
                    EditorButton { iconName: "rotateRight"; subtle: true; enabled: toolsPage.pdfSelected > 0; onClicked: toolsPage.rotateSelected(90); ToolTip.visible: hovered; ToolTip.text: "Rotate selected right" }
                    EditorButton { iconName: "trash"; subtle: true; danger: true; enabled: toolsPage.pdfSelected > 0 && toolsPage.pdfSelected < pageModel.count; onClicked: toolsPage.deleteSelected(); ToolTip.visible: hovered; ToolTip.text: "Remove selected pages" }
                    EditorButton { text: "Reset"; subtle: true; enabled: toolsPage.pdfEdited; onClicked: toolsPage.resetPages() }
                }
                Item {
                    visible: toolsPage.pdfMode === "edit" && (pageModel.count > 0 || localPdf.loadingPages)
                    Layout.fillWidth: true
                    implicitHeight: localPdf.loadingPages ? 220 : pageGrid.contentHeight + 8
                    // Loading skeleton in the grid's shape.
                    Flow {
                        anchors.fill: parent
                        visible: localPdf.loadingPages
                        spacing: 14
                        Repeater {
                            model: 5
                            delegate: SkeletonBlock { width: 136; height: 194; radius: 10 }
                        }
                    }
                    GridView {
                        id: pageGrid
                        anchors.fill: parent
                        visible: !localPdf.loadingPages
                        interactive: false
                        cellWidth: 150
                        cellHeight: 214
                        model: pageModel
                        displaced: Transition { SmoothSpring { properties: "x,y" } }
                        delegate: DropArea {
                            id: slot
                            required property int index
                            required property int page
                            required property int rotation
                            required property bool selected
                            width: pageGrid.cellWidth
                            height: pageGrid.cellHeight
                            onEntered: function(drag) {
                                if (drag.source && drag.source.visualIndex !== slot.index) {
                                    pageModel.move(drag.source.visualIndex, slot.index, 1)
                                    toolsPage.pdfEdited = true
                                }
                            }
                            Rectangle {
                                id: pageCard
                                readonly property int visualIndex: slot.index
                                width: 136
                                height: 200
                                anchors.horizontalCenter: dragging ? undefined : parent.horizontalCenter
                                anchors.top: dragging ? undefined : parent.top
                                readonly property bool dragging: cardMouse.drag.active
                                radius: 10
                                color: slot.selected ? Theme.accentWash : cardMouse.containsMouse ? Theme.card : Theme.field
                                border.width: slot.selected ? 2 : 1
                                border.color: slot.selected ? Theme.accent : Theme.line
                                scale: dragging ? 1.05 : 1
                                z: dragging ? 10 : 1
                                Behavior on scale { SnapSpring {} }
                                Behavior on color { ColorAnimation { duration: Theme.fadeFast } }
                                Drag.active: dragging
                                Drag.source: pageCard
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2
                                states: State {
                                    when: pageCard.dragging
                                    ParentChange { target: pageCard; parent: pageGrid }
                                }
                                Item {
                                    id: pageFrame
                                    x: 10
                                    y: 10
                                    width: parent.width - 20
                                    height: parent.height - 40
                                    clip: true
                                    Image {
                                        id: pageImage
                                        anchors.centerIn: parent
                                        readonly property bool sideways: ((slot.rotation % 180) + 180) % 180 === 90
                                        width: sideways ? pageFrame.height : pageFrame.width
                                        height: sideways ? pageFrame.width : pageFrame.height
                                        source: localPdf.pageImages[slot.page - 1] || ""
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        rotation: slot.rotation
                                        Behavior on rotation { SnapSpring { epsilon: 0.2 } }
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 8
                                    text: (slot.index + 1) + (slot.page !== slot.index + 1 ? "  ·  p. " + slot.page : "")
                                    color: slot.selected ? Theme.accentSoft : Theme.textMuted
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                MouseArea {
                                    id: cardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    drag.target: pageCard
                                    cursorShape: pageCard.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                    onClicked: pageModel.setProperty(slot.index, "selected", !slot.selected)
                                    onDoubleClicked: toolsPage.openPagePreview(slot.page, slot.rotation)
                                    onReleased: pageCard.Drag.drop()
                                }
                                // Per-page actions on hover.
                                Row {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 6
                                    spacing: 2
                                    opacity: cardMouse.containsMouse && !pageCard.dragging ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.fadeFast } }
                                    Repeater {
                                        model: [["rotateLeft", -90], ["rotateRight", 90], ["trash", 0]]
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 26
                                            height: 26
                                            radius: 7
                                            color: actionMouse.containsMouse ? Theme.pressed : Theme.chipScrim
                                            ToolIcon { anchors.centerIn: parent; width: 15; height: 15; name: parent.modelData[0]; tint: parent.modelData[0] === "trash" ? Theme.danger : Theme.text }
                                            MouseArea {
                                                id: actionMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (parent.modelData[0] === "trash") {
                                                        if (pageModel.count > 1) { pageModel.remove(slot.index); toolsPage.pdfEdited = true }
                                                    } else {
                                                        pageModel.setProperty(slot.index, "rotation", slot.rotation + parent.modelData[1])
                                                        toolsPage.pdfEdited = true
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Other modes keep their compact forms.
                Text { text: "Pages (e.g. 1,3-5)"; visible: toolsPage.pdfMode === "split" && toolsPage.pdfFiles.length > 0; color: Theme.textMuted; font.pixelSize: 12 }
                EditorField { id: pdfPages; visible: toolsPage.pdfMode === "split" && toolsPage.pdfFiles.length > 0; Layout.preferredWidth: 280; placeholderText: "1,3-5" }
                Text { text: "Documents stay on this device."; color: Theme.textFaint; font.pixelSize: 11 }
                EditorButton {
                    text: toolsPage.pdfMode === "edit" ? "Save PDF" : toolsPage.pdfMode === "merge" ? "Merge PDFs" : toolsPage.pdfMode === "split" ? "Extract pages" : "Create PDF"
                    iconName: "save"
                    primary: true
                    enabled: !localPdf.busy && (toolsPage.pdfMode === "edit" ? pageModel.count > 0 && localPdf.qpdfAvailable
                             : toolsPage.pdfFiles.length > 0 && (localPdf.qpdfAvailable || toolsPage.pdfMode === "images-to-pdf") && (toolsPage.pdfMode !== "split" || pdfPages.text.trim().length > 0))
                    onClicked: toolsPage.openPdfSave()
                }
            }

            // QR: live preview while typing, styled and exported on this device.
            RowLayout {
                visible: toolsPage.section === 6
                Layout.fillWidth: true
                spacing: 24
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 12
                    Text { visible: !localQr.available; text: "Install qrencode locally or set KADRON_QRENCODE."; color: Theme.warning; font.pixelSize: 12 }
                    Text { text: "Text or URL"; color: Theme.textMuted; font.pixelSize: 12 }
                    EditorField {
                        id: qrText
                        Layout.fillWidth: true
                        placeholderText: "https://..."
                        onTextChanged: qrDelay.restart()
                    }
                    Timer { id: qrDelay; interval: 150; onTriggered: localQr.update(qrText.text, toolsPage.qrLevel) }
                    Text { text: "Colors"; color: Theme.textMuted; font.pixelSize: 12 }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: [["#000000", "#ffffff"], ["#ffffff", "#000000"], ["#1a5fb4", "#ffffff"], ["#ffffff", "#1a5fb4"], ["#17200e", "#c9f27a"], ["#c0392b", "#fef9e7"], ["#1e272e", "#f5f6fa"]]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool chosen: toolsPage.qrFg === modelData[0] && toolsPage.qrBg === modelData[1]
                                width: 36
                                height: 36
                                radius: 9
                                color: modelData[1]
                                border.width: chosen ? 2 : 1
                                border.color: chosen ? Theme.accent : Theme.lineStrong
                                scale: swatchMouse.pressed ? 0.92 : 1
                                Behavior on scale { SnapSpring {} }
                                Rectangle { anchors.centerIn: parent; width: 16; height: 16; radius: 3; color: parent.modelData[0] }
                                MouseArea { id: swatchMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { toolsPage.qrFg = parent.modelData[0]; toolsPage.qrBg = parent.modelData[1] } }
                            }
                        }
                    }
                    RowLayout {
                        spacing: 10
                        Text { text: "Foreground"; color: Theme.textMuted; font.pixelSize: 12 }
                        EditorField {
                            Layout.preferredWidth: 100
                            text: toolsPage.qrFg
                            validator: RegularExpressionValidator { regularExpression: /#[0-9a-fA-F]{6}/ }
                            onEditingFinished: toolsPage.qrFg = text.toLowerCase()
                        }
                        EditorButton { iconName: "loop"; subtle: true; onClicked: { var fg = toolsPage.qrFg; toolsPage.qrFg = toolsPage.qrBg; toolsPage.qrBg = fg } ToolTip.visible: hovered; ToolTip.text: "Swap colors" }
                        Text { text: "Background"; color: Theme.textMuted; font.pixelSize: 12 }
                        EditorField {
                            Layout.preferredWidth: 100
                            text: toolsPage.qrBg
                            validator: RegularExpressionValidator { regularExpression: /#[0-9a-fA-F]{6}/ }
                            onEditingFinished: toolsPage.qrBg = text.toLowerCase()
                        }
                    }
                    Text { text: "Error correction"; color: Theme.textMuted; font.pixelSize: 12 }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [["L", "7%"], ["M", "15%"], ["Q", "25%"], ["H", "30%"]]
                            delegate: EditorButton {
                                required property var modelData
                                text: modelData[0] + "  " + modelData[1]
                                primary: toolsPage.qrLevel === modelData[0]
                                onClicked: { toolsPage.qrLevel = modelData[0]; localQr.update(qrText.text, toolsPage.qrLevel) }
                            }
                        }
                    }
                    Text { text: "Export size"; color: Theme.textMuted; font.pixelSize: 12 }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [256, 512, 1024, 2048]
                            delegate: EditorButton {
                                required property int modelData
                                text: modelData + " px"
                                primary: toolsPage.qrSize === modelData
                                onClicked: toolsPage.qrSize = modelData
                            }
                        }
                    }
                    RowLayout {
                        Layout.topMargin: 6
                        spacing: 8
                        EditorButton { text: "Save PNG"; iconName: "save"; primary: true; enabled: localQr.modules > 0; onClicked: toolsPage.openQrSave("png") }
                        EditorButton { text: "Save SVG"; iconName: "save"; enabled: localQr.modules > 0; onClicked: toolsPage.openQrSave("svg") }
                        EditorButton { text: "Open file"; subtle: true; visible: localQr.outputUrl.toString().length > 0; onClicked: Qt.openUrlExternally(localQr.outputUrl) }
                    }
                    Text { visible: localQr.errorText.length > 0; text: localQr.errorText; color: Theme.danger; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                }
                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    spacing: 8
                    Rectangle {
                        implicitWidth: 260
                        implicitHeight: 260
                        radius: 14
                        color: localQr.modules > 0 ? toolsPage.qrBg : Theme.field
                        border.color: Theme.line
                        Behavior on color { ColorAnimation { duration: Theme.fade } }
                        Image {
                            id: qrPreview
                            anchors.fill: parent
                            anchors.margins: 6
                            visible: localQr.modules > 0
                            source: localQr.modules > 0 ? "image://qr/" + localQr.revision + "?fg=" + toolsPage.qrFg.slice(1) + "&bg=" + toolsPage.qrBg.slice(1) + "&size=496" : ""
                            sourceSize: Qt.size(496, 496)
                            smooth: false
                            cache: false
                            scale: status === Image.Ready ? 1 : 0.96
                            Behavior on scale { SnapSpring {} }
                        }
                        Column {
                            anchors.centerIn: parent
                            visible: localQr.modules === 0
                            spacing: 8
                            ToolIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "qr"; tint: Theme.textFaint; width: 34; height: 34 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Start typing to generate"; color: Theme.textFaint; font.pixelSize: 12 }
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: localQr.modules > 0 ? localQr.modules + " × " + localQr.modules + " modules · exports " + toolsPage.qrSize + " px" : "Preview"
                        color: Theme.textFaint
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                visible: localTools.busy || localTools.errorText.length > 0 || localTools.outputUrl.toString().length > 0 || localDownload.busy || localDownload.errorText.length > 0 || localDownload.outputUrl.toString().length > 0 || localPdf.busy || localPdf.errorText.length > 0 || localPdf.outputUrl.toString().length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.line
                Layout.topMargin: 8
            }
            RowLayout {
                visible: toolsPage.section >= 2 && toolsPage.section <= 4 && (localTools.busy || localTools.errorText || localTools.outputUrl.toString())
                Layout.fillWidth: true
                spacing: 10
                Text { text: localTools.errorText || localTools.stage; color: localTools.errorText ? Theme.danger : Theme.textSoft; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                Text { text: localTools.busy ? localTools.progress + "%" : localTools.outputUrl.toString() ? toolsPage.sizeLabel(localTools.outputBytes) : ""; color: Theme.textMuted; font.pixelSize: 12 }
                EditorButton { text: "Cancel"; visible: localTools.busy; danger: true; onClicked: localTools.cancel() }
            }
            StudioProgress { visible: toolsPage.section >= 2 && toolsPage.section <= 4 && localTools.busy; value: localTools.progress / 100; Layout.fillWidth: true }
            RowLayout {
                visible: toolsPage.section >= 2 && toolsPage.section <= 4 && toolsPage.resultSection === (toolsPage.section === 2 ? "audio" : toolsPage.section === 3 ? "compress" : "gif") && localTools.outputUrl.toString().length > 0 && !localTools.busy
                Layout.fillWidth: true
                Text { text: toolsPage.filename(localTools.outputUrl); color: Theme.textSoft; font.pixelSize: 12; Layout.fillWidth: true }
                EditorButton { text: "Open file"; onClicked: Qt.openUrlExternally(localTools.outputUrl) }
                EditorButton { text: "Publish"; onClicked: toolsPage.publishFile(localTools.outputUrl) }
            }
            RowLayout {
                visible: toolsPage.section === 1 ? (localDownload.busy || localDownload.errorText || localDownload.outputUrl.toString()) : toolsPage.section === 5 && (localPdf.busy || localPdf.errorText || localPdf.outputUrl.toString())
                Layout.fillWidth: true
                spacing: 10
                Text { text: toolsPage.section === 1 ? (localDownload.errorText || localDownload.stage) : (localPdf.errorText || localPdf.stage); color: toolsPage.section === 1 ? (localDownload.errorText ? Theme.danger : Theme.textSoft) : (localPdf.errorText ? Theme.danger : Theme.textSoft); font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                Text { text: toolsPage.section === 1 ? (localDownload.busy ? localDownload.progress + "%" : localDownload.outputUrl.toString() ? toolsPage.sizeLabel(localDownload.outputBytes) : "") : (localPdf.outputUrl.toString() ? toolsPage.sizeLabel(localPdf.outputBytes) : ""); color: Theme.textMuted; font.pixelSize: 12 }
                EditorButton { text: "Cancel"; visible: toolsPage.section === 1 ? localDownload.busy : localPdf.busy; danger: true; onClicked: toolsPage.section === 1 ? localDownload.cancel() : localPdf.cancel() }
            }
            StudioProgress { visible: toolsPage.section === 1 && localDownload.busy; value: localDownload.progress / 100; Layout.fillWidth: true }
            RowLayout {
                visible: (toolsPage.section === 1 && toolsPage.resultSection === "download" && localDownload.outputUrl.toString().length > 0 && !localDownload.busy) || (toolsPage.section === 5 && toolsPage.resultSection === "pdf" && localPdf.outputUrl.toString().length > 0 && !localPdf.busy)
                Layout.fillWidth: true
                Text { text: toolsPage.filename(toolsPage.section === 1 ? localDownload.outputUrl : localPdf.outputUrl); color: Theme.textSoft; font.pixelSize: 12; Layout.fillWidth: true }
                EditorButton { text: "Open file"; onClicked: Qt.openUrlExternally(toolsPage.section === 1 ? localDownload.outputUrl : localPdf.outputUrl) }
                EditorButton { text: "Publish"; onClicked: toolsPage.publishFile(toolsPage.section === 1 ? localDownload.outputUrl : localPdf.outputUrl) }
            }
            Item { Layout.preferredHeight: 8 }
        }
        }
    }
}
