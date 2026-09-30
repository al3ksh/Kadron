import QtQuick

// Keeps the rebound at the ends of a scroll, only smaller: Qt overshoots as usual
// and the view is pulled back by most of it, leaving a short nudge.
QtObject {
    id: soft
    property Flickable flickable
    property real strength: 0.3

    readonly property Translate shift: Translate {
        y: soft.flickable ? soft.flickable.verticalOvershoot * (1 - soft.strength) : 0
    }

    onFlickableChanged: if (flickable) {
        // On the content, not the view: the view carries the clip, which has to stay put.
        flickable.contentItem.transform = [shift]
    }
}
