import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: toolsPage
    property int section: 1
    property url sourceUrl: ""
    property var pdfFiles: []
    property string resultSection: ""
    property string pendingAction: ""
    property bool isImage: /\.(jpe?g|png|webp|bmp|tiff?)$/i.test(sourceUrl.toString())
    property string selectedFormat: section === 2 ? audioFormat.currentText.toLowerCase()
                                  : section === 3 ? compressFormat.currentText.toLowerCase() : "gif"
    signal publishFile(url fileUrl)

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
    function beginRemote() {
        resultSection = section === 1 ? "download" : "pdf"
        if (section === 1)
            remoteJobs.download(downloadUrl.text, downloadPreset.currentValue,
                                Number(downloadStart.text), Number(downloadDuration.text),
                                Number(downloadFps.text), Number(downloadWidth.text), Number(downloadTarget.text))
        else
            remoteJobs.pdfAction(pdfAction.currentValue, pdfFiles, pdfPages.text, Number(pdfRotation.currentText))
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
        id: remoteSave
        title: "Save server result"
        fileMode: FileDialog.SaveFile
        onAccepted: remoteJobs.saveResult(selectedFile)
    }
    FileDialog {
        id: pdfDialog
        title: "Choose documents"
        fileMode: FileDialog.OpenFiles
        nameFilters: pdfAction.currentValue === "images-to-pdf" ? ["Images (*.jpg *.jpeg *.png)"] : ["PDF files (*.pdf)"]
        onAccepted: toolsPage.pdfFiles = selectedFiles
    }
    FileDialog {
        id: qrSave
        title: "Save QR code"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "png"
        nameFilters: ["PNG image (*.png)"]
        onAccepted: toolsClient.saveQr(selectedFile)
    }

    Rectangle {
        anchors.fill: parent
        color: "#181a1b"
    }
    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: ScrollBar {
            width: 8
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle { implicitWidth: 6; radius: 3; color: "#677477" }
        }
        ColumnLayout {
            width: Math.min(scroll.availableWidth - 54, 1080)
            x: Math.max(27, (scroll.availableWidth - width) / 2)
            spacing: 14

            Item { Layout.preferredHeight: 14 }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: ["", "Download", "Audio conversion", "Compress", "GIF maker", "PDF tools", "QR code"][toolsPage.section]
                    color: "#eef1f0"
                    font.pixelSize: 23
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                Text {
                    text: toolsPage.section === 1 || toolsPage.section >= 5 ? "TOOLS SERVER" : "LOCAL PROCESSING"
                    color: "#9eb4b4"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#3b4345" }

            RowLayout {
                visible: toolsPage.section === 1 || toolsPage.section >= 5
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Server"; color: "#cbd2d0"; font.pixelSize: 12; Layout.preferredWidth: 90 }
                EditorField {
                    id: serverAddress
                    Layout.fillWidth: true
                    text: toolsClient.serverUrl
                    placeholderText: "https://tools.example.com"
                    onEditingFinished: toolsClient.serverUrl = text
                }
                EditorButton {
                    text: "Connect"
                    enabled: !toolsClient.busy
                    onClicked: { toolsClient.serverUrl = serverAddress.text; toolsClient.testConnection() }
                }
                Text {
                    text: toolsClient.connected ? "Connected" : "Offline"
                    color: toolsClient.connected ? "#a9d5b7" : "#aeb6b4"
                    font.pixelSize: 11
                }
            }
            Text {
                visible: (toolsPage.section === 1 || toolsPage.section >= 5) && toolsClient.errorText.length > 0
                text: toolsClient.errorText
                color: "#e7aaa4"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            ColumnLayout {
                visible: toolsPage.section === 1
                Layout.fillWidth: true
                spacing: 12
                Text { text: "Source URL"; color: "#bdc9c7"; font.pixelSize: 12 }
                EditorField { id: downloadUrl; Layout.fillWidth: true; placeholderText: "https://..." }
                Text { text: "Format"; color: "#bdc9c7"; font.pixelSize: 12 }
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
                    Text { text: "Start (s)"; color: "#bdc9c7"; font.pixelSize: 12 }
                    Text { text: "Duration (s)"; color: "#bdc9c7"; font.pixelSize: 12 }
                    Text { text: "FPS"; color: "#bdc9c7"; font.pixelSize: 12 }
                    Text { text: "Width (px)"; color: "#bdc9c7"; font.pixelSize: 12 }
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
                    Text { text: "Max file size (MB)"; color: "#bdc9c7"; font.pixelSize: 12 }
                    EditorField { id: downloadTarget; text: "8"; validator: DoubleValidator { bottom: 1; top: 25 }
                        Layout.preferredWidth: 120 }
                }
                EditorButton {
                    text: "Download"
                    primary: true
                    enabled: !remoteJobs.busy && downloadUrl.text.length > 0 && toolsClient.serverUrl.length > 0 && serverAddress.text.trim() === toolsClient.serverUrl
                    onClicked: toolsPage.beginRemote()
                }
            }

            ColumnLayout {
                visible: toolsPage.section >= 2 && toolsPage.section <= 4
                Layout.fillWidth: true
                spacing: 12
                Text { text: "Source file"; color: "#bdc9c7"; font.pixelSize: 12 }
                RowLayout {
                    Layout.fillWidth: true
                    EditorField { Layout.fillWidth: true; readOnly: true; text: toolsPage.sourceUrl.toString() ? toolsPage.sourceUrl.toLocalFile() : ""; placeholderText: "Choose media" }
                    EditorButton { text: "Browse"; onClicked: sourceDialog.open() }
                }
                Text {
                    visible: !localTools.available
                    text: "FFmpeg and FFprobe are unavailable. Set their paths before processing."
                    color: "#e2bb8e"
                    font.pixelSize: 12
                }
            }

            ColumnLayout {
                visible: toolsPage.section === 2
                Layout.fillWidth: true
                spacing: 12
                Text { text: "Output format"; color: "#bdc9c7"; font.pixelSize: 12 }
                ToolCombo { id: audioFormat; model: ["MP3", "WAV", "FLAC", "Opus"]; Layout.preferredWidth: 250 }
                GridLayout {
                    columns: 3
                    columnSpacing: 14
                    rowSpacing: 7
                    Text { text: "Bitrate (kbps)"; color: "#bdc9c7"; font.pixelSize: 12 }
                    Text { text: "Start (s)"; color: "#bdc9c7"; font.pixelSize: 12 }
                    Text { text: "End (s, 0 = full)"; color: "#bdc9c7"; font.pixelSize: 12 }
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
                visible: toolsPage.section === 3
                Layout.fillWidth: true
                spacing: 12
                Text { text: "Output format"; color: "#bdc9c7"; font.pixelSize: 12 }
                ToolCombo { id: compressFormat; model: toolsPage.isImage ? ["WebP", "JPG", "PNG", "GIF"] : ["MP4", "WebM", "GIF"]; Layout.preferredWidth: 250 }
                GridLayout {
                    columns: 3
                    columnSpacing: 14
                    rowSpacing: 7
                    Text { text: "Target size (MB, 0 = quality)"; color: "#bdc9c7"; font.pixelSize: 12 }
                    Text { text: "Quality (1–100)"; color: "#bdc9c7"; font.pixelSize: 12 }
                    Text { text: "Max width (px, 0 = original)"; color: "#bdc9c7"; font.pixelSize: 12 }
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
                visible: toolsPage.section === 4
                Layout.fillWidth: true
                spacing: 12
                GridLayout {
                    columns: 3
                    columnSpacing: 14
                    rowSpacing: 7
                    Text { text: "Start (s)"; color: "#bdc9c7"; font.pixelSize: 12 }
                    Text { text: "Duration (s)"; color: "#bdc9c7"; font.pixelSize: 12 }
                    Text { text: "FPS"; color: "#bdc9c7"; font.pixelSize: 12 }
                    EditorField { id: gifStart; text: "0"; validator: DoubleValidator { bottom: 0 }
                        Layout.preferredWidth: 160 }
                    EditorField { id: gifDuration; text: "8"; validator: DoubleValidator { bottom: 0.1 }
                        Layout.preferredWidth: 160 }
                    EditorField { id: gifFps; text: "10"; validator: IntValidator { bottom: 5; top: 30 }
                        Layout.preferredWidth: 160 }
                    Text { text: "Width (px)"; color: "#bdc9c7"; font.pixelSize: 12 }
                    Text { text: "Max file size (MB, 0 = none)"; color: "#bdc9c7"; font.pixelSize: 12 }
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
            }

            ColumnLayout {
                visible: toolsPage.section === 5
                Layout.fillWidth: true
                spacing: 12
                Text { text: "Operation"; color: "#bdc9c7"; font.pixelSize: 12 }
                ToolCombo {
                    id: pdfAction
                    Layout.preferredWidth: 280
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        {label: "Merge PDFs", value: "merge"},
                        {label: "Split pages", value: "split"},
                        {label: "Rotate pages", value: "rotate"},
                        {label: "Remove pages", value: "remove-pages"},
                        {label: "Reorder pages", value: "reorder"},
                        {label: "Images to PDF", value: "images-to-pdf"}
                    ]
                    onCurrentIndexChanged: toolsPage.pdfFiles = []
                }
                Text { text: "Documents"; color: "#bdc9c7"; font.pixelSize: 12 }
                RowLayout {
                    Layout.fillWidth: true
                    EditorField { Layout.fillWidth: true; readOnly: true; text: toolsPage.pdfFiles.length ? toolsPage.pdfFiles.map(function(file) { return toolsPage.filename(file) }).join(", ") : ""; placeholderText: "Choose files" }
                    EditorButton { text: "Browse"; onClicked: pdfDialog.open() }
                }
                Text { text: "Documents are uploaded to your Tools server."; color: "#aebbb9"; font.pixelSize: 11 }
                Text { text: "Pages (e.g. 1,3-5)"; visible: pdfAction.currentValue !== "merge" && pdfAction.currentValue !== "images-to-pdf"; color: "#bdc9c7"; font.pixelSize: 12 }
                EditorField { id: pdfPages; visible: pdfAction.currentValue !== "merge" && pdfAction.currentValue !== "images-to-pdf"; Layout.preferredWidth: 280; placeholderText: "1,3-5" }
                ToolCombo { id: pdfRotation; visible: pdfAction.currentValue === "rotate"; model: [90, 180, 270]; Layout.preferredWidth: 180 }
                EditorButton {
                    text: "Process PDF"
                    primary: true
                    enabled: toolsPage.pdfFiles.length > 0 && !remoteJobs.busy && toolsClient.serverUrl.length > 0 && serverAddress.text.trim() === toolsClient.serverUrl
                    onClicked: toolsPage.beginRemote()
                }
            }

            ColumnLayout {
                visible: toolsPage.section === 6
                Layout.fillWidth: true
                spacing: 12
                Text { text: "Text or URL"; color: "#bdc9c7"; font.pixelSize: 12 }
                EditorField { id: qrText; Layout.fillWidth: true; placeholderText: "https://..." }
                RowLayout {
                    Text { text: "Image size (px)"; color: "#bdc9c7"; font.pixelSize: 12 }
                    EditorField { id: qrSize; text: "512"; validator: IntValidator { bottom: 100; top: 2000 }
                        Layout.preferredWidth: 130 }
                    EditorButton { text: "Generate"; primary: true; enabled: qrText.text.length > 0 && !toolsClient.busy && toolsClient.serverUrl.length > 0 && serverAddress.text.trim() === toolsClient.serverUrl; onClicked: toolsClient.generateQr(qrText.text, Number(qrSize.text)) }
                }
                Image { source: toolsClient.qrPreviewUrl; Layout.preferredWidth: 240; Layout.preferredHeight: 240; fillMode: Image.PreserveAspectFit; visible: source.toString().length > 0; cache: false }
                EditorButton { text: "Save PNG"; visible: toolsClient.qrPreviewUrl.toString().length > 0; onClicked: qrSave.open() }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#3b4345"; Layout.topMargin: 8 }
            RowLayout {
                visible: toolsPage.section >= 2 && toolsPage.section <= 4 && (localTools.busy || localTools.errorText || localTools.outputUrl.toString())
                Layout.fillWidth: true
                spacing: 10
                Text { text: localTools.errorText || localTools.stage; color: localTools.errorText ? "#e7aaa4" : "#d4dfdc"; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                Text { text: localTools.busy ? localTools.progress + "%" : localTools.outputUrl.toString() ? toolsPage.sizeLabel(localTools.outputBytes) : ""; color: "#b5c4c1"; font.pixelSize: 12 }
                EditorButton { text: "Cancel"; visible: localTools.busy; danger: true; onClicked: localTools.cancel() }
            }
            ProgressBar { visible: toolsPage.section >= 2 && toolsPage.section <= 4 && localTools.busy; value: localTools.progress / 100; Layout.fillWidth: true }
            RowLayout {
                visible: toolsPage.section >= 2 && toolsPage.section <= 4 && toolsPage.resultSection === (toolsPage.section === 2 ? "audio" : toolsPage.section === 3 ? "compress" : "gif") && localTools.outputUrl.toString().length > 0 && !localTools.busy
                Layout.fillWidth: true
                Text { text: toolsPage.filename(localTools.outputUrl); color: "#cbd5d3"; font.pixelSize: 12; Layout.fillWidth: true }
                EditorButton { text: "Open file"; onClicked: Qt.openUrlExternally(localTools.outputUrl) }
                EditorButton { text: "Publish"; onClicked: toolsPage.publishFile(localTools.outputUrl) }
            }
            RowLayout {
                visible: (toolsPage.section === 1 || toolsPage.section === 5) && (remoteJobs.busy || remoteJobs.errorText || remoteJobs.resultAvailable)
                Layout.fillWidth: true
                spacing: 10
                Text { text: remoteJobs.errorText || remoteJobs.stage; color: remoteJobs.errorText ? "#e7aaa4" : "#d4dfdc"; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                Text { text: remoteJobs.busy ? remoteJobs.progress + "%" : remoteJobs.resultAvailable ? toolsPage.sizeLabel(remoteJobs.outputBytes) : ""; color: "#b5c4c1"; font.pixelSize: 12 }
                EditorButton { text: "Cancel"; visible: remoteJobs.busy; danger: true; onClicked: remoteJobs.cancel() }
            }
            ProgressBar { visible: (toolsPage.section === 1 || toolsPage.section === 5) && remoteJobs.busy; value: remoteJobs.progress / 100; Layout.fillWidth: true }
            RowLayout {
                visible: toolsPage.resultSection === (toolsPage.section === 1 ? "download" : "pdf") && remoteJobs.resultAvailable && !remoteJobs.busy && (toolsPage.section === 1 || toolsPage.section === 5)
                Layout.fillWidth: true
                Text { text: remoteJobs.outputFilename; color: "#cbd5d3"; font.pixelSize: 12; Layout.fillWidth: true }
                EditorButton { text: "Save file"; primary: true; onClicked: { remoteSave.defaultSuffix = remoteJobs.outputFilename.split(".").pop(); remoteSave.open() } }
            }
            Text {
                visible: toolsPage.section === 1 && remoteJobs.resultAvailable && remoteJobs.overTarget
                text: "GIF exceeds the requested size limit (" + toolsPage.sizeLabel(remoteJobs.outputBytes) + ")."
                color: "#e2bb8e"
                font.pixelSize: 12
            }
            RowLayout {
                visible: toolsPage.resultSection === (toolsPage.section === 1 ? "download" : "pdf") && remoteJobs.savedUrl.toString().length > 0 && (toolsPage.section === 1 || toolsPage.section === 5)
                Layout.fillWidth: true
                Text { text: toolsPage.filename(remoteJobs.savedUrl); color: "#cbd5d3"; font.pixelSize: 12; Layout.fillWidth: true }
                EditorButton { text: "Open file"; onClicked: Qt.openUrlExternally(remoteJobs.savedUrl) }
                EditorButton { text: "Publish"; onClicked: toolsPage.publishFile(remoteJobs.savedUrl) }
            }
            Item { Layout.preferredHeight: 24 }
        }
    }
}
