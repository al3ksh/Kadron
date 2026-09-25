import QtQuick

// Placeholder in the shape of content that is still loading. It breathes only
// while visible, so nothing animates once the real content is in.
Rectangle {
    id: block
    color: Theme.hover
    radius: Theme.radiusSmall

    SequentialAnimation on opacity {
        running: block.visible
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 0.45; duration: 750; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.45; to: 1; duration: 750; easing.type: Easing.InOutSine }
    }
}
