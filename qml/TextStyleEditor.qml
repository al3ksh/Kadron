import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

// Font, size, colour, look and a quick spot for one text (a TextOverlay map).
// Changes come out as a map of the fields that changed; the size slider only
// reports on release and shows its value through draftSize meanwhile.
ColumnLayout {
    id: editor
    property var item: null
    readonly property real draftSize: sizeSlider.pressed ? sizeSlider.value / 100 : -1
    signal changeRequested(var changes)

    readonly property var fonts: [
        { value: "sans", label: "Sans" }, { value: "impact", label: "Impact" }, { value: "black", label: "Heavy" },
        { value: "serif", label: "Serif" }, { value: "mono", label: "Mono" }
    ]
    readonly property var looks: [
        { value: "outline", label: "Outline" }, { value: "box", label: "Box" }, { value: "shadow", label: "Shadow" }
    ]
    readonly property var swatches: ["#ffffff", "#ffd400", "#ff3b30", "#35c6ff", "#3ddc84", "#000000"]

    function indexOf(list, value) {
        for (let i = 0; i < list.length; ++i)
            if (list[i].value === value) return i
        return 0
    }

    spacing: 6
    // Using a control breaks its binding, so every new item resets them.
    function sync() {
        fontCombo.currentIndex = item ? indexOf(fonts, item.font) : 0
        lookCombo.currentIndex = item ? indexOf(looks, item.style) : 0
        if (!sizeSlider.pressed) sizeSlider.value = item ? item.size * 100 : 6.5
    }
    onItemChanged: sync()
    Component.onCompleted: sync()

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        ToolCombo {
            id: fontCombo
            objectName: "textFontCombo"
            Layout.fillWidth: true
            textRole: "label"
            valueRole: "value"
            model: editor.fonts
            onActivated: editor.changeRequested({ font: currentValue })
        }
        ToolCombo {
            id: lookCombo
            objectName: "textLookCombo"
            Layout.fillWidth: true
            textRole: "label"
            valueRole: "value"
            model: editor.looks
            onActivated: editor.changeRequested({ style: currentValue })
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text { text: "Size"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: 11 }
        ToolSlider {
            id: sizeSlider
            objectName: "textSizeSlider"
            Layout.fillWidth: true
            from: 2
            to: 25
            stepSize: 0.5
            value: 6.5
            onPressedChanged: if (!pressed && editor.item && Math.abs(value / 100 - editor.item.size) > 0.0001)
                                  editor.changeRequested({ size: value / 100 })
            // Arrow keys change it without a press.
            onMoved: if (!pressed) editor.changeRequested({ size: value / 100 })
        }
        Text {
            Layout.preferredWidth: 30
            horizontalAlignment: Text.AlignRight
            text: Math.round(sizeSlider.value * 10) / 10 + "%"
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: editor.swatches
            delegate: Rectangle {
                required property string modelData
                readonly property bool current: editor.item !== null && editor.item.color === modelData
                implicitWidth: 22
                implicitHeight: 22
                radius: 11
                color: modelData
                border.width: current ? 2 : 1
                border.color: current ? Theme.accent : Theme.lineStrong
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -2
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editor.changeRequested({ color: parent.modelData })
                }
            }
        }
        Rectangle {
            objectName: "textCustomColor"
            readonly property bool current: editor.item !== null && editor.swatches.indexOf(editor.item.color) < 0
            implicitWidth: 22
            implicitHeight: 22
            radius: 11
            color: current ? editor.item.color : Theme.field
            border.width: current ? 2 : 1
            border.color: current ? Theme.accent : Theme.lineStrong
            ToolIcon {
                visible: !parent.current
                anchors.centerIn: parent
                width: 12
                height: 12
                name: "plus"
                tint: Theme.textMuted
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -2
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    colorDialog.selectedColor = editor.item ? editor.item.color : "#ffffff"
                    colorDialog.open()
                }
            }
            ToolTip.visible: customHover.hovered
            ToolTip.delay: 500
            ToolTip.text: "Any colour"
            HoverHandler { id: customHover }
        }
        Item { Layout.fillWidth: true }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            // Quick spots; dragging the text on the picture places it anywhere.
            model: [{ label: "Top", at: "top" }, { label: "Middle", at: "middle" }, { label: "Bottom", at: "bottom" }]
            delegate: EditorButton {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 30
                text: modelData.label
                subtle: true
                onClicked: {
                    const size = editor.item ? editor.item.size : 0.065
                    const y = modelData.at === "top" ? 0.07 + size * 0.6 : modelData.at === "middle" ? 0.5 : 0.93 - size * 0.6
                    editor.changeRequested({ x: 0.5, y: y })
                }
            }
        }
    }

    ColorDialog {
        id: colorDialog
        title: "Text colour"
        onAccepted: editor.changeRequested({ color: selectedColor.toString() })
    }
}
