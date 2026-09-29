import QtQuick
import QtQuick.Controls

// A row of choices in one track; the chosen one sits on an accent pill that
// slides between them. Each option is { label, value, glyph, tip }, the last
// two optional. A glyph draws a small picture before the label: "top",
// "middle" or "bottom" put a bar in a frame, "w:h" draws that shape.
Rectangle {
    id: control
    property var options: []
    property var current: undefined
    // Segments are named prefix + value, for tests and the tutorial.
    property string namePrefix: ""
    signal activated(var value)

    readonly property int currentIndex: {
        for (let i = 0; i < options.length; ++i) {
            const value = options[i].value
            if (typeof value === "number" && typeof current === "number" ? Math.abs(value - current) < 0.001 : value === current)
                return i
        }
        return -1
    }
    readonly property real segmentWidth: (width - 6) / Math.max(1, options.length)

    implicitHeight: 34
    radius: Theme.radius
    color: Theme.field
    border.width: 1
    border.color: Theme.line

    Rectangle {
        id: pill
        visible: control.currentIndex >= 0
        x: 3 + control.currentIndex * control.segmentWidth
        y: 3
        width: control.segmentWidth
        height: control.height - 6
        radius: Theme.radius - 2
        color: control.enabled ? Theme.accent : Theme.disabled
        Behavior on x { enabled: pill.visible; SmoothSpring {} }
        Behavior on color { ColorAnimation { duration: Theme.fade } }
    }

    Row {
        x: 3
        y: 3
        Repeater {
            model: control.options
            delegate: AbstractButton {
                id: segment
                required property var modelData
                required property int index
                readonly property bool chosen: index === control.currentIndex
                readonly property color ink: !control.enabled ? Theme.textDisabled
                                           : chosen ? Theme.accentInk
                                           : hovered ? Theme.text : Theme.textMuted
                readonly property string glyph: modelData.glyph || ""
                objectName: control.namePrefix ? control.namePrefix + modelData.value : ""
                width: control.segmentWidth
                height: control.height - 6
                padding: 0
                hoverEnabled: true
                enabled: control.enabled
                scale: down && enabled ? 0.95 : 1
                Behavior on scale { SnapSpring {} }

                background: Rectangle {
                    radius: Theme.radius - 2
                    color: Theme.hover
                    opacity: segment.hovered && !segment.chosen && control.enabled ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.fadeFast } }
                }
                contentItem: Item {
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        // Where the text lands in the picture.
                        Rectangle {
                            visible: segment.glyph === "top" || segment.glyph === "middle" || segment.glyph === "bottom"
                            anchors.verticalCenter: parent.verticalCenter
                            width: 15
                            height: 11
                            radius: 2
                            color: "transparent"
                            border.width: 1.3
                            border.color: segment.ink
                            Rectangle {
                                x: 3.5
                                width: 8
                                height: 2
                                radius: 1
                                color: segment.ink
                                y: segment.glyph === "top" ? 2.5 : segment.glyph === "bottom" ? parent.height - 4.5 : (parent.height - 2) / 2
                            }
                        }
                        // The shape itself, fitted in a small square.
                        Item {
                            readonly property var ratio: segment.glyph.indexOf(":") > 0 ? segment.glyph.split(":").map(Number) : null
                            visible: !!ratio
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            height: 14
                            Rectangle {
                                readonly property real aspect: parent.ratio ? parent.ratio[0] / parent.ratio[1] : 1
                                anchors.centerIn: parent
                                width: aspect >= 1 ? 14 : 14 * aspect
                                height: aspect >= 1 ? 14 / aspect : 14
                                radius: 2
                                color: "transparent"
                                border.width: 1.3
                                border.color: segment.ink
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: segment.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: segment.chosen ? Font.DemiBold : Font.Medium
                            color: segment.ink
                            Behavior on color { ColorAnimation { duration: Theme.fadeFast } }
                        }
                    }
                }
                onClicked: control.activated(modelData.value)
                ToolTip.visible: hovered && !!modelData.tip
                ToolTip.delay: 500
                ToolTip.text: modelData.tip || ""
            }
        }
    }
}
