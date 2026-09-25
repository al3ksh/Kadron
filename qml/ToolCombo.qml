import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    implicitHeight: 38
    font.family: "Segoe UI"
    font.pixelSize: 12

    contentItem: Text {
        leftPadding: 12
        rightPadding: 30
        text: control.displayText
        font: control.font
        color: "#e9eeee"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        text: "\u2304"
        font.pixelSize: 18
        color: "#b7c6c5"
        x: control.width - width - 13
        y: (control.height - height) / 2 - 3
    }
    background: Rectangle {
        radius: 4
        color: control.down ? "#2e393a" : "#222829"
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? "#8bc9cb" : "#41494b"
    }
    delegate: ItemDelegate {
        width: control.width
        height: 34
        text: control.textAt(index)
        font: control.font
        highlighted: control.highlightedIndex === index
        contentItem: Text {
            text: parent.text
            color: "#e9eeee"
            font: control.font
            verticalAlignment: Text.AlignVCenter
            leftPadding: 12
        }
        background: Rectangle { color: parent.highlighted ? "#365154" : "#242a2b" }
    }
    popup: Popup {
        y: control.height - 1
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight, 320)
        padding: 1
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: Rectangle { radius: 4; color: "#242a2b"; border.color: "#586366" }
    }
}
