import QtQuick
import QtQuick.Shapes

// First step of a file-based tool: a large target for dropping files, with a
// browse fallback. The page owns the DropArea; `active` mirrors its hover state.
Item {
    id: zone
    property string heading: "Drop a file here"
    property string formats: ""
    property string iconName: "drop"
    property bool active: false
    signal browseRequested()

    implicitHeight: 260
    activeFocusOnTab: true
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            zone.browseRequested()
            event.accepted = true
        }
    }

    Rectangle {
        id: fill
        anchors.fill: parent
        radius: 14
        color: zone.active ? Theme.accentWash : pointer.containsMouse ? Theme.card : Theme.field
        scale: zone.active ? 1.015 : 1
        Behavior on color { ColorAnimation { duration: Theme.fade } }
        Behavior on scale { SnapSpring {} }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: zone.active || zone.activeFocus ? Theme.accent : Theme.lineStrong
                strokeWidth: 1.5
                strokeStyle: ShapePath.DashLine
                dashPattern: [5, 4]
                PathRectangle {
                    x: 1; y: 1
                    width: fill.width - 2
                    height: fill.height - 2
                    radius: 13
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 12
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56
                height: 56
                radius: 18
                color: zone.active ? Theme.accent : Theme.accentWash
                Behavior on color { ColorAnimation { duration: Theme.fade } }
                ToolIcon {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    name: zone.iconName
                    tint: zone.active ? Theme.accentInk : Theme.accent
                    y: zone.active ? 3 : 0
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: zone.active ? "Release to open" : zone.heading
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "or click to browse"
                color: Theme.accentSoft
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: zone.formats.length > 0
                text: zone.formats
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { zone.forceActiveFocus(); zone.browseRequested() }
    }
}
