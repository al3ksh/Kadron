import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Modal confirmation card. The window behind it is blurred by Main while any
// StudioDialog is open; buttons are declared as children and laid out right-aligned.
Dialog {
    id: dialog
    property string heading: ""
    property string message: ""
    property string iconName: "close"
    property bool warning: false
    default property alias actions: actionRow.data

    modal: true
    focus: true
    anchors.centerIn: parent
    width: 460
    padding: 0
    standardButtons: Dialog.NoButton
    closePolicy: Popup.CloseOnEscape

    Overlay.modal: Rectangle {
        color: Theme.scrim
        Behavior on opacity { NumberAnimation { duration: Theme.reveal } }
    }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.reveal; easing.type: Easing.OutCubic }
            SnapSpring { property: "scale"; from: 0.92; to: 1 }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.fadeFast; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale"; to: 0.97; duration: Theme.fadeFast; easing.type: Easing.InCubic }
        }
    }

    background: Rectangle {
        color: Theme.card
        radius: Theme.radiusLarge
        border.color: Theme.lineStrong
    }

    contentItem: ColumnLayout {
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 26
            Layout.bottomMargin: 22
            spacing: 16
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 40
                implicitHeight: 40
                radius: 12
                color: dialog.warning ? Theme.playheadWash : Theme.accentWash
                ToolIcon {
                    anchors.centerIn: parent
                    name: dialog.iconName
                    tint: dialog.warning ? Theme.warning : Theme.accent
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 7
                Text {
                    Layout.fillWidth: true
                    text: dialog.heading
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: dialog.message
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    lineHeight: 1.15
                    wrapMode: Text.WordWrap
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 1
            Layout.topMargin: 0
            implicitHeight: 64
            color: Theme.panel
            radius: Theme.radiusLarge - 1
            // Square off the top corners where the footer meets the body.
            Rectangle { width: parent.width; height: Theme.radiusLarge; color: parent.color }
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            RowLayout {
                id: actionRow
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 8
                layoutDirection: Qt.RightToLeft
            }
        }
    }
}
