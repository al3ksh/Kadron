import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
import QtMultimedia

// Reframe: a landscape video becomes 9:16, 1:1, 4:5 or 16:9. In "crop" mode
// a frame follows the action: move it at different moments and each move is
// a keyframe it glides between. In "blur" mode the whole picture sits over a
// blurred copy of itself. In "split" mode two regions are stacked: a free
// one (a streamer's webcam, a face) and the main picture below or above it.
// LocalMediaTools::reframe renders the same thing.
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
    // Split screen: the camera region is free; its band's height follows its
    // shape, and the main region takes the shape of the band that is left.
    property rect camArea: Qt.rect(0.7, 0.05, 0.26, 0.34)
    property rect mainArea: Qt.rect(0.25, 0, 0.5, 1)
    property bool camOnTop: true
    RememberedOptions { target: page; category: "reframeOptions"; names: ["mode", "aspectW", "aspectH", "camOnTop"] }
    readonly property bool splitAllowed: aspectW <= aspectH
    readonly property real camShare: {
        var camAspect = camArea.width * videoAspect / Math.max(0.001, camArea.height)
        return Math.max(0.2, Math.min(0.6, outputSize.width / camAspect / outputSize.height))
    }
    readonly property real mainRatio: outputSize.width / (outputSize.height * (1 - camShare))
    onMainRatioChanged: fitMain()
    onVideoAspectChanged: fitMain()
    onSplitAllowedChanged: if (!splitAllowed && mode === "split") mode = "crop"
    // Gives the main region the band's shape around its current centre.
    function fitMain() {
        var a = mainArea
        var h = a.height
        var w = h * mainRatio / videoAspect
        if (w > 1) { w = 1; h = w * videoAspect / mainRatio }
        if (h > 1) { h = 1; w = h * mainRatio / videoAspect }
        var cx = a.x + a.width / 2, cy = a.y + a.height / 2
        mainArea = Qt.rect(Math.max(0, Math.min(1 - w, cx - w / 2)), Math.max(0, Math.min(1 - h, cy - h / 2)), w, h)
    }
    function regionPixels(area) {
        return Qt.size(Math.round(area.width * videoPixels.width), Math.round(area.height * videoPixels.height))
    }
    function asPanel(area) { return { x: area.x, y: area.y, w: area.width, h: area.height } }
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
        texts = []
        textIndex = -1
        return true
    }
    // Text over the result, the same maps the editor uses (TextOverlay).
    property var texts: []
    property int textIndex: -1
    readonly property var activeText: textIndex >= 0 && textIndex < texts.length ? texts[textIndex] : null
    function addText() {
        var end = Math.max(1000, player.duration)
        var list = texts.slice()
        list.push({ text: "Your text", startMs: 0, endMs: end, lengthMs: end, x: 0.5, y: 0.8, size: 0.05,
                    color: "#ffffff", font: "sans", style: "outline" })
        texts = list
        textIndex = list.length - 1
    }
    function updateText(index, changes) {
        if (index < 0 || index >= texts.length) return
        var item = Object.assign({}, texts[index], changes)
        item.x = Math.max(0, Math.min(1, item.x))
        item.y = Math.max(0, Math.min(1, item.y))
        item.size = Math.max(0.02, Math.min(0.25, item.size))
        item.startMs = Math.max(0, Math.min(item.startMs, item.endMs - 200))
        item.lengthMs = item.endMs - item.startMs
        var list = texts.slice()
        list[index] = item
        texts = list
    }
    function removeText(index) {
        if (index < 0 || index >= texts.length) return
        var list = texts.slice()
        list.splice(index, 1)
        texts = list
        textIndex = Math.min(textIndex, list.length - 1)
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
        saveDialog.selectedFile = folder + "/" + encodeURIComponent(base + " " + aspectW + "x" + aspectH + (mode === "blur" ? " fill" : mode === "split" ? " split" : "") + ".mp4")
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
                keyframes: page.keyframes.length > 0 ? page.keyframes : [{ t: 0, x: page.center.x, y: page.center.y }],
                share: page.camOnTop ? page.camShare : 1 - page.camShare,
                panels: page.camOnTop ? [page.asPanel(page.camArea), page.asPanel(page.mainArea)]
                                      : [page.asPanel(page.mainArea), page.asPanel(page.camArea)],
                texts: page.texts
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

    ToolEmptyState {
        visible: !page.sourceUrl.toString()
        anchors.fill: parent
        title: "Reframe a video"
        subtitle: "Turn a wide video into vertical, square, or 4:5, with a frame that follows the action."
        active: pageDrop.containsDrag
        iconName: "reframe"
        heading: "Drop a video to reframe"
        formats: "MP4 · MOV · MKV · WEBM"
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
                    model: [["crop", "Follow with a crop", "crop"], ["blur", "Blurred fill", "image"], ["split", "Split screen", "stack"]]
                    delegate: EditorButton {
                        required property var modelData
                        objectName: "reframeMode_" + modelData[0]
                        enabled: modelData[0] !== "split" || page.splitAllowed
                        ToolTip.visible: hovered && modelData[0] === "split"
                        ToolTip.text: page.splitAllowed ? "Two parts of the picture, one above the other: a webcam and the game, say" : "Split screen needs a portrait or square shape"
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

                // Split screen: both regions over the dimmed picture; the camera on top.
                Item {
                    id: splitOverlay
                    objectName: "reframeSplit"
                    visible: page.mode === "split" && page.picture.width > 0
                    x: video.x + page.picture.x
                    y: video.y + page.picture.y
                    width: page.picture.width
                    height: page.picture.height
                    Rectangle { anchors.fill: parent; color: "#a6000000" }
                    RegionFrame {
                        anchors.fill: parent
                        area: page.mainArea
                        ratio: page.mainRatio
                        pictureAspect: page.videoAspect
                        tint: Theme.playhead
                        ink: "#2a1c0e"
                        label: "Main"
                        sourceItem: splitOverlay.visible ? video : null
                        sourcePicture: page.picture
                        onMoved: function(area) { page.mainArea = area }
                    }
                    RegionFrame {
                        anchors.fill: parent
                        area: page.camArea
                        pictureAspect: page.videoAspect
                        label: "Camera"
                        sourceItem: splitOverlay.visible ? video : null
                        sourcePicture: page.picture
                        onMoved: function(area) { page.camArea = area }
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
                    readonly property SoftBounds softBounds: SoftBounds { flickable: settingsScroll.contentItem }
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
                        SegmentedControl {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            namePrefix: "reframeShape_"
                            options: page.shapes.map(function(shape) {
                                return { label: shape[2], value: shape[0] + "x" + shape[1], glyph: shape[0] + ":" + shape[1], tip: shape[3] }
                            })
                            current: page.aspectW + "x" + page.aspectH
                            onActivated: function(shape) {
                                const sides = shape.split("x").map(Number)
                                page.aspectW = sides[0]
                                page.aspectH = sides[1]
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

                                // Split: the two regions in their bands.
                                Column {
                                    anchors.fill: parent
                                    visible: page.mode === "split"
                                    Repeater {
                                        model: 2
                                        delegate: ShaderEffectSource {
                                            required property int index
                                            readonly property bool camera: (index === 0) === page.camOnTop
                                            readonly property rect area: camera ? page.camArea : page.mainArea
                                            width: phone.width
                                            height: phone.height * (camera ? page.camShare : 1 - page.camShare)
                                            sourceItem: page.mode === "split" ? video : null
                                            live: true
                                            sourceRect: Qt.rect(page.picture.x + area.x * page.picture.width, page.picture.y + area.y * page.picture.height,
                                                                area.width * page.picture.width, area.height * page.picture.height)
                                        }
                                    }
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

                                TextOverlayLayer {
                                    objectName: "reframeTextLayer"
                                    anchors.fill: parent
                                    texts: page.texts
                                    timeMs: player.position
                                    selectedIndex: page.textIndex
                                    draftSize: reframeTextStyle.draftSize
                                    editable: !localReframe.busy
                                    onPicked: function(index) { page.textIndex = index }
                                    onMoved: function(index, x, y) { page.updateText(index, { x: x, y: y }) }
                                    onEdited: function(index, text) { page.updateText(index, { text: text.slice(0, 500) }) }
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
                        Text { Layout.leftMargin: 20; Layout.topMargin: 6; text: page.mode === "crop" ? "CROP" : page.mode === "split" ? "SPLIT" : "FILL"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
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
                        EditorButton {
                            objectName: "reframeSwap"
                            visible: page.mode === "split"
                            Layout.leftMargin: 20
                            iconName: "flipV"
                            text: page.camOnTop ? "Camera on top · swap" : "Camera at the bottom · swap"
                            subtle: true
                            onClicked: page.camOnTop = !page.camOnTop
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
                            Text { visible: page.mode === "split"; text: "Camera"; color: Theme.textMuted; font.pixelSize: 12 }
                            Text {
                                visible: page.mode === "split"
                                Layout.fillWidth: true
                                text: page.videoPixels.width > 0 ? page.regionPixels(page.camArea).width + " × " + page.regionPixels(page.camArea).height + " px · " + Math.round(page.camShare * 100) + "% of the height" : "…"
                                color: Theme.text
                                font.pixelSize: 12
                            }
                            Text { visible: page.mode === "split"; text: "Main"; color: Theme.textMuted; font.pixelSize: 12 }
                            Text {
                                visible: page.mode === "split"
                                Layout.fillWidth: true
                                text: page.videoPixels.width > 0 ? page.regionPixels(page.mainArea).width + " × " + page.regionPixels(page.mainArea).height + " px" : "…"
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
                                  : page.mode === "split" ? "Put the green frame around the webcam or face, any size and shape; its band grows to fit it. The amber frame picks the main picture for the rest."
                                  : "Nothing is cut off: the whole picture sits over a blurred, enlarged copy of itself."
                            color: Theme.textFaint
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        // Text burnt into the result.
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                        Text { Layout.leftMargin: 20; Layout.topMargin: 6; text: "TEXT"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            Layout.bottomMargin: 14
                            spacing: 6
                            enabled: !localReframe.busy
                            Flow {
                                visible: page.texts.length > 1
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: page.texts
                                    delegate: EditorButton {
                                        required property var modelData
                                        required property int index
                                        implicitHeight: 28
                                        text: modelData.text.length > 14 ? modelData.text.slice(0, 13).trim() + "…" : modelData.text
                                        primary: index === page.textIndex
                                        subtle: index !== page.textIndex
                                        onClicked: {
                                            page.textIndex = index
                                            if (player.position < modelData.startMs || player.position >= modelData.endMs)
                                                player.position = modelData.startMs
                                        }
                                    }
                                }
                            }
                            EditorButton {
                                objectName: "reframeAddText"
                                Layout.fillWidth: true
                                text: "Add text"
                                iconName: "plus"
                                enabled: player.duration > 0
                                onClicked: {
                                    page.addText()
                                    reframeTextField.forceActiveFocus()
                                    reframeTextField.selectAll()
                                }
                            }
                            TextArea {
                                id: reframeTextField
                                objectName: "reframeTextField"
                                visible: page.activeText !== null
                                Layout.fillWidth: true
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
                                    border.width: reframeTextField.activeFocus ? 2 : 1
                                    border.color: reframeTextField.activeFocus ? Theme.accent : Theme.lineStrong
                                }
                                readonly property string savedText: page.activeText ? page.activeText.text : ""
                                onSavedTextChanged: if (text !== savedText) text = savedText
                                Component.onCompleted: text = savedText
                                // Live: the preview follows each key.
                                onTextChanged: if (page.activeText && text !== savedText && text.trim().length > 0)
                                                   page.updateText(page.textIndex, { text: text.slice(0, 500) })
                            }
                            RowLayout {
                                visible: page.activeText !== null
                                Layout.fillWidth: true
                                spacing: 6
                                EditorButton {
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    text: "Start here"
                                    subtle: true
                                    enabled: page.activeText !== null && player.position < page.activeText.endMs - 200
                                    onClicked: page.updateText(page.textIndex, { startMs: player.position })
                                }
                                EditorButton {
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    text: "End here"
                                    subtle: true
                                    enabled: page.activeText !== null && player.position > page.activeText.startMs + 200
                                    onClicked: page.updateText(page.textIndex, { endMs: player.position })
                                }
                                EditorButton {
                                    implicitHeight: 30
                                    text: "Whole"
                                    subtle: true
                                    onClicked: page.updateText(page.textIndex, { startMs: 0, endMs: Math.max(1000, player.duration) })
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 500
                                    ToolTip.text: "Show it for the whole video"
                                }
                            }
                            TextStyleEditor {
                                id: reframeTextStyle
                                visible: page.activeText !== null
                                Layout.fillWidth: true
                                item: page.activeText
                                onChangeRequested: function(changes) { page.updateText(page.textIndex, changes) }
                            }
                            EditorButton {
                                visible: page.activeText !== null
                                Layout.fillWidth: true
                                text: "Remove text"
                                iconName: "close"
                                subtle: true
                                onClicked: page.removeText(page.textIndex)
                            }
                            Text {
                                Layout.fillWidth: true
                                text: page.activeText
                                      ? "Shown " + page.timecode(page.activeText.startMs / 1000) + " – " + page.timecode(page.activeText.endMs / 1000) + ". Drag it on the preview to place it."
                                      : "Titles or a hook over the reframed video, placed anywhere on it."
                                color: Theme.textFaint
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
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
                            onClicked: shellIntegration.reveal(localReframe.outputUrl)
                            ToolTip.visible: hovered
                            ToolTip.text: "Show in folder"
                        }
                        CopyButton {
                            visible: !localReframe.busy && localReframe.outputUrl.toString().length > 0
                            compact: true
                            subtle: true
                            file: localReframe.outputUrl
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
