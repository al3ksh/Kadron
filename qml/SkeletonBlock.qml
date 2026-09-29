import QtQuick

// Placeholder in the shape of content that is still loading: one soft light
// sweeps across it. It runs only while visible, so nothing animates once the
// real content is in.
Rectangle {
    id: block
    radius: Theme.radiusSmall
    property real sweep: -0.3
    readonly property color base: Theme.hover
    readonly property color shine: Qt.lighter(Theme.hover, Theme.dark ? 1.3 : 1.06)
    function at(position) { return Math.max(0, Math.min(1, position)) }

    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: block.base }
        GradientStop { position: block.at(block.sweep - 0.3); color: block.base }
        GradientStop { position: block.at(block.sweep); color: block.shine }
        GradientStop { position: block.at(block.sweep + 0.3); color: block.base }
        GradientStop { position: 1; color: block.base }
    }

    NumberAnimation on sweep {
        running: block.visible
        loops: Animation.Infinite
        from: -0.3
        to: 1.3
        duration: 1600
        easing.type: Easing.InOutSine
    }
}
