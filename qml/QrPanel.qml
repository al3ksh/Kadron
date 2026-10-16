import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// QR: live preview while typing, styled and exported on this device.
RowLayout {
    id: qrPanel
    // The Tools page: section, sources, jobs and the dialogs it owns.
    required property var page
    property alias textField: qrText
    visible: page.section === 6
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
        Timer { id: qrDelay; interval: 150; onTriggered: localQr.update(qrText.text, page.qrLevel) }
        Text { text: "Colors"; color: Theme.textMuted; font.pixelSize: 12 }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: [["#000000", "#ffffff"], ["#ffffff", "#000000"], ["#1a5fb4", "#ffffff"], ["#ffffff", "#1a5fb4"], ["#17200e", "#c9f27a"], ["#c0392b", "#fef9e7"], ["#1e272e", "#f5f6fa"]]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool chosen: page.qrFg === modelData[0] && page.qrBg === modelData[1]
                    width: 36
                    height: 36
                    radius: 9
                    color: modelData[1]
                    border.width: chosen ? 2 : 1
                    border.color: chosen ? Theme.accent : Theme.lineStrong
                    scale: swatchMouse.pressed ? 0.92 : 1
                    Behavior on scale { SnapSpring {} }
                    Rectangle { anchors.centerIn: parent; width: 16; height: 16; radius: 3; color: parent.modelData[0] }
                    MouseArea { id: swatchMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { page.qrFg = parent.modelData[0]; page.qrBg = parent.modelData[1] } }
                }
            }
        }
        RowLayout {
            spacing: 10
            Text { text: "Foreground"; color: Theme.textMuted; font.pixelSize: 12 }
            EditorField {
                Layout.preferredWidth: 100
                text: page.qrFg
                validator: RegularExpressionValidator { regularExpression: /#[0-9a-fA-F]{6}/ }
                onEditingFinished: page.qrFg = text.toLowerCase()
            }
            EditorButton { iconName: "loop"; subtle: true; onClicked: { var fg = page.qrFg; page.qrFg = page.qrBg; page.qrBg = fg } ToolTip.visible: hovered; ToolTip.text: "Swap colors" }
            Text { text: "Background"; color: Theme.textMuted; font.pixelSize: 12 }
            EditorField {
                Layout.preferredWidth: 100
                text: page.qrBg
                validator: RegularExpressionValidator { regularExpression: /#[0-9a-fA-F]{6}/ }
                onEditingFinished: page.qrBg = text.toLowerCase()
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
                    primary: page.qrLevel === modelData[0]
                    onClicked: { page.qrLevel = modelData[0]; localQr.update(qrText.text, page.qrLevel) }
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
                    primary: page.qrSize === modelData
                    onClicked: page.qrSize = modelData
                }
            }
        }
        RowLayout {
            Layout.topMargin: 6
            spacing: 8
            EditorButton { text: "Save PNG"; iconName: "save"; primary: true; enabled: localQr.modules > 0; onClicked: page.openQrSave("png") }
            EditorButton { text: "Save SVG"; iconName: "save"; enabled: localQr.modules > 0; onClicked: page.openQrSave("svg") }
            EditorButton {
                id: qrCopy
                property bool copied: false
                text: copied ? "Copied" : "Copy"
                iconName: copied ? "check" : "copy"
                enabled: localQr.modules > 0
                ToolTip.visible: hovered; ToolTip.delay: 500; ToolTip.text: "Copy the code as a picture · Ctrl+V to paste"
                onClicked: if (localQr.copyImage(page.qrSize, page.qrFg, page.qrBg)) { copied = true; qrCopyReset.restart() }
                Timer { id: qrCopyReset; interval: 1400; onTriggered: qrCopy.copied = false }
            }
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
            color: localQr.modules > 0 ? page.qrBg : Theme.field
            border.color: Theme.line
            Behavior on color { ColorAnimation { duration: Theme.fade } }
            Image {
                id: qrPreview
                anchors.fill: parent
                anchors.margins: 6
                visible: localQr.modules > 0
                source: localQr.modules > 0 ? "image://qr/" + localQr.revision + "?fg=" + page.qrFg.slice(1) + "&bg=" + page.qrBg.slice(1) + "&size=496" : ""
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
            text: localQr.modules > 0 ? localQr.modules + " × " + localQr.modules + " modules · exports " + page.qrSize + " px" : "Preview"
            color: Theme.textFaint
            font.pixelSize: 11
        }
    }
}
