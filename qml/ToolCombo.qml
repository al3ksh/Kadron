import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    implicitHeight: 39
    font.family: Theme.fontFamily
    font.pixelSize: 12

    contentItem: Text {
        leftPadding: 12
        rightPadding: 30
        text: control.displayText
        font: control.font
        color: Theme.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: ToolIcon {
        name: "chevron"
        tint: Theme.textMuted
        width: 16
        height: 16
        x: control.width - width - 12
        y: (control.height - height) / 2
        rotation: control.popup.visible ? 180 : 0
        Behavior on rotation { SnapSpring { epsilon: 0.2 } }
    }
    background: Rectangle {
        radius: 8
        color: control.down ? Theme.hover : Theme.field
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Theme.accent : Theme.lineStrong
        Behavior on border.color { ColorAnimation { duration: Theme.fade } }
    }
    delegate: ItemDelegate {
        width: control.width
        height: 34
        text: control.textAt(index)
        font: control.font
        highlighted: control.highlightedIndex === index
        contentItem: Text {
            text: parent.text
            color: Theme.text
            font: control.font
            verticalAlignment: Text.AlignVCenter
            leftPadding: 12
        }
        background: Rectangle { color: parent.highlighted ? Theme.accentWash : Theme.card }
    }
    popup: Popup {
        y: control.height - 1
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight, 320)
        padding: 1
        enter: Transition { ParallelAnimation { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.fadeFast } SmoothSpring { property: "y"; from: control.height - 8; to: control.height - 1 } } }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.fadeFast } }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: Rectangle { radius: 8; color: Theme.card; border.color: Theme.lineStrong }
    }
}
