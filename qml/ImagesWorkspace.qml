import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

// Images: batch convert, resize, crop and clean photos on this device.
// Output settings apply to every image; crop, rotation and flips belong to
// each image. Saved copies never carry metadata (see LocalImageTools).
Item {
    id: imagesPage
    objectName: "imagesArea"

    // One entry per image: url, rotate, flipH, flipV, cropX/Y/W/H, aspect.
    ListModel { id: edits }
    property int selected: -1
    // Bumped on every edit so bindings that read `edits` re-evaluate.
    property int revision: 0
    readonly property var current: revision, selected >= 0 && selected < edits.count ? edits.get(selected) : null
    readonly property var currentInfo: current ? (localImages.infos[current.url] || null) : null

    // Output settings, shared by all images.
    property string format: "same"
    property int quality: 82
    property string resizeMode: "none"
    property string view: "crop"

    readonly property var aspects: [["free", "Free", 0], ["original", "Original", -1], ["1:1", "1:1", 1], ["4:5", "4:5", 0.8],
                                   ["3:2", "3:2", 1.5], ["16:9", "16:9", 16 / 9], ["9:16", "9:16", 9 / 16]]

    function isImage(url) { return localImages.isImageFile(url) }
    function sizeLabel(bytes) {
        if (!bytes) return "0 KB"
        return bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(bytes / 1024)) + " KB"
    }
    function formatLabel(ext) { return ext ? (ext === "jpeg" ? "JPG" : ext.toUpperCase()) : "" }
    function outputLabel(ext) {
        if (format !== "same") return formatLabel(format)
        var e = (ext || "").toLowerCase()
        if (e === "jpg" || e === "jpeg" || e === "png" || e === "webp" || e === "avif") return formatLabel(e)
        return e === "bmp" || e === "tif" || e === "tiff" || e === "gif" ? "PNG" : "JPG"
    }
    readonly property bool lossless: format === "png"

    function addFiles(urls) {
        var added = []
        var known = {}
        for (var i = 0; i < edits.count; i++) known[edits.get(i).url] = true
        for (var j = 0; j < urls.length; j++) {
            var key = urls[j].toString()
            if (known[key] || !isImage(urls[j])) continue
            known[key] = true
            edits.append({ url: key, rotate: 0, flipH: false, flipV: false, cropX: 0, cropY: 0, cropW: 1, cropH: 1, aspect: "free" })
            added.push(urls[j])
        }
        if (added.length > 0) {
            localImages.inspect(added)
            if (selected < 0) selected = edits.count - added.length
            localImages.clearResults()
        }
        revision++
        return added.length
    }
    function removeAt(index) {
        if (index < 0 || index >= edits.count) return
        edits.remove(index)
        if (selected >= edits.count) selected = edits.count - 1
        revision++
    }
    function clearAll() {
        edits.clear()
        selected = -1
        localImages.clearResults()
        revision++
    }
    function update(index, changes) {
        if (index < 0 || index >= edits.count) return
        for (var key in changes) edits.setProperty(index, key, changes[key])
        revision++
    }

    // Shown size of an image after its rotation (EXIF orientation is already in the info).
    function viewSize(item, info) {
        if (!item || !info || !info.width) return Qt.size(0, 0)
        var quarter = item.rotate % 180 !== 0
        return Qt.size(quarter ? info.height : info.width, quarter ? info.width : info.height)
    }
    function aspectRatio(item, info) {
        if (!item) return 0
        for (var i = 0; i < aspects.length; i++) if (aspects[i][0] === item.aspect) {
            if (aspects[i][2] === -1) { var v = viewSize(item, info); return v.height > 0 ? v.width / v.height : 0 }
            return aspects[i][2]
        }
        return 0
    }
    // The largest centred crop of `ratio` (width / height in pixels); 0 is the whole image.
    function fitCrop(ratio, view) {
        if (ratio <= 0 || view.width <= 0) return { cropX: 0, cropY: 0, cropW: 1, cropH: 1 }
        var w = 1, h = 1
        if (view.width / view.height > ratio) w = ratio * view.height / view.width
        else h = view.width / (ratio * view.height)
        return { cropX: (1 - w) / 2, cropY: (1 - h) / 2, cropW: w, cropH: h }
    }
    function setAspect(key) {
        if (!current) return
        update(selected, { aspect: key })
        var crop = key === "free" ? { cropX: 0, cropY: 0, cropW: 1, cropH: 1 } : fitCrop(aspectRatio(current, currentInfo), viewSize(current, currentInfo))
        update(selected, crop)
    }
    function rotateBy(angle) {
        if (!current) return
        update(selected, { rotate: (current.rotate + angle + 360) % 360 })
        // A new orientation starts a fresh crop in the chosen shape.
        var ratio = aspectRatio(current, currentInfo)
        update(selected, ratio > 0 ? fitCrop(ratio, viewSize(current, currentInfo)) : { cropX: 0, cropY: 0, cropW: 1, cropH: 1 })
    }
    function resetEdits() {
        if (!current) return
        update(selected, { rotate: 0, flipH: false, flipV: false, cropX: 0, cropY: 0, cropW: 1, cropH: 1, aspect: "free" })
    }

    function job(item) {
        var j = {
            source: item.url, format: format, quality: quality,
            targetKB: lossless ? 0 : Math.max(0, Number(targetField.text) || 0),
            resize: resizeMode, longEdge: Number(longEdgeField.text) || 0, percent: Number(percentField.text) || 100,
            boxWidth: Number(boxWidthField.text) || 0, boxHeight: Number(boxHeightField.text) || 0,
            rotate: item.rotate, flipH: item.flipH, flipV: item.flipV,
            cropX: item.cropX, cropY: item.cropY, cropW: item.cropW, cropH: item.cropH
        }
        j.key = JSON.stringify(j)
        return j
    }
    // The preview follows the selected image and the settings, after a short pause.
    readonly property string previewKey: revision, current && currentInfo && !currentInfo.error ? job(current).key : ""
    onPreviewKeyChanged: if (previewKey) previewTimer.restart()
    Timer {
        id: previewTimer
        interval: 350
        onTriggered: if (imagesPage.current && imagesPage.previewKey) localImages.renderPreview(imagesPage.job(imagesPage.current))
    }
    // Inspecting finishes after the image is added; start its preview then.
    Connections {
        target: localImages
        function onInfosChanged() { if (imagesPage.previewKey) previewTimer.restart() }
    }
    readonly property var preview: localImages.preview
    readonly property bool previewCurrent: preview && preview.key === previewKey && previewKey !== ""

    function saveAll() {
        var first = edits.count > 0 ? edits.get(0).url : ""
        folderDialog.currentFolder = first ? first.replace(/\/[^\/]*$/, "") : StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        folderDialog.open()
    }
    FolderDialog {
        id: folderDialog
        title: "Save the images in"
        onAccepted: {
            var jobs = []
            for (var i = 0; i < edits.count; i++) jobs.push(imagesPage.job(edits.get(i)))
            localImages.process(jobs, selectedFolder)
        }
    }
    FileDialog {
        id: openDialog
        title: "Add images"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Images (*.jpg *.jpeg *.png *.webp *.avif *.heic *.heif *.bmp *.tif *.tiff *.gif)", "All files (*)"]
        onAccepted: imagesPage.addFiles(selectedFiles)
    }

    Rectangle { anchors.fill: parent; color: Theme.window }

    DropArea {
        id: pageDrop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: function(drop) { if (drop.hasUrls) imagesPage.addFiles(drop.urls) }
    }

    // Empty state.
    DropZone {
        visible: edits.count === 0
        anchors.centerIn: parent
        width: Math.min(parent.width - 90, 760)
        height: 300
        active: pageDrop.containsDrag
        iconName: "image"
        heading: "Drop photos or images"
        formats: "JPG · PNG · WEBP · AVIF · HEIC · TIFF · BMP  ·  convert, resize, crop, remove location"
        onBrowseRequested: openDialog.open()
    }

    RowLayout {
        visible: edits.count > 0
        anchors.fill: parent
        spacing: 0

        // Editor: the selected image and the strip of all images.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [["crop", "Crop", "crop"], ["compare", "Compare", "compare"]]
                    delegate: EditorButton {
                        required property var modelData
                        objectName: "imageView_" + modelData[0]
                        text: modelData[1]
                        iconName: modelData[2]
                        primary: imagesPage.view === modelData[0]
                        subtle: imagesPage.view !== modelData[0]
                        onClicked: imagesPage.view = modelData[0]
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: imagesPage.currentInfo && imagesPage.currentInfo.name ? imagesPage.currentInfo.name : ""
                    color: Theme.textMuted
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 360
                }
            }

            // Stage.
            Rectangle {
                id: stage
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusLarge
                color: Theme.canvas
                clip: true

                readonly property size view: imagesPage.viewSize(imagesPage.current, imagesPage.currentInfo)
                readonly property real fit: view.width > 0 ? Math.min((width - 48) / view.width, (height - 48) / view.height) : 0

                Text {
                    anchors.centerIn: parent
                    visible: !imagesPage.currentInfo || !!imagesPage.currentInfo.error
                    text: imagesPage.currentInfo && imagesPage.currentInfo.error ? imagesPage.currentInfo.error : "Reading image…"
                    color: imagesPage.currentInfo && imagesPage.currentInfo.error ? Theme.danger : Theme.textMuted
                    font.pixelSize: 13
                }

                // Crop view: the image as it will be oriented, with the crop frame.
                Item {
                    id: frame
                    visible: imagesPage.view === "crop" && imagesPage.currentInfo && !imagesPage.currentInfo.error
                    anchors.centerIn: parent
                    width: stage.view.width * stage.fit
                    height: stage.view.height * stage.fit

                    CheckerBoard {
                        anchors.fill: parent
                        visible: !!(imagesPage.currentInfo && imagesPage.currentInfo.hasAlpha)
                    }
                    // Flips act on the rotated image, as FFmpeg applies them.
                    Item {
                        anchors.fill: parent
                        transform: Scale {
                            origin.x: frame.width / 2
                            origin.y: frame.height / 2
                            xScale: imagesPage.current && imagesPage.current.flipH ? -1 : 1
                            yScale: imagesPage.current && imagesPage.current.flipV ? -1 : 1
                        }
                        Image {
                            anchors.centerIn: parent
                            readonly property bool quarter: imagesPage.current ? imagesPage.current.rotate % 180 !== 0 : false
                            width: quarter ? frame.height : frame.width
                            height: quarter ? frame.width : frame.height
                            rotation: imagesPage.current ? imagesPage.current.rotate : 0
                            source: imagesPage.currentInfo && imagesPage.currentInfo.thumb ? imagesPage.currentInfo.thumb : ""
                            sourceSize.width: 1600
                            sourceSize.height: 1600
                            fillMode: Image.Stretch
                            autoTransform: true
                            asynchronous: true
                            smooth: true
                        }
                    }

                    CropOverlay {
                        id: cropOverlay
                        anchors.fill: parent
                        item: imagesPage.current
                        ratio: imagesPage.aspectRatio(imagesPage.current, imagesPage.currentInfo)
                        viewSize: stage.view
                        revision: imagesPage.revision
                        onCommitted: function(crop) { imagesPage.update(imagesPage.selected, crop) }
                    }
                }

                // Compare view: the original pixels and the saved result, split by a handle.
                Item {
                    id: compare
                    visible: imagesPage.view === "compare" && imagesPage.currentInfo && !imagesPage.currentInfo.error
                    anchors.fill: parent
                    anchors.margins: 24
                    property real split: 0.5
                    readonly property bool ready: imagesPage.previewCurrent && !!imagesPage.preview.before && !!imagesPage.preview.after
                    Image {
                        id: beforeImage
                        anchors.fill: parent
                        source: compare.ready ? imagesPage.preview.before : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    Item {
                        x: 0
                        width: parent.width * compare.split
                        height: parent.height
                        clip: true
                        Image {
                            width: compare.width
                            height: compare.height
                            source: compare.ready ? imagesPage.preview.after : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                    }
                    Rectangle {
                        visible: compare.ready
                        x: parent.width * compare.split - 1
                        width: 2
                        height: parent.height
                        color: Theme.accent
                        Rectangle {
                            anchors.centerIn: parent
                            width: 28; height: 28; radius: 14
                            color: Theme.accent
                            ToolIcon { anchors.centerIn: parent; width: 16; height: 16; name: "split"; tint: Theme.accentInk }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: compare.ready
                        cursorShape: Qt.SizeHorCursor
                        onPressed: function(mouse) { compare.split = Math.max(0, Math.min(1, mouse.x / width)) }
                        onPositionChanged: function(mouse) { if (pressed) compare.split = Math.max(0, Math.min(1, mouse.x / width)) }
                    }
                    Rectangle {
                        visible: compare.ready
                        anchors.left: parent.left
                        anchors.top: parent.top
                        width: afterTag.implicitWidth + 16; height: 24; radius: 12
                        color: Theme.chipScrim
                        Text { id: afterTag; anchors.centerIn: parent; text: "Saved · " + (imagesPage.preview.format || "").toUpperCase() + " · " + imagesPage.sizeLabel(imagesPage.preview.bytes); color: "#f1f4ef"; font.pixelSize: 11; font.weight: Font.DemiBold }
                    }
                    Rectangle {
                        visible: compare.ready
                        anchors.right: parent.right
                        anchors.top: parent.top
                        width: beforeTag.implicitWidth + 16; height: 24; radius: 12
                        color: Theme.chipScrim
                        Text { id: beforeTag; anchors.centerIn: parent; text: "Original · " + imagesPage.sizeLabel(imagesPage.currentInfo ? imagesPage.currentInfo.bytes : 0); color: "#f1f4ef"; font.pixelSize: 11; font.weight: Font.DemiBold }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !compare.ready
                        text: imagesPage.preview && imagesPage.preview.error && imagesPage.previewCurrent ? imagesPage.preview.error : "Rendering the result…"
                        color: imagesPage.preview && imagesPage.preview.error && imagesPage.previewCurrent ? Theme.danger : Theme.textMuted
                        font.pixelSize: 13
                    }
                }
            }

            // All images.
            ListView {
                id: strip
                objectName: "imageStrip"
                Layout.fillWidth: true
                Layout.preferredHeight: 128
                orientation: ListView.Horizontal
                spacing: 10
                clip: true
                model: edits
                boundsBehavior: Flickable.StopAtBounds
                footer: Item {
                    width: 118
                    height: 118
                    Rectangle {
                        x: 10
                        width: 108; height: 118
                        radius: 10
                        color: addMouse.containsMouse ? Theme.accentWash : "transparent"
                        border.width: 1.5
                        border.color: addMouse.containsMouse ? Theme.accentEdge : Theme.lineStrong
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            ToolIcon { anchors.horizontalCenter: parent.horizontalCenter; width: 22; height: 22; name: "plus"; tint: addMouse.containsMouse ? Theme.accent : Theme.textMuted }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Add images"; color: Theme.textSoft; font.pixelSize: 11; font.weight: Font.DemiBold }
                        }
                        MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: openDialog.open() }
                    }
                }
                delegate: Rectangle {
                    id: card
                    required property int index
                    required property string url
                    readonly property var info: localImages.infos[url] || null
                    readonly property bool chosen: index === imagesPage.selected
                    width: 118
                    height: 118
                    radius: 10
                    color: Theme.field
                    border.width: chosen ? 2 : 1
                    border.color: chosen ? Theme.accent : cardMouse.containsMouse ? Theme.lineStrong : Theme.line
                    clip: true
                    CheckerBoard {
                        anchors.fill: parent
                        anchors.margins: 2
                        visible: !!(card.info && card.info.hasAlpha)
                    }
                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: card.info && card.info.thumb ? card.info.thumb : ""
                        sourceSize.width: 236
                        sourceSize.height: 236
                        fillMode: Image.PreserveAspectCrop
                        autoTransform: true
                        asynchronous: true
                        opacity: card.chosen ? 1 : 0.85
                    }
                    SkeletonBlock { anchors.fill: parent; anchors.margins: 2; visible: !card.info }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 2
                        height: 34
                        radius: 8
                        color: Theme.chipScrim
                        Column {
                            anchors.fill: parent
                            anchors.leftMargin: 7
                            anchors.rightMargin: 7
                            anchors.topMargin: 3
                            Text { width: parent.width; text: card.info ? card.info.name : ""; color: "#f1f4ef"; font.pixelSize: 10; font.weight: Font.DemiBold; elide: Text.ElideMiddle }
                            Text {
                                width: parent.width
                                text: !card.info ? "" : card.info.error ? card.info.error : imagesPage.formatLabel(card.info.format) + " · " + imagesPage.sizeLabel(card.info.bytes)
                                color: card.info && card.info.error ? Theme.danger : "#c3ccd0"
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                        }
                    }
                    Rectangle {
                        visible: !!(card.info && card.info.hasGps)
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 6
                        width: 22; height: 22; radius: 11
                        color: Theme.chipScrim
                        ToolIcon { anchors.centerIn: parent; width: 13; height: 13; name: "pin"; tint: Theme.warning }
                        ToolTip.visible: gpsHover.hovered
                        ToolTip.text: "Has a location. It is removed when saved."
                        HoverHandler { id: gpsHover }
                    }
                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: imagesPage.selected = card.index
                    }
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 6
                        width: 22; height: 22; radius: 11
                        visible: cardMouse.containsMouse || removeMouse.containsMouse
                        color: removeMouse.containsMouse ? Theme.dangerStrong : Theme.chipScrim
                        ToolIcon { anchors.centerIn: parent; width: 12; height: 12; name: "close"; tint: "#f1f4ef" }
                        MouseArea { id: removeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: imagesPage.removeAt(card.index) }
                    }
                }
            }
        }

        // Settings.
        Rectangle {
            Layout.preferredWidth: 340
            Layout.fillHeight: true
            color: Theme.panel
            Rectangle { width: 1; height: parent.height; color: Theme.line }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                ScrollView {
                    id: settingsScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: settingsScroll.availableWidth
                        spacing: 10

                        Item { Layout.preferredHeight: 8 }
                        Text { Layout.leftMargin: 20; text: "OUTPUT · ALL IMAGES"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            spacing: 4
                            Repeater {
                                model: [["same", "Keep"], ["jpg", "JPG"], ["png", "PNG"], ["webp", "WebP"], ["avif", "AVIF"]]
                                delegate: EditorButton {
                                    required property var modelData
                                    objectName: "imageFormat_" + modelData[0]
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    leftPadding: 4
                                    rightPadding: 4
                                    text: modelData[1]
                                    primary: imagesPage.format === modelData[0]
                                    subtle: imagesPage.format !== modelData[0]
                                    onClicked: imagesPage.format = modelData[0]
                                    ToolTip.visible: hovered && modelData[0] === "same"
                                    ToolTip.text: "Keep each image's format (HEIC becomes JPG)"
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            Layout.topMargin: 4
                            Text { text: "Quality"; color: imagesPage.lossless ? Theme.textDisabled : Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true }
                            Text { text: imagesPage.lossless ? "Lossless" : imagesPage.quality; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold }
                        }
                        ToolSlider {
                            objectName: "imageQuality"
                            Layout.fillWidth: true
                            Layout.leftMargin: 14
                            Layout.rightMargin: 14
                            enabled: !imagesPage.lossless
                            from: 10
                            to: 100
                            stepSize: 1
                            value: imagesPage.quality
                            onMoved: imagesPage.quality = Math.round(value)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            spacing: 8
                            Text { text: "Max file size"; color: imagesPage.lossless ? Theme.textDisabled : Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true }
                            EditorField {
                                id: targetField
                                objectName: "imageTarget"
                                enabled: !imagesPage.lossless
                                Layout.preferredWidth: 90
                                placeholderText: "none"
                                validator: IntValidator { bottom: 0; top: 100000 }
                                horizontalAlignment: Text.AlignRight
                                onTextChanged: imagesPage.revision++
                            }
                            Text { text: "KB"; color: Theme.textMuted; font.pixelSize: 12 }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.topMargin: 8; height: 1; color: Theme.line }
                        Text { Layout.leftMargin: 20; Layout.topMargin: 6; text: "SIZE · ALL IMAGES"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                        ToolCombo {
                            id: resizeCombo
                            objectName: "imageResize"
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            textRole: "label"
                            valueRole: "value"
                            model: [{ value: "none", label: "Original size" }, { value: "long", label: "Longest side" },
                                    { value: "percent", label: "Percent" }, { value: "box", label: "Fit in a box" }]
                            onActivated: imagesPage.resizeMode = currentValue
                        }
                        RowLayout {
                            visible: imagesPage.resizeMode === "long"
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            spacing: 6
                            EditorField { id: longEdgeField; text: "1920"; Layout.preferredWidth: 90; onTextChanged: imagesPage.revision++; validator: IntValidator { bottom: 1; top: 20000 } }
                            Text { text: "px"; color: Theme.textMuted; font.pixelSize: 12 }
                            Item { Layout.fillWidth: true }
                            Repeater {
                                model: [1080, 1920, 2560]
                                delegate: EditorButton { required property int modelData; text: modelData; subtle: true; onClicked: longEdgeField.text = modelData }
                            }
                        }
                        RowLayout {
                            visible: imagesPage.resizeMode === "percent"
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            spacing: 6
                            EditorField { id: percentField; text: "50"; Layout.preferredWidth: 90; onTextChanged: imagesPage.revision++; validator: IntValidator { bottom: 1; top: 100 } }
                            Text { text: "%"; color: Theme.textMuted; font.pixelSize: 12 }
                        }
                        RowLayout {
                            visible: imagesPage.resizeMode === "box"
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            spacing: 6
                            EditorField { id: boxWidthField; text: "1920"; Layout.preferredWidth: 80; onTextChanged: imagesPage.revision++; validator: IntValidator { bottom: 1; top: 20000 } }
                            Text { text: "×"; color: Theme.textMuted; font.pixelSize: 12 }
                            EditorField { id: boxHeightField; text: "1080"; Layout.preferredWidth: 80; onTextChanged: imagesPage.revision++; validator: IntValidator { bottom: 1; top: 20000 } }
                            Text { text: "px"; color: Theme.textMuted; font.pixelSize: 12 }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            visible: imagesPage.resizeMode !== "none"
                            text: "Smaller images are never enlarged."
                            color: Theme.textFaint
                            font.pixelSize: 11
                        }

                        Rectangle { Layout.fillWidth: true; Layout.topMargin: 8; height: 1; color: Theme.line }
                        Text { Layout.leftMargin: 20; Layout.topMargin: 6; text: "CROP & ROTATE · THIS IMAGE"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            spacing: 6
                            EditorButton { iconName: "rotateLeft"; subtle: true; enabled: !!imagesPage.current; onClicked: imagesPage.rotateBy(-90); ToolTip.visible: hovered; ToolTip.text: "Rotate left" }
                            EditorButton { objectName: "imageRotateRight"; iconName: "rotateRight"; subtle: true; enabled: !!imagesPage.current; onClicked: imagesPage.rotateBy(90); ToolTip.visible: hovered; ToolTip.text: "Rotate right" }
                            EditorButton { iconName: "flipH"; subtle: true; enabled: !!imagesPage.current; primary: !!(imagesPage.current && imagesPage.current.flipH); onClicked: imagesPage.update(imagesPage.selected, { flipH: !imagesPage.current.flipH }); ToolTip.visible: hovered; ToolTip.text: "Flip horizontally" }
                            EditorButton { iconName: "flipV"; subtle: true; enabled: !!imagesPage.current; primary: !!(imagesPage.current && imagesPage.current.flipV); onClicked: imagesPage.update(imagesPage.selected, { flipV: !imagesPage.current.flipV }); ToolTip.visible: hovered; ToolTip.text: "Flip vertically" }
                            Item { Layout.fillWidth: true }
                            EditorButton { text: "Reset"; subtle: true; enabled: !!imagesPage.current; onClicked: imagesPage.resetEdits() }
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            columns: 4
                            columnSpacing: 4
                            rowSpacing: 4
                            Repeater {
                                model: imagesPage.aspects
                                delegate: EditorButton {
                                    required property var modelData
                                    objectName: "imageAspect_" + modelData[0]
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    leftPadding: 4
                                    rightPadding: 4
                                    text: modelData[1]
                                    enabled: !!imagesPage.current
                                    primary: !!(imagesPage.current && imagesPage.current.aspect === modelData[0])
                                    subtle: !(imagesPage.current && imagesPage.current.aspect === modelData[0])
                                    onClicked: imagesPage.setAspect(modelData[0])
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.topMargin: 8; height: 1; color: Theme.line }
                        Text { Layout.leftMargin: 20; Layout.topMargin: 6; text: "THIS IMAGE"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 6
                            visible: !!imagesPage.currentInfo && !imagesPage.currentInfo.error
                            readonly property var info: imagesPage.currentInfo || ({})
                            Text { text: "Original"; color: Theme.textMuted; font.pixelSize: 12 }
                            Text { Layout.fillWidth: true; text: (parent.info.width || 0) + " × " + (parent.info.height || 0) + " · " + imagesPage.sizeLabel(parent.info.bytes) + " · " + imagesPage.formatLabel(parent.info.format); color: Theme.text; font.pixelSize: 12; elide: Text.ElideRight }
                            Text { text: "Saved as"; color: Theme.textMuted; font.pixelSize: 12 }
                            Text {
                                objectName: "imageResult"
                                Layout.fillWidth: true
                                text: !imagesPage.previewCurrent ? "…"
                                      : imagesPage.preview.error ? "Can't save with these settings"
                                      : imagesPage.preview.width + " × " + imagesPage.preview.height + " · " + imagesPage.sizeLabel(imagesPage.preview.bytes) + " · " + (imagesPage.preview.format || "").toUpperCase()
                                color: imagesPage.previewCurrent && imagesPage.preview.error ? Theme.danger : Theme.accent
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text { visible: !!parent.info.camera; text: "Camera"; color: Theme.textMuted; font.pixelSize: 12 }
                            Text { visible: !!parent.info.camera; Layout.fillWidth: true; text: parent.info.camera || ""; color: Theme.text; font.pixelSize: 12; elide: Text.ElideRight }
                            Text { visible: !!parent.info.taken; text: "Taken"; color: Theme.textMuted; font.pixelSize: 12 }
                            Text { visible: !!parent.info.taken; Layout.fillWidth: true; text: parent.info.taken || ""; color: Theme.text; font.pixelSize: 12 }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            visible: imagesPage.previewCurrent && !!imagesPage.preview.note
                            text: imagesPage.preview.note || ""
                            color: Theme.warning
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                        // Location warning.
                        Rectangle {
                            visible: !!(imagesPage.currentInfo && imagesPage.currentInfo.hasGps)
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            implicitHeight: gpsColumn.implicitHeight + 18
                            radius: Theme.radius
                            color: Theme.tint(Theme.panel, Theme.warning, 0.12)
                            border.color: Theme.tint(Theme.panel, Theme.warning, 0.4)
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 9
                                spacing: 8
                                ToolIcon { Layout.alignment: Qt.AlignTop; name: "pin"; tint: Theme.warning }
                                ColumnLayout {
                                    id: gpsColumn
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text { text: "This photo records where it was taken"; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                    Text {
                                        text: imagesPage.currentInfo && imagesPage.currentInfo.hasGps ? imagesPage.currentInfo.latitude.toFixed(4) + ", " + imagesPage.currentInfo.longitude.toFixed(4) + " · removed when saved" : ""
                                        color: Theme.textMuted
                                        font.pixelSize: 11
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Layout.rightMargin: 20
                            Layout.bottomMargin: 12
                            text: "Saved copies carry no metadata: camera, date and location are left out. Originals are not changed."
                            color: Theme.textFaint
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // Save.
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        visible: localImages.busy || localImages.results.length > 0 || localImages.errorText.length > 0
                        text: {
                            if (localImages.busy) return localImages.stage + "…"
                            var before = 0, after = 0
                            for (var i = 0; i < localImages.results.length; i++) {
                                var r = localImages.results[i]
                                if (!r.error) { before += r.sourceBytes; after += r.bytes }
                            }
                            return localImages.stage + (after > 0 ? " · " + imagesPage.sizeLabel(before) + " → " + imagesPage.sizeLabel(after) : "")
                        }
                        color: Theme.textSoft
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Text { Layout.fillWidth: true; visible: localImages.errorText.length > 0 && !localImages.busy; text: localImages.errorText; color: Theme.danger; font.pixelSize: 11; wrapMode: Text.WordWrap }
                    StudioProgress { Layout.fillWidth: true; visible: localImages.busy; value: localImages.progress / 100 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        EditorButton {
                            objectName: "imagesSave"
                            Layout.fillWidth: true
                            visible: !localImages.busy
                            primary: true
                            iconName: "save"
                            text: edits.count === 1 ? "Save image…" : "Save " + edits.count + " images…"
                            enabled: edits.count > 0 && localImages.available
                            onClicked: imagesPage.saveAll()
                        }
                        EditorButton { Layout.fillWidth: true; visible: localImages.busy; text: "Stop"; danger: true; onClicked: localImages.cancel() }
                        EditorButton {
                            visible: !localImages.busy && localImages.results.length > 0
                            iconName: "folder"
                            subtle: true
                            onClicked: Qt.openUrlExternally(localImages.outputFolder)
                            ToolTip.visible: hovered
                            ToolTip.text: "Open the folder"
                        }
                        EditorButton { iconName: "trash"; subtle: true; enabled: !localImages.busy; onClicked: imagesPage.clearAll(); ToolTip.visible: hovered; ToolTip.text: "Remove all images" }
                    }
                }
            }
        }
    }
}
