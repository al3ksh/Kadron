import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kadron.Backend

// PDF Tools: edit, merge, extract pages and turn images into a PDF.
ColumnLayout {
    id: pdfPanel
    // The Tools page: section, sources, jobs and the dialogs it owns.
    required property var page
    property alias pagesField: pdfPages
    visible: page.section === 5
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
                primary: page.pdfMode === modelData[0]
                subtle: page.pdfMode !== modelData[0]
                onClicked: page.setPdfMode(modelData[0])
            }
        }
    }
    DropZone {
        visible: page.pdfFiles.length === 0
        Layout.fillWidth: true
        implicitHeight: 220
        active: page.dropArea.containsDrag
        iconName: page.pdfMode === "images-to-pdf" ? "drop" : "pdf"
        heading: page.pdfMode === "images-to-pdf" ? "Drop images to combine" : page.pdfMode === "merge" ? "Drop the PDFs to merge" : "Drop a PDF"
        formats: page.pdfMode === "images-to-pdf" ? "JPG · PNG · WEBP · BMP · TIFF" : page.pdfMode === "edit" ? "PDF · reorder, rotate and remove pages visually" : "PDF"
        onBrowseRequested: page.pdfPicker.open()
    }
    Rectangle {
        visible: page.pdfFiles.length > 0 && !page.pdfUsesBoard
        Layout.fillWidth: true
        implicitHeight: 54
        radius: Theme.radius
        color: page.dropArea.containsDrag ? Theme.accentWash : Theme.field
        border.color: page.dropArea.containsDrag ? Theme.accent : Theme.line
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 8
            spacing: 10
            ToolIcon { name: "pdf"; tint: Theme.accent }
            Text {
                Layout.fillWidth: true
                text: page.dropArea.containsDrag ? "Drop to replace" : page.pdfFiles.map(function(file) { return decodeURIComponent(page.filename(file)) }).join(", ")
                color: Theme.text
                font.pixelSize: 13
                elide: Text.ElideMiddle
            }
            Text {
                text: page.pdfMode === "edit" ? (Core.localPdf.loadingPages ? "Reading pages…" : Core.localPdf.pageImages.length + " pages")
                      : page.pdfFiles.length + (page.pdfFiles.length === 1 ? " file" : " files")
                color: Theme.textMuted
                font.pixelSize: 11
            }
            EditorButton { text: "Change"; subtle: true; onClicked: page.pdfPicker.open() }
            EditorButton { iconName: "close"; subtle: true; enabled: !Core.localPdf.busy; onClicked: page.pdfFiles = [] }
        }
    }
    Text { visible: !Core.localPdf.qpdfAvailable && page.pdfMode !== "images-to-pdf"; text: "Install qpdf locally or set KADRON_QPDF for this operation."; color: Theme.warning; font.pixelSize: 12 }
    Text { visible: page.pdfMode === "edit" && Core.localPdf.pagesError.length > 0; text: Core.localPdf.pagesError; color: Theme.danger; font.pixelSize: 12 }

    // Visual page editor.
    RowLayout {
        visible: page.pdfMode === "edit" && page.pdfPageModel.count > 0
        Layout.fillWidth: true
        spacing: 6
        Text {
            Layout.fillWidth: true
            text: page.pdfPageModel.count + " pages" + (page.pdfSelected > 0 ? " · " + page.pdfSelected + " selected" : " · click to select, drag to reorder, double-click to preview")
            color: Theme.textMuted
            font.pixelSize: 12
            elide: Text.ElideRight
        }
        EditorButton { text: page.pdfSelected === page.pdfPageModel.count ? "Select none" : "Select all"; subtle: true; onClicked: page.selectAllPages(page.pdfSelected !== page.pdfPageModel.count) }
        EditorButton { iconName: "rotateLeft"; subtle: true; enabled: page.pdfSelected > 0; onClicked: page.rotateSelected(-90); ToolTip.visible: hovered; ToolTip.text: "Rotate selected left" }
        EditorButton { iconName: "rotateRight"; subtle: true; enabled: page.pdfSelected > 0; onClicked: page.rotateSelected(90); ToolTip.visible: hovered; ToolTip.text: "Rotate selected right" }
        EditorButton { iconName: "trash"; subtle: true; danger: true; enabled: page.pdfSelected > 0 && page.pdfSelected < page.pdfPageModel.count; onClicked: page.deleteSelected(); ToolTip.visible: hovered; ToolTip.text: "Remove selected pages" }
        EditorButton { text: "Reset"; subtle: true; enabled: page.pdfEdited; onClicked: page.resetPages() }
    }
    Item {
        visible: page.pdfMode === "edit" && (page.pdfPageModel.count > 0 || Core.localPdf.loadingPages)
        Layout.fillWidth: true
        implicitHeight: Core.localPdf.loadingPages ? 220 : pageGrid.contentHeight + 8
        // Loading skeleton in the grid's shape.
        Flow {
            anchors.fill: parent
            visible: Core.localPdf.loadingPages
            spacing: 14
            Repeater {
                model: 5
                delegate: SkeletonBlock { width: 136; height: 194; radius: 10 }
            }
        }
        GridView {
            id: pageGrid
            anchors.fill: parent
            visible: !Core.localPdf.loadingPages
            interactive: false
            cellWidth: 150
            cellHeight: 214
            model: page.pdfPageModel
            displaced: Transition { SmoothSpring { properties: "x,y" } }
            delegate: DropArea {
                id: slot
                required property int index
                required property int page
                required property int rotation
                required property bool selected
                width: pageGrid.cellWidth
                height: pageGrid.cellHeight
                keys: ["kadron-page-card"]
                onEntered: function(drag) {
                    if (drag.source && drag.source.visualIndex !== slot.index) {
                        page.pdfPageModel.move(drag.source.visualIndex, slot.index, 1)
                        page.pdfEdited = true
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
                    Drag.keys: ["kadron-page-card"]
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
                            source: Core.localPdf.pageImages[slot.page - 1] || ""
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
                    // Unlike cardMouse, stays hovered while the pointer is on the page buttons.
                    HoverHandler { id: cardHover }
                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        drag.target: pageCard
                        cursorShape: pageCard.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        onClicked: page.pdfPageModel.setProperty(slot.index, "selected", !slot.selected)
                        onDoubleClicked: page.openPagePreview(slot.index)
                        onReleased: pageCard.Drag.drop()
                    }
                    // Per-page actions on hover.
                    Row {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 6
                        spacing: 2
                        opacity: cardHover.hovered && !pageCard.dragging ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.fadeFast } }
                        Repeater {
                            model: [["rotateLeft", -90, "Rotate left"], ["rotateRight", 90, "Rotate right"], ["zoom", 0, "View larger"], ["trash", 0, "Remove page"]]
                            delegate: Rectangle {
                                required property var modelData
                                width: 26
                                height: 26
                                radius: 7
                                color: actionMouse.containsMouse ? (modelData[0] === "trash" ? Theme.dangerStrong : Theme.pressed) : Theme.chipScrim
                                ToolTip.visible: actionMouse.containsMouse
                                ToolTip.delay: 400
                                ToolTip.text: modelData[2]
                                ToolIcon { anchors.centerIn: parent; width: 15; height: 15; name: parent.modelData[0]; tint: parent.modelData[0] === "trash" && !actionMouse.containsMouse ? Theme.danger : "#f1f4ef" }
                                MouseArea {
                                    id: actionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (parent.modelData[0] === "trash") page.removePage(slot.index)
                                        else if (parent.modelData[0] === "zoom") page.openPagePreview(slot.index)
                                        else page.rotatePage(slot.index, parent.modelData[1])
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Merge / Images to PDF: ordered cards with an Add tile.
    RowLayout {
        visible: page.pdfUsesBoard && page.pdfFiles.length > 0
        Layout.fillWidth: true
        spacing: 6
        Text {
            Layout.fillWidth: true
            text: {
                var n = page.pdfFiles.length
                if (page.pdfMode === "images-to-pdf") return n + (n === 1 ? " image · one page each" : " images · one page each, in this order")
                var pages = 0
                for (var i = 0; i < n; i++) pages += (Core.localPdf.covers[page.pdfFiles[i].toString()] || {}).pages || 0
                return n + (n === 1 ? " file" : " files") + (pages ? " · " + pages + " pages" : "") + (n < 2 ? " · add at least one more" : " · drag to set the order")
            }
            color: Theme.textMuted
            font.pixelSize: 12
        }
        EditorButton { text: "Clear"; subtle: true; enabled: !Core.localPdf.busy; onClicked: page.pdfFiles = [] }
    }
    FileBoard {
        objectName: "pdfFileBoard"
        visible: page.pdfUsesBoard && page.pdfFiles.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        files: page.pdfFiles
        images: page.pdfMode === "images-to-pdf"
        covers: Core.localPdf.covers
        onReordered: function(files) { page.pdfFiles = files }
        onRemoveRequested: function(index) { page.removePdfFile(index) }
        onAddRequested: page.pdfPicker.open()
    }

    // Extract pages: pick on the thumbnails or type a range.
    RowLayout {
        visible: page.pdfMode === "split" && page.pdfFiles.length > 0
        Layout.fillWidth: true
        spacing: 6
        EditorField {
            id: pdfPages
            objectName: "pdfPages"
            Layout.fillWidth: true
            Layout.maximumWidth: 420
            placeholderText: "Click pages below, or type e.g. 1, 3-5"
            onTextEdited: page.splitPages = Core.localPdf.rangeToPages(text, Core.localPdf.pageImages.length)
        }
        EditorButton { text: "All"; subtle: true; onClicked: { var p = []; for (var i = 1; i <= Core.localPdf.pageImages.length; i++) p.push(i); page.setSplitPages(p) } }
        EditorButton { text: "Odd"; subtle: true; onClicked: { var p = []; for (var i = 1; i <= Core.localPdf.pageImages.length; i += 2) p.push(i); page.setSplitPages(p) } }
        EditorButton { text: "Even"; subtle: true; onClicked: { var p = []; for (var i = 2; i <= Core.localPdf.pageImages.length; i += 2) p.push(i); page.setSplitPages(p) } }
        EditorButton { text: "None"; subtle: true; enabled: page.splitPages.length > 0; onClicked: page.setSplitPages([]) }
        Item { Layout.fillWidth: true }
        Text {
            text: page.splitPages.length > 0 ? page.splitPages.length + " of " + Core.localPdf.pageImages.length + " pages" : "Shift+click picks a run"
            color: Theme.textMuted
            font.pixelSize: 12
        }
    }
    Item {
        visible: page.pdfMode === "split" && page.pdfFiles.length > 0 && Core.localPdf.loadingPages
        Layout.fillWidth: true
        implicitHeight: 200
        Row {
            spacing: 10
            Repeater { model: 5; SkeletonBlock { width: 134; height: 194; radius: 10 } }
        }
    }
    PagePicker {
        objectName: "pagePicker"
        visible: page.pdfMode === "split" && page.pdfFiles.length > 0 && !Core.localPdf.loadingPages
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        images: Core.localPdf.pageImages
        selected: page.splitPages
        onSelectionEdited: function(pages) { page.setSplitPages(pages) }
    }
    Text { text: "Documents stay on this device."; color: Theme.textFaint; font.pixelSize: 11 }
    EditorButton {
        text: page.pdfMode === "edit" ? "Save PDF" : page.pdfMode === "merge" ? "Merge PDFs" : page.pdfMode === "split" ? "Extract pages" : "Create PDF"
        iconName: "save"
        primary: true
        enabled: !Core.localPdf.busy && (page.pdfMode === "edit" ? page.pdfPageModel.count > 0 && Core.localPdf.qpdfAvailable
                 : page.pdfFiles.length > (page.pdfMode === "merge" ? 1 : 0) && (Core.localPdf.qpdfAvailable || page.pdfMode === "images-to-pdf") && (page.pdfMode !== "split" || page.splitPages.length > 0))
        onClicked: page.openPdfSave()
    }
}
