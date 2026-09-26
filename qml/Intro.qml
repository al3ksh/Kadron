import QtQuick

// Startup intro, shown while the main window loads (see main.cpp). The whole
// animation is one shader (shaders/intro.frag) whose clock is advanced by
// UniformAnimators on the render thread, so it keeps playing while the UI
// thread is busy. It plays to the lockup, holds there until the app is ready,
// then fades to the window colour and hands off. A click or key skips ahead.
Window {
    id: intro
    objectName: "introWindow"
    flags: Qt.SplashScreen | Qt.FramelessWindowHint
    color: Theme.window
    title: "Kadron"
    width: 1440
    height: 900

    // Set from C++ once the main window exists.
    property bool appReady: false
    property bool played: false
    property bool skipped: false
    property bool leaving: false
    // Screenshot runs hold a single moment of the intro instead of playing it.
    property real frozenAt: -1
    signal finished()

    readonly property real stageScale: Math.min(width / 1920, height / 1080)
    readonly property real lockupAt: 2.74

    onAppReadyChanged: leaveIfDone()
    function leaveIfDone() {
        if (leaving || !appReady || !(played || skipped)) return
        leaving = true
        exitAnimator.start()
    }
    function skip() {
        if (skipped || leaving) return
        skipped = true
        leaveIfDone()
    }

    // Sources for the shader's text: the wordmark and a digit atlas, drawn
    // at twice the stage scale for crisp sampling.
    Text {
        id: wordText
        text: "Kadron"
        color: "white"
        font.family: Theme.fontFamily
        font.weight: Font.DemiBold
        font.pixelSize: Math.round(176 * intro.stageScale * 2)
        font.letterSpacing: -3 * intro.stageScale * 2
    }
    ShaderEffectSource { id: wordSource; sourceItem: wordText; hideSource: true; smooth: true }

    TextMetrics {
        id: digitMetrics
        text: "0"
        font.family: Theme.fontFamily
        font.weight: Font.DemiBold
        font.pixelSize: Math.round(20 * intro.stageScale * 2)
    }
    readonly property real cellWidth: Math.ceil(digitMetrics.advanceWidth / 0.78)
    readonly property real cellHeight: Math.ceil(digitMetrics.height)
    Row {
        id: digitAtlas
        Repeater {
            model: 12
            Item {
                required property int index
                width: intro.cellWidth
                height: intro.cellHeight
                Text {
                    anchors.centerIn: parent
                    text: "0123456789:."[parent.index]
                    color: "white"
                    font: digitMetrics.font
                }
            }
        }
    }
    ShaderEffectSource { id: digitSource; sourceItem: digitAtlas; hideSource: true; smooth: true }

    ShaderEffect {
        id: stage
        objectName: "introStage"
        anchors.fill: parent
        property real t: Math.max(0, intro.frozenAt)
        property real exitAmount: 0
        readonly property real stageScale: intro.stageScale
        readonly property size itemSize: Qt.size(width, height)
        readonly property size wordSize: Qt.size(wordText.implicitWidth / (2 * stageScale), wordText.implicitHeight / (2 * stageScale))
        readonly property real wordBaseline: wordText.baselineOffset / (2 * stageScale)
        readonly property real glyphAdvance: intro.cellWidth / (2 * stageScale)
        readonly property real glyphHeight: intro.cellHeight / (2 * stageScale)
        readonly property color bg: Theme.window
        readonly property color lane: Theme.rail
        readonly property color laneEdge: Theme.tint(Theme.rail, Theme.line, 0.5)
        readonly property color ink: Theme.text
        readonly property color inkPlayed: Theme.textFaint
        readonly property color muted: Theme.textDisabled
        readonly property color accent: Theme.accent
        readonly property color accentInk: Theme.accentInk
        readonly property color playhead: Theme.playhead
        readonly property color playheadInk: Theme.playheadInk
        readonly property color playheadWash: Theme.playheadWash
        readonly property var wordTex: wordSource
        readonly property var digitTex: digitSource
        fragmentShader: "qrc:/shaders/intro.frag.qsb"

        UniformAnimator {
            id: playAnimator
            target: stage
            uniform: "t"
            from: 0
            to: intro.lockupAt
            duration: intro.lockupAt * 1000
            running: intro.visible && intro.frozenAt < 0
            onFinished: { intro.played = true; intro.leaveIfDone() }
        }
        UniformAnimator {
            id: exitAnimator
            target: stage
            uniform: "exitAmount"
            from: 0
            to: 1
            duration: 340
            onFinished: intro.finished()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: intro.skip()
    }
    Item {
        focus: true
        Keys.onPressed: function(event) { intro.skip(); event.accepted = true }
    }
}
