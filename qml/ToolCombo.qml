import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    implicitHeight: 39
    font.family: "Segoe UI"
    font.pixelSize: 12

    contentItem: Text {
        leftPadding: 12
        rightPadding: 30
        text: control.displayText
        font: control.font
        color: "#f1f4ef"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        text: "\u2304"
        font.pixelSize: 18
        color: "#b9c2c8"
        x: control.width - width - 13
        y: (control.height - height) / 2 - 3
    }
    background: Rectangle {
        radius: 8
        color: control.down ? "#30383e" : "#20262b"
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? "#c9f27a" : "#404950"
        Behavior on border.color { ColorAnimation { duration: 140 } }
    }
    delegate: ItemDelegate {
        width: control.width
        height: 34
        text: control.textAt(index)
        font: control.font
        highlighted: control.highlightedIndex === index
        contentItem: Text {
            text: parent.text
            color: "#f1f4ef"
            font: control.font
            verticalAlignment: Text.AlignVCenter
            leftPadding: 12
        }
        background: Rectangle { color: parent.highlighted ? "#354033" : "#242a30" }
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
        background: Rectangle { radius: 8; color: "#242a30"; border.color: "#505961" }
    }
}
