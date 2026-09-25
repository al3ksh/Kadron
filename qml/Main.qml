import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia

ApplicationWindow {
    id: root
    width: 1380
    height: 860
    minimumWidth: 1080
    minimumHeight: 700
    visible: true
    color: "#151b1e"
    title: "Kadron" + (editorProject.projectUrl.toString() ? " - " + editorProject.projectUrl.toString().split("/").pop() : "")

    property bool forceClose: false
    property string playerError: ""
    property string notice: ""
    property bool hasPlayed: false
    property string currentMediaKey: ""

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

    Component.onCompleted: syncRangeFields()
    onClosing: function(event) {
        if (!forceClose && editorProject.dirty) {
            event.accepted = false
            quitDialog.open()
        }
    }

    Connections {
        target: editorProject
        function onChanged() {
            root.syncRangeFields()
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
    Shortcut { sequence: "Space"; enabled: editorProject.hasMedia; onActivated: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
    Shortcut { sequence: "I"; enabled: editorProject.hasMedia; onActivated: editorProject.setInMs(player.position) }
    Shortcut { sequence: "O"; enabled: editorProject.hasMedia; onActivated: editorProject.setOutMs(player.position) }

    FileDialog {
        id: mediaDialog
        title: "Open media"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Media files (*.mp4 *.mov *.mkv *.webm *.m4v *.avi *.mp3 *.wav *.flac *.m4a *.ogg)", "All files (*)"]
        onAccepted: {
            if (editorProject.importMedia(selectedFile)) {
                playerError = ""
                notice = "Media ready"
            }
        }
    }
    FileDialog {
        id: openDialog
        title: "Open Kadron project"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Kadron project (*.kadr)"]
        onAccepted: {
            if (editorProject.openProject(selectedFile)) {
                playerError = ""
                notice = "Project opened"
            }
        }
    }
    FileDialog {
        id: saveDialog
        title: "Save Kadron project"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "kadr"
        nameFilters: ["Kadron project (*.kadr)"]
        onAccepted: {
            if (editorProject.saveProject(selectedFile)) notice = "Project saved"
        }
    }
    FileDialog {
        id: exportDialog
        title: "Export MP4"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "mp4"
        nameFilters: ["MP4 video (*.mp4)"]
        onAccepted: exporter.start(editorProject.mediaUrl, selectedFile, editorProject.inMs, editorProject.outMs)
    }

    Dialog {
        id: quitDialog
        modal: true
        title: "Unsaved changes"
        anchors.centerIn: parent
        width: 380
        standardButtons: Dialog.NoButton
        background: Rectangle { color: "#252d31"; radius: 7; border.color: "#4a5559" }
        contentItem: ColumnLayout {
            spacing: 18
            Text {
                text: "Close without saving this project?"
                color: "#e4e8e9"
                font.pixelSize: 14
            }
            RowLayout {
                Item { Layout.fillWidth: true }
                EditorButton { text: "Cancel"; onClicked: quitDialog.close() }
                EditorButton {
                    text: "Discard"
                    primary: true
                    onClicked: {
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
        onDurationChanged: editorProject.setDurationMs(duration)
        onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) root.hasPlayed = true
        onPositionChanged: {
            if (playbackState === MediaPlayer.PlayingState && editorProject.outMs > editorProject.inMs && position >= editorProject.outMs)
                pause()
        }
        onErrorOccurred: function(error, errorString) { root.playerError = errorString }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            color: "#1e2629"
            border.width: 0
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                spacing: 12
                Text {
                    text: "KADRON"
                    font.family: "Segoe UI"
                    font.pixelSize: 19
                    font.weight: Font.Bold
                    color: "#e7eeec"
                    Layout.preferredWidth: 148
                }
                Rectangle { width: 1; height: 25; color: "#3a4649" }
                Text {
                    text: editorProject.hasMedia ? editorProject.mediaName : "Untitled project"
                    color: "#c9d2d1"
                    font.pixelSize: 13
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
                Text {
                    text: editorProject.dirty ? "Unsaved" : "Saved"
                    color: editorProject.dirty ? "#e2bf86" : "#8a9b98"
                    font.pixelSize: 11
                    visible: editorProject.hasMedia
                }
                EditorButton { text: "Open project"; subtle: true; onClicked: openDialog.open() }
                EditorButton { text: "Import media"; onClicked: mediaDialog.open() }
                EditorButton { text: "Save"; enabled: editorProject.hasMedia; onClicked: root.saveProject() }
                EditorButton {
                    text: "Export"
                    primary: true
                    enabled: editorProject.hasMedia && editorProject.outMs > editorProject.inMs && !exporter.busy && exporter.available
                    onClicked: exportDialog.open()
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a4548" }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Rectangle {
                Layout.preferredWidth: 228
                Layout.fillHeight: true
                color: "#1b2225"
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 10
                    Text { text: "MEDIA"; color: "#9facad"; font.pixelSize: 11; font.weight: Font.DemiBold }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#394347" }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        visible: editorProject.hasMedia
                        radius: 5
                        color: "#293438"
                        border.color: "#4b7065"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8
                            Rectangle { width: 4; height: 38; color: "#94d2b7"; radius: 2 }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text { text: editorProject.mediaName; color: "#e6edeb"; font.pixelSize: 12; elide: Text.ElideMiddle; Layout.fillWidth: true }
                                Text { text: root.timecode(editorProject.durationMs); color: "#96aba6"; font.pixelSize: 11 }
                            }
                        }
                    }
                    Text {
                        visible: !editorProject.hasMedia
                        text: "No media imported"
                        color: "#9aa7a8"
                        font.pixelSize: 12
                        Layout.topMargin: 12
                    }
                    Item { Layout.fillHeight: true }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#394347" }
                    Text { text: "LOCAL PROJECT"; color: "#9facad"; font.pixelSize: 11; font.weight: Font.DemiBold }
                    Text {
                        text: editorProject.projectUrl.toString() ? editorProject.projectUrl.toLocalFile() : "Not saved yet"
                        color: "#b5c0c0"
                        font.pixelSize: 11
                        wrapMode: Text.WrapAnywhere
                        Layout.fillWidth: true
                    }
                }
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#394347" }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 250
                    color: "#101516"
                    VideoOutput {
                        id: videoOutput
                        anchors.fill: parent
                        anchors.margins: 18
                        visible: player.hasVideo && root.hasPlayed
                        fillMode: VideoOutput.PreserveAspectFit
                    }
                    Image {
                        anchors.fill: parent
                        anchors.margins: 18
                        source: thumbnails.frames.length > 0 ? thumbnails.frames[0] : ""
                        fillMode: Image.PreserveAspectFit
                        visible: editorProject.hasMedia && player.hasVideo && !root.hasPlayed
                        asynchronous: true
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 14
                        visible: !editorProject.hasMedia || !player.hasVideo || !root.hasPlayed && thumbnails.frames.length === 0
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: editorProject.hasMedia ? editorProject.mediaName : "Open a file to begin"
                            color: "#e4ece8"
                            font.pixelSize: editorProject.hasMedia ? 18 : 22
                            font.weight: Font.DemiBold
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
                        color: "#f0a9a1"
                        font.pixelSize: 12
                        visible: root.playerError.length > 0
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 84
                    color: "#20292c"
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        anchors.topMargin: 9
                        anchors.bottomMargin: 9
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 9
                            EditorButton {
                                text: player.playbackState === MediaPlayer.PlayingState ? "Pause" : "Play"
                                enabled: editorProject.hasMedia
                                onClicked: {
                                    if (player.playbackState === MediaPlayer.PlayingState) player.pause()
                                    else {
                                        if (player.position < editorProject.inMs || player.position >= editorProject.outMs)
                                            player.position = editorProject.inMs
                                        player.play()
                                    }
                                }
                            }
                            Text { text: root.timecode(player.position); color: "#e7f0e9"; font.pixelSize: 12; font.weight: Font.DemiBold }
                            Text { text: "/ " + root.timecode(editorProject.durationMs); color: "#9daeb0"; font.pixelSize: 12 }
                            Item { Layout.fillWidth: true }
                            Text { text: "Volume"; color: "#aab8b7"; font.pixelSize: 11 }
                            Slider { id: volumeSlider; from: 0; to: 1; value: 0.8; Layout.preferredWidth: 100 }
                        }
                        Slider {
                            id: seekSlider
                            Layout.fillWidth: true
                            enabled: editorProject.durationMs > 0
                            from: 0
                            to: Math.max(1, editorProject.durationMs)
                            value: player.position
                            onMoved: player.position = value
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 222
                    color: "#1b2326"
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 22
                        anchors.rightMargin: 22
                        anchors.topMargin: 12
                        anchors.bottomMargin: 11
                        spacing: 9
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "TIMELINE"; color: "#aab8b7"; font.pixelSize: 11; font.weight: Font.DemiBold }
                            Item { Layout.fillWidth: true }
                            EditorButton { text: "Mark in"; subtle: true; enabled: editorProject.hasMedia; onClicked: editorProject.setInMs(player.position) }
                            EditorButton { text: "Mark out"; subtle: true; enabled: editorProject.hasMedia; onClicked: editorProject.setOutMs(player.position) }
                        }
                        Timeline {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            durationMs: editorProject.durationMs
                            inMs: editorProject.inMs
                            outMs: editorProject.outMs
                            playheadMs: player.position
                            frames: thumbnails.frames
                            onSeekRequested: function(ms) { player.position = ms }
                            onInRequested: function(ms) { editorProject.setInMs(ms) }
                            onOutRequested: function(ms) { editorProject.setOutMs(ms) }
                            onMoveRequested: function(delta) { editorProject.moveRange(delta) }
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 252
                Layout.fillHeight: true
                color: "#1b2225"
                Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: "#394347" }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 11
                    Text { text: "INSPECTOR"; color: "#aab8b7"; font.pixelSize: 11; font.weight: Font.DemiBold }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#394347" }
                    Text { text: "Selected range"; color: "#e1e9e6"; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { text: "Start (seconds)"; color: "#a6b3b3"; font.pixelSize: 11 }
                    TextField {
                        id: inField
                        Layout.fillWidth: true
                        enabled: editorProject.durationMs > 0
                        validator: DoubleValidator { bottom: 0; decimals: 3 }
                        color: "#e9f0ed"
                        font.pixelSize: 13
                        background: Rectangle { color: "#293237"; radius: 5; border.color: inField.activeFocus ? "#91d5b8" : "#4b565a" }
                        onEditingFinished: editorProject.setInMs(Math.round(Number(text) * 1000))
                    }
                    Text { text: "End (seconds)"; color: "#a6b3b3"; font.pixelSize: 11 }
                    TextField {
                        id: outField
                        Layout.fillWidth: true
                        enabled: editorProject.durationMs > 0
                        validator: DoubleValidator { bottom: 0; decimals: 3 }
                        color: "#e9f0ed"
                        font.pixelSize: 13
                        background: Rectangle { color: "#293237"; radius: 5; border.color: outField.activeFocus ? "#91d5b8" : "#4b565a" }
                        onEditingFinished: editorProject.setOutMs(Math.round(Number(text) * 1000))
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#394347"; Layout.topMargin: 6 }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Duration"; color: "#a6b3b3"; font.pixelSize: 12; Layout.fillWidth: true }
                        Text { text: root.timecode(editorProject.outMs - editorProject.inMs); color: "#d8e6dc"; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                    Item { Layout.fillHeight: true }
                    Text {
                        Layout.fillWidth: true
                        visible: !exporter.available
                        text: "FFmpeg is required for export. Set KADRON_FFMPEG or add it to PATH."
                        wrapMode: Text.WordWrap
                        color: "#e2bf86"
                        font.pixelSize: 11
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: exporter.errorText.length > 0
                        text: exporter.errorText
                        wrapMode: Text.WordWrap
                        color: "#f0a9a1"
                        font.pixelSize: 11
                    }
                    EditorButton {
                        Layout.fillWidth: true
                        text: exporter.busy ? "Cancel export" : "Export MP4"
                        enabled: exporter.busy || editorProject.hasMedia && editorProject.outMs > editorProject.inMs && exporter.available
                        primary: !exporter.busy
                        onClicked: exporter.busy ? exporter.cancel() : exportDialog.open()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            color: "#243034"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 10
                Rectangle { width: 6; height: 6; radius: 3; color: exporter.busy ? "#e2bf86" : exporter.errorText || editorProject.errorText ? "#e89c94" : "#91d3b4" }
                Text {
                    text: editorProject.errorText || exporter.errorText || (exporter.busy ? exporter.stage + "  " + exporter.progress + "%" : exporter.stage === "Ready" ? "Export ready" : root.notice || "Ready")
                    color: "#d1dad8"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text { text: "LOCAL"; color: "#9aabaa"; font.pixelSize: 10; font.weight: Font.DemiBold }
            }
        }
    }
}
