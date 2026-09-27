import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
import QtMultimedia

// Reframe: a landscape video becomes 9:16, 1:1, 4:5 or 16:9. In "crop" mode
// a frame follows the action: move it at different moments and each move is
// a keyframe it glides between. In "blur" mode the whole picture sits over a
// blurred copy of itself. LocalMediaTools::reframe renders the same thing.
Item {
    id: page
    objectName: "reframeArea"

    property url sourceUrl: ""
    property string mode: "crop"
    property int aspectW: 9
    property int aspectH: 16
    property real zoom: 1
    // [{t: seconds, x, y}] sorted by t; x/y are the frame centre, 0..1 of the picture.
    property var keyframes: []
    property bool dragging: false
    property real dragX: 0.5
    property real dragY: 0.5

    readonly property var shapes: [[9, 16, "9:16", "Reels, Shorts, TikTok"], [1, 1, "1:1", "Square post"],
                                   [4, 5, "4:5", "Portrait post"], [16, 9, "16:9", "Landscape"]]
    readonly property real seconds: player.position / 1000
    readonly property real durationSec: player.duration / 1000
    readonly property rect picture: video.contentRect
    readonly property real videoAspect: picture.height > 0 ? picture.width / picture.height : 16 / 9
    // The picture in pixels, upright (phones record portrait video rotated).
    readonly property size videoPixels: {
        var r = player.metaData.value(MediaMetaData.Resolution)
        if (!r || !r.width) return Qt.size(0, 0)
        var portrait = videoAspect < 1
        return (r.width < r.height) === portrait ? Qt.size(r.width, r.height) : Qt.size(r.height, r.width)
    }
    // The crop as a share of the picture: the largest frame of the shape, then zoomed.
    readonly property size cropShare: {
        var ratio = aspectW / aspectH
        var w = 1, h = 1
        if (videoAspect > ratio) w = ratio / videoAspect
        else h = videoAspect / ratio
        return Qt.size(w / zoom, h / zoom)
    }
    readonly property size outputSize: localReframe.reframeOutput(aspectW, aspectH)
    readonly property size cropPixels: localReframe.reframeCrop(videoPixels, aspectW, aspectH, zoom)
    readonly property point center: dragging ? Qt.point(dragX, dragY) : centerAt(seconds)
    readonly property int nearKey: nearestKey(seconds)
    // How much the crop is enlarged to fill the output; 1080p to 9:16 is 1.8×, past 2× it looks soft.
    readonly property real upscale: videoPixels.height > 0 ? outputSize.height / Math.max(1, cropPixels.height) : 0

    function isVideo(url) { return /\.(mp4|mov|mkv|webm|avi|m4v|wmv|mpe?g|ts)$/i.test(url.toString()) }
    function load(url) {
        if (!isVideo(url) || localReframe.busy) return false
        sourceUrl = url
        keyframes = []
        zoom = 1
        return true
    }
    function clampCenter(x, y) {
        var hw = cropShare.width / 2, hh = cropShare.height / 2
        return Qt.point(Math.max(hw, Math.min(1 - hw, x)), Math.max(hh, Math.min(1 - hh, y)))
    }
    // Same easing as the export: smoothstep between neighbouring keyframes.
    function centerAt(t) {
        var keys = keyframes
        if (keys.length === 0) return clampCenter(0.5, 0.5)
        if (t <= keys[0].t || keys.length === 1) return clampCenter(keys[0].x, keys[0].y)
        for (var i = 0; i < keys.length - 1; i++) {
            if (t < keys[i + 1].t) {
                var a = clampCenter(keys[i].x, keys[i].y), b = clampCenter(keys[i + 1].x, keys[i + 1].y)
                var u = Math.max(0, Math.min(1, (t - keys[i].t) / Math.max(0.001, keys[i + 1].t - keys[i].t)))
                var s = u * u * (3 - 2 * u)
                return Qt.point(a.x + (b.x - a.x) * s, a.y + (b.y - a.y) * s)
            }
        }
        var last = keys[keys.length - 1]
        return clampCenter(last.x, last.y)
    }
    function nearestKey(t) {
        var tolerance = Math.max(0.12, durationSec / 300)
        for (var i = 0; i < keyframes.length; i++)
            if (Math.abs(keyframes[i].t - t) <= tolerance) return i
        return -1
    }
    // A move of the frame is a keyframe at this moment.
    function placeFrame(x, y) {
        var c = clampCenter(x, y)
        var list = keyframes.slice()
        var i = nearestKey(seconds)
        if (i >= 0) list[i] = { t: list[i].t, x: c.x, y: c.y }
        else list.push({ t: seconds, x: c.x, y: c.y })
        list.sort(function(a, b) { return a.t - b.t })
        keyframes = list
    }
    function addKey() { placeFrame(center.x, center.y) }
    function removeKey(index) {
        if (index < 0) return
        var list = keyframes.slice()
        list.splice(index, 1)
        keyframes = list
    }
    function seek(t) {
        player.position = Math.max(0, Math.min(player.duration, Math.round(t * 1000)))
    }
    function timecode(t) {
        var s = Math.max(0, t)
        return Math.floor(s / 60) + ":" + Math.floor(s % 60).toString().padStart(2, "0") + "." + Math.floor((s * 10) % 10)
    }
    function exportVideo() {
        var path = sourceUrl.toString()
        var folder = path.replace(/\/[^\/]*$/, "")
        var base = decodeURIComponent(path.split("/").pop().replace(/\.[^.]*$/, ""))
        saveDialog.currentFolder = folder
        saveDialog.selectedFile = folder + "/" + encodeURIComponent(base + " " + aspectW + "x" + aspectH + (mode === "blur" ? " fill" : "") + ".mp4")
        saveDialog.open()
    }

    FileDialog {
        id: saveDialog
        title: "Save the reframed video"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "mp4"
        nameFilters: ["MP4 video (*.mp4)"]
        onAccepted: {
            player.pause()
            localReframe.reframe(page.sourceUrl, selectedFile, {
                mode: page.mode, aspectW: page.aspectW, aspectH: page.aspectH, zoom: page.zoom,
                keyframes: page.keyframes.length > 0 ? page.keyframes : [{ t: 0, x: page.center.x, y: page.center.y }]
            })
        }
    }
    FileDialog {
        id: openDialog
        title: "Choose a video"
        nameFilters: ["Video (*.mp4 *.mov *.mkv *.webm *.avi *.m4v *.wmv *.mpg *.mpeg *.ts)", "All files (*)"]
        onAccepted: page.load(selectedFile)
    }

    MediaPlayer {
        id: player
        source: page.sourceUrl
        videoOutput: video
        audioOutput: AudioOutput { volume: reframeVolume.effectiveVolume }
        onMediaStatusChanged: {
            // Show the first frame instead of a black stage.
            if (mediaStatus === MediaPlayer.LoadedMedia && playbackState === MediaPlayer.StoppedState) pause()
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.window }

    DropArea {
        id: pageDrop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: function(drop) { if (drop.hasUrls) page.load(drop.urls[0]) }
    }

    DropZone {
        visible: !page.sourceUrl.toString()
        anchors.centerIn: parent
        width: Math.min(parent.width - 90, 760)
        height: 300
        active: pageDrop.containsDrag
        iconName: "reframe"
        heading: "Drop a video to reframe"
        formats: "MP4 · MOV · MKV · WEBM  ·  9:16, 1:1, 4:5 or 16:9 with a frame that follows the action"
        onBrowseRequested: openDialog.open()
    }

    RowLayout {
        visible: !!page.sourceUrl.toString()
        anchors.fill: parent
        spacing: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.fillHeight: true
            Layout.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [["crop", "Follow with a crop", "crop"], ["blur", "Whole picture, blurred fill", "image"]]
                    delegate: EditorButton {
                        required property var modelData
                        objectName: "reframeMode_" + modelData[0]
                        text: modelData[1]
                        iconName: modelData[2]
                        primary: page.mode === modelData[0]
                        subtle: page.mode !== modelData[0]
                        onClicked: page.mode = modelData[0]
                    }
                }
                Text {
                    text: decodeURIComponent(page.sourceUrl.toString().split("/").pop())
                    color: Theme.textMuted
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    horizontalAlignment: Text.AlignRight
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                }
                EditorButton { text: "Change"; subtle: true; enabled: !localReframe.busy; onClicked: openDialog.open() }
            }

            // Stage: the source with the frame over it.
            Rectangle {
                id: stage
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusLarge
                color: Theme.canvas
                clip: true

                VideoOutput {
                    id: video
                    anchors.fill: parent
                    anchors.margins: 20
                    fillMode: VideoOutput.PreserveAspectFit
                }
                Text {
                    anchors.centerIn: parent
                    visible: player.error !== MediaPlayer.NoError
                    text: player.errorString
                    color: Theme.danger
                    font.pixelSize: 13
                }

                Item {
                    id: overlay
                    visible: page.mode === "crop" && page.picture.width > 0
                    x: video.x + page.picture.x
                    y: video.y + page.picture.y
                    width: page.picture.width
                    height: page.picture.height

                    readonly property real frameW: page.cropShare.width * width
                    readonly property real frameH: page.cropShare.height * height
                    readonly property real frameX: page.center.x * width - frameW / 2
                    readonly property real frameY: page.center.y * height - frameH / 2

                    Rectangle { x: 0; y: 0; width: overlay.width; height: overlay.frameY; color: "#a6000000" }
                    Rectangle { x: 0; y: overlay.frameY + overlay.frameH; width: overlay.width; height: overlay.height - overlay.frameY - overlay.frameH; color: "#a6000000" }
                    Rectangle { x: 0; y: overlay.frameY; width: overlay.frameX; height: overlay.frameH; color: "#a6000000" }
                    Rectangle { x: overlay.frameX + overlay.frameW; y: overlay.frameY; width: overlay.width - overlay.frameX - overlay.frameW; height: overlay.frameH; color: "#a6000000" }

                    Rectangle {
                        id: frameBox
                        objectName: "reframeFrame"
                        x: overlay.frameX
                        y: overlay.frameY
                        width: overlay.frameW
                        height: overlay.frameH
                        color: "transparent"
                        border.width: 2
                        border.color: page.nearKey >= 0 || page.dragging ? Theme.accent : Qt.rgba(1, 1, 1, 0.7)
                        Repeater {
                            model: 2
                            delegate: Item {
                                required property int index
                                anchors.fill: parent
                                visible: page.dragging
                                Rectangle { x: frameBox.width * (index + 1) / 3; width: 1; height: frameBox.height; color: Qt.rgba(1, 1, 1, 0.4) }
                                Rectangle { y: frameBox.height * (index + 1) / 3; height: 1; width: frameBox.width; color: Qt.rgba(1, 1, 1, 0.4) }
                            }
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            visible: page.keyframes.length === 0 && !page.dragging
                            width: dragHint.implicitWidth + 18
                            height: 24
                            radius: 12
                            color: Theme.chipScrim
                            Text { id: dragHint; anchors.centerIn: parent; text: "Drag to frame"; color: "#f1f4ef"; font.pixelSize: 11; font.weight: Font.DemiBold }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property real grabX: 0
                            property real grabY: 0
                            onPressed: function(mouse) {
                                player.pause()
                                grabX = mouse.x - frameBox.width / 2
                                grabY = mouse.y - frameBox.height / 2
                                page.dragX = page.center.x
                                page.dragY = page.center.y
                                page.dragging = true
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed) return
                                var p = mapToItem(overlay, mouse.x - grabX, mouse.y - grabY)
                                var c = page.clampCenter(p.x / overlay.width, p.y / overlay.height)
                                page.dragX = c.x
                                page.dragY = c.y
                            }
                            onReleased: {
                                page.placeFrame(page.dragX, page.dragY)
                                page.dragging = false
                            }
                            onCanceled: page.dragging = false
                        }
                    }
                }
            }

            // Transport and keyframes.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                EditorButton {
                    iconName: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
                    subtle: true
                    onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                }
                Text {
                    text: page.timecode(page.seconds) + " / " + page.timecode(page.durationSec)
                    color: Theme.textSoft
                    font.pixelSize: 12
                    font.family: "Consolas"
                }
                Item {
                    id: track
                    objectName: "reframeTrack"
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    readonly property real share: page.durationSec > 0 ? page.seconds / page.durationSec : 0
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 6
                        radius: 3
                        color: Theme.field
                        Rectangle { width: parent.width * track.share; height: parent.height; radius: 3; color: Theme.accentEdge }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: function(mouse) { page.seek(mouse.x / width * page.durationSec) }
                        onPositionChanged: function(mouse) { if (pressed) page.seek(Math.max(0, Math.min(1, mouse.x / width)) * page.durationSec) }
                    }
                    Repeater {
                        model: page.mode === "crop" ? page.keyframes : []
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            x: (page.durationSec > 0 ? modelData.t / page.durationSec : 0) * track.width - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            rotation: 45
                            radius: 2
                            color: index === page.nearKey ? Theme.accent : Theme.panel
                            border.width: 2
                            border.color: Theme.accent
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { player.pause(); page.seek(modelData.t) }
                            }
                        }
                    }
                    Rectangle {
                        x: track.share * track.width - 1
                        width: 2
                        height: parent.height
                        radius: 1
                        color: Theme.playhead
                    }
                }
                VolumeControl { id: reframeVolume }
            }
            RowLayout {
                visible: page.mode === "crop"
                Layout.fillWidth: true
                spacing: 6
                EditorButton {
                    objectName: "reframeAddKey"
                    iconName: "key"
                    text: page.nearKey >= 0 ? "Keyframe here" : "Add keyframe"
                    subtle: page.nearKey < 0
                    enabled: page.nearKey < 0
                    onClicked: page.addKey()
                }
                EditorButton { text: "Remove"; subtle: true; enabled: page.nearKey >= 0; onClicked: page.removeKey(page.nearKey) }
                EditorButton { text: "Clear all"; subtle: true; enabled: page.keyframes.length > 0; onClicked: page.keyframes = [] }
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: page.keyframes.length < 2 ? "Move the frame at another moment and it glides there by itself."
                                                    : page.keyframes.length + " keyframes · the frame glides between them"
                    color: Theme.textMuted
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        // Settings and the result preview.
        Rectangle {
            Layout.preferredWidth: 340
            Layout.minimumWidth: 340
            Layout.maximumWidth: 340
            Layout.fillHeight: true
            color: Theme.panel
            Rectangle { width: 1; height: parent.height; color: Theme.line }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                ScrollView {
                    id: settingsScroll
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: settingsScroll.availableWidth
                        spacing: 10

                        Item { Layout.preferredHeight: 8 }
                        Text { Layout.leftMargin: 20; text: "SHAPE"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            spacing: 4
                            Repeater {
                                model: page.shapes
                                delegate: EditorButton {
                                    required property var modelData
                                    readonly property bool chosen: page.aspectW === modelData[0] && page.aspectH === modelData[1]
                                    objectName: "reframeShape_" + modelData[0] + "x" + modelData[1]
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    leftPadding: 4
                                    rightPadding: 4
                                    text: modelData[2]
                                    primary: chosen
                                    subtle: !chosen
                                    onClicked: { page.aspectW = modelData[0]; page.aspectH = modelData[1] }
                                    ToolTip.visible: hovered
                                    ToolTip.text: modelData[3]
                                }
                            }
                        }

                        // What the export looks like, live.
                        Item {
                            id: preview
                            Layout.fillWidth: true
                            Layout.preferredHeight: 290
                            readonly property real boxW: Math.min(width - 40, 270 * page.aspectW / page.aspectH)
                            readonly property real boxH: boxW * page.aspectH / page.aspectW
                            Rectangle {
                                id: phone
                                anchors.centerIn: parent
                                width: preview.boxW
                                height: preview.boxH
                                radius: 10
                                color: "#000000"
                                clip: true
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: phoneMask
                                }

                                // Crop: the frame's part of the picture.
                                ShaderEffectSource {
                                    anchors.fill: parent
                                    visible: page.mode === "crop"
                                    sourceItem: page.mode === "crop" ? video : null
                                    live: true
                                    sourceRect: Qt.rect(page.picture.x + (page.center.x - page.cropShare.width / 2) * page.picture.width,
                                                        page.picture.y + (page.center.y - page.cropShare.height / 2) * page.picture.height,
                                                        page.cropShare.width * page.picture.width,
                                                        page.cropShare.height * page.picture.height)
                                }

                                // Blurred fill: the picture enlarged and blurred, the whole picture on top.
                                Item {
                                    anchors.fill: parent
                                    visible: page.mode === "blur"
                                    readonly property real coverW: Math.max(width, height * page.videoAspect)
                                    ShaderEffectSource {
                                        id: blurSource
                                        anchors.centerIn: parent
                                        width: parent.coverW
                                        height: parent.coverW / page.videoAspect
                                        visible: false
                                        sourceItem: page.mode === "blur" ? video : null
                                        live: true
                                        sourceRect: page.picture
                                    }
                                    MultiEffect {
                                        anchors.fill: blurSource
                                        source: blurSource
                                        blurEnabled: true
                                        blur: 1
                                        blurMax: 48
                                        brightness: -0.06
                                    }
                                    ShaderEffectSource {
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width, parent.height * page.videoAspect)
                                        height: width / page.videoAspect
                                        sourceItem: page.mode === "blur" ? video : null
                                        live: true
                                        sourceRect: page.picture
                                    }
                                }
                            }
                            Rectangle { id: phoneMask; width: phone.width; height: phone.height; radius: 10; visible: false; layer.enabled: true }
                            Rectangle {
                                anchors.centerIn: phone
                                width: phone.width + 2
                                height: phone.height + 2
                                radius: 11
                                color: "transparent"
                                border.color: Theme.lineStrong
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                        Text { Layout.leftMargin: 20; Layout.topMargin: 6; text: page.mode === "crop" ? "CROP" : "FILL"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                        RowLayout {
                            visible: page.mode === "crop"
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            Text { text: "Zoom"; color: Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true }
                            Text { text: page.zoom.toFixed(2) + "×"; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold }
                        }
                        ToolSlider {
                            objectName: "reframeZoom"
                            visible: page.mode === "crop"
                            Layout.fillWidth: true
                            Layout.leftMargin: 14
                            Layout.rightMargin: 14
                            from: 1
                            to: 2.5
                            stepSize: 0.05
                            value: page.zoom
                            onMoved: page.zoom = value
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 6
                            Text { text: "Source"; color: Theme.textMuted; font.pixelSize: 12 }
                            Text {
                                Layout.fillWidth: true
                                text: page.videoPixels.width > 0 ? page.videoPixels.width + " × " + page.videoPixels.height : "…"
                                color: Theme.text
                                font.pixelSize: 12
                            }
                            Text { visible: page.mode === "crop"; text: "Frame"; color: Theme.textMuted; font.pixelSize: 12 }
                            Text {
                                visible: page.mode === "crop"
                                Layout.fillWidth: true
                                text: page.videoPixels.width > 0 ? page.cropPixels.width + " × " + page.cropPixels.height + " px of the picture" : "…"
                                color: Theme.text
                                font.pixelSize: 12
                            }
                            Text { text: "Saved as"; color: Theme.textMuted; font.pixelSize: 12 }
                            Text {
                                objectName: "reframeOutput"
                                Layout.fillWidth: true
                                text: page.outputSize.width + " × " + page.outputSize.height + " · MP4"
                                color: Theme.accent
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            visible: page.mode === "crop" && page.upscale > 2
                            text: "The frame is enlarged " + page.upscale.toFixed(1) + "× to fill " + page.outputSize.width + " × " + page.outputSize.height + ", so it can look soft. Zoom out or use a sharper video."
                            color: Theme.warning
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            Layout.bottomMargin: 12
                            text: page.mode === "crop" ? "Each move of the frame is a keyframe; between them the frame eases, like a camera operator would."
                                                       : "Nothing is cut off: the whole picture sits over a blurred, enlarged copy of itself."
                            color: Theme.textFaint
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // Export.
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        visible: localReframe.busy || localReframe.outputUrl.toString().length > 0
                        text: localReframe.busy ? localReframe.stage + " · " + localReframe.progress + "%"
                                                : decodeURIComponent(localReframe.outputUrl.toString().split("/").pop())
                        color: Theme.textSoft
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }
                    Text { Layout.fillWidth: true; visible: localReframe.errorText.length > 0 && !localReframe.busy; text: localReframe.errorText; color: Theme.danger; font.pixelSize: 11; wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight }
                    StudioProgress { Layout.fillWidth: true; visible: localReframe.busy; value: localReframe.progress / 100 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        EditorButton {
                            objectName: "reframeExport"
                            Layout.fillWidth: true
                            visible: !localReframe.busy
                            primary: true
                            iconName: "save"
                            text: "Export video…"
                            enabled: localReframe.available && page.picture.width > 0
                            onClicked: page.exportVideo()
                        }
                        EditorButton { Layout.fillWidth: true; visible: localReframe.busy; text: "Stop"; danger: true; onClicked: localReframe.cancel() }
                        EditorButton {
                            visible: !localReframe.busy && localReframe.outputUrl.toString().length > 0
                            iconName: "play"
                            subtle: true
                            onClicked: Qt.openUrlExternally(localReframe.outputUrl)
                            ToolTip.visible: hovered
                            ToolTip.text: "Play the result"
                        }
                        EditorButton {
                            visible: !localReframe.busy && localReframe.outputUrl.toString().length > 0
                            iconName: "folder"
                            subtle: true
                            onClicked: Qt.openUrlExternally(localReframe.outputUrl.toString().replace(/\/[^\/]*$/, ""))
                            ToolTip.visible: hovered
                            ToolTip.text: "Open the folder"
                        }
                        EditorButton {
                            iconName: "close"
                            subtle: true
                            enabled: !localReframe.busy
                            onClicked: { player.stop(); page.sourceUrl = ""; page.keyframes = [] }
                            ToolTip.visible: hovered
                            ToolTip.text: "Close the video"
                        }
                    }
                }
            }
        }
    }
}
