import QtQuick
import QtQuick.Layouts

// Folds its content open and shut: the height eases so the page below glides
// instead of jumping, while the content fades and settles a few pixels down.
Item {
    id: fold
    property bool open: true
    property alias spacing: body.spacing
    default property alias content: body.data

    property real reveal: open ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    // The fold stays in the layout and folds its share of the parent's spacing
    // away with it, so nothing snaps when it finishes closing or starts opening.
    readonly property real parentSpacing: parent && parent.spacing !== undefined ? parent.spacing : 0
    Layout.fillWidth: true
    Layout.topMargin: -parentSpacing * (1 - reveal)
    implicitWidth: body.implicitWidth
    implicitHeight: body.implicitHeight * reveal
    clip: reveal < 1

    ColumnLayout {
        id: body
        width: parent.width
        spacing: 0
        visible: fold.reveal > 0
        y: -6 * (1 - fold.reveal)
        // The content trails the height a little, so it never shows cut off at full strength.
        opacity: fold.reveal * fold.reveal
    }
}
