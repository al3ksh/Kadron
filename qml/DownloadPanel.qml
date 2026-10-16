import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Download: a link with its preview, the format and the queue, run by yt-dlp on this device.
ColumnLayout {
    id: downloadPanel
    // The Tools page: section, sources, jobs and the dialogs it owns.
    required property var page
    property alias gifStartField: downloadStart
    property alias gifDurationField: downloadDuration
    property alias gifFpsField: downloadFps
    property alias gifWidthField: downloadWidth
    property alias gifTargetField: downloadTarget
    property alias urlField: downloadUrl
    property alias presetBox: downloadPreset
    visible: page.section === 1
    Layout.fillWidth: true
    spacing: 12
    Text { text: "Source URL"; color: Theme.textMuted; font.pixelSize: 12 }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        EditorField {
            id: downloadUrl
            objectName: "downloadUrl"
            Layout.fillWidth: true
            placeholderText: "Paste a link from YouTube, TikTok, Instagram, X… and press Enter"
            onTextChanged: probeDelay.restart()
            onAccepted: page.quickDownload()
        }
        EditorButton {
            text: "Paste"
            iconName: "link"
            Layout.preferredHeight: downloadUrl.implicitHeight
            onClicked: page.pasteLink()
        }
    }
    Timer {
        id: probeDelay
        interval: 450
        onTriggered: localDownload.probe(downloadUrl.text)
    }
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
                    Text { id: durationText; anchors.centerIn: parent; text: page.durationLabel(linkPreview.info.durationMs || 0); color: Theme.text; font.pixelSize: 10; font.weight: Font.DemiBold }
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
                    text: [linkPreview.info.playlistCount ? "Playlist · " + linkPreview.info.playlistCount + " videos" : "",
                           linkPreview.info.uploader, linkPreview.info.source].filter(function(part) { return part }).join(" · ")
                    color: Theme.textMuted
                }
                // A video opened from a playlist: its list can be loaded too.
                EditorButton {
                    visible: /[?&]list=/.test(page.downloadLink) && !linkPreview.info.playlistCount
                             && localDownload.playlist.url !== page.downloadLink
                    text: "Load playlist"
                    iconName: "stack"
                    implicitHeight: 30
                    onClicked: localDownload.probePlaylist(page.downloadLink)
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
    // The videos of a playlist link, ticked for download.
    Rectangle {
        id: playlistPanel
        readonly property var list: localDownload.playlist
        visible: list.url === page.downloadLink && page.downloadLink.length > 0
        Layout.fillWidth: true
        implicitHeight: playlistColumn.implicitHeight + 20
        radius: Theme.radius
        color: Theme.field
        border.color: Theme.line
        ColumnLayout {
            id: playlistColumn
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: playlistPanel.list.loading ? "Reading the playlist…"
                        : playlistPanel.list.error ? playlistPanel.list.error
                        : (playlistPanel.list.title || "Playlist") + " · " + page.playlistSelected + " of " + (playlistPanel.list.entries || []).length + " selected"
                    color: playlistPanel.list.error ? Theme.danger : Theme.text
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                EditorButton { visible: page.linkIsPlaylist; subtle: true; text: "All"; implicitHeight: 30; onClicked: page.setAllPlaylist(true) }
                EditorButton { visible: page.linkIsPlaylist; subtle: true; text: "None"; implicitHeight: 30; onClicked: page.setAllPlaylist(false) }
            }
            ListView {
                id: playlistList
                visible: page.linkIsPlaylist
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 260)
                clip: true
                model: playlistPanel.list.entries || []
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: playlistList.contentHeight > playlistList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                delegate: RowLayout {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    spacing: 8
                    ToolCheck {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        text: (index + 1) + ". " + (modelData.title || modelData.url)
                        checked: !!page.playlistChecked[index]
                        onToggled: {
                            var next = page.playlistChecked.slice()
                            next[index] = checked
                            page.playlistChecked = next
                        }
                    }
                    Text {
                        visible: (modelData.durationMs || 0) > 0
                        text: page.durationLabel(modelData.durationMs || 0)
                        color: Theme.textFaint
                        font.pixelSize: 11
                        Layout.rightMargin: 6
                    }
                }
            }
            EditorButton {
                visible: page.linkIsPlaylist
                primary: true
                text: "Download " + page.playlistSelected + (page.playlistSelected === 1 ? " video" : " videos")
                enabled: page.playlistSelected > 0 && localDownload.available
                onClicked: page.downloadPlaylist()
            }
            Text {
                visible: page.linkIsPlaylist
                text: "Saved one after another to Downloads/" + (localDownload.safeFileName(playlistPanel.list.title || "") || "Playlist")
                color: Theme.textFaint
                font.pixelSize: 11
            }
        }
    }
    Text { visible: !localDownload.available; text: "Install yt-dlp and FFmpeg locally, or set KADRON_YTDLP and KADRON_FFMPEG."; color: Theme.warning; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    Text { text: "Format"; color: Theme.textMuted; font.pixelSize: 12 }
    ToolCombo {
        id: downloadPreset
        Layout.preferredWidth: 360
        currentIndex: page.downloadPresetIndex
        onActivated: page.downloadPresetIndex = currentIndex
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
        visible: !page.linkIsPlaylist
        text: localDownload.busy ? "Add to queue" : "Download"
        primary: true
        enabled: downloadUrl.text.length > 0 && localDownload.available
        onClicked: localDownload.busy ? page.quickDownload() : page.openDownloadSave()
    }
}
