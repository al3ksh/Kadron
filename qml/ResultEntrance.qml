import QtQuick

// A freshly finished file comes in with a short fade and a small grow instead
// of popping up. Plays when `file` changes to a new result.
ParallelAnimation {
    id: entrance
    property Item target
    property url file
    onFileChanged: if (file.toString().length > 0 && target) restart()

    NumberAnimation { target: entrance.target; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
    NumberAnimation { target: entrance.target; property: "scale"; from: 0.96; to: 1; duration: 280; easing.type: Easing.OutQuint }
}
