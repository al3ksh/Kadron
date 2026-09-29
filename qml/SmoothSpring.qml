import QtQuick

// Settling ease for indicators, panels and anything that travels a distance.
// It slows into place without overshooting.
NumberAnimation {
    // Kept so callers written for the old spring still load.
    property real epsilon: 0
    duration: 260
    easing.type: Easing.OutQuint
}
