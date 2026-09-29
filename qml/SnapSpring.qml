import QtQuick

// Quick settle for press feedback, dialog entry and small nudges. It eases out
// without overshooting, so a click reads as a tap rather than a wobble.
NumberAnimation {
    // Kept so callers written for the old spring still load.
    property real epsilon: 0
    duration: 140
    easing.type: Easing.OutCubic
}
