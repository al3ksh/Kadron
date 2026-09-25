import QtQuick

// Workspace entrance: a short fade while the content settles upward on a spring.
ParallelAnimation {
    id: reveal
    property Item target
    property Translate shift
    property real distance: 12

    NumberAnimation { target: reveal.target; property: "opacity"; from: 0.55; to: 1; duration: Theme.reveal; easing.type: Easing.OutCubic }
    SmoothSpring { target: reveal.shift; property: "y"; from: reveal.distance; to: 0 }
}
