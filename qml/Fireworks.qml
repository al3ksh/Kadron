import QtQuick

// A few bursts of sparks over the area it covers, for good news: play()
// sets them off one after another. It takes no clicks.
Item {
    id: fireworks
    property int bursts: 3
    property var colors: [Theme.accent, "#ffd166", "#ff7aa2", "#7ad7ff", "#ffffff"]

    function play() {
        shells.model = 0
        shells.model = bursts
    }

    Repeater {
        id: shells
        model: 0
        delegate: Item {
            id: shell
            required property int index
            // Where it bursts, how far the sparks fly and their colour, picked once.
            readonly property real cx: fireworks.width * (0.2 + Math.random() * 0.6)
            readonly property real cy: fireworks.height * (0.25 + Math.random() * 0.35)
            readonly property real reach: Math.min(fireworks.width, fireworks.height) * (0.3 + Math.random() * 0.25) + 14
            readonly property color tint: fireworks.colors[Math.floor(Math.random() * fireworks.colors.length)]
            property real t: 0

            NumberAnimation {
                id: flight
                target: shell
                property: "t"
                from: 0
                to: 1
                duration: 1100
                easing.type: Easing.OutCubic
            }
            Timer { interval: 40 + shell.index * 280; running: true; onTriggered: flight.start() }

            Repeater {
                model: 16
                Rectangle {
                    required property int index
                    readonly property real angle: index / 16 * 2 * Math.PI + (Math.random() - 0.5) * 0.35
                    readonly property real speed: 0.65 + Math.random() * 0.35
                    readonly property real size: shell.t < 0.5 ? 3 : 3 - (shell.t - 0.5) * 3
                    width: size
                    height: size
                    radius: size / 2
                    color: shell.tint
                    x: shell.cx + Math.cos(angle) * shell.reach * speed * shell.t - size / 2
                    // A little gravity pulls the sparks down as they fade.
                    y: shell.cy + Math.sin(angle) * shell.reach * speed * shell.t + shell.t * shell.t * 14 - size / 2
                    opacity: shell.t <= 0 || shell.t >= 1 ? 0 : 1 - shell.t * shell.t
                }
            }
        }
    }
}
