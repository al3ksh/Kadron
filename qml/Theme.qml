pragma Singleton
import QtQuick

// Shared palette, type, shape and motion tokens. Components reference these
// instead of literal values so the whole app moves and reads as one surface.
QtObject {
    // Surfaces, darkest to lightest.
    readonly property color canvas: "#0b0d10"       // source monitor, previews
    readonly property color window: "#101317"
    readonly property color rail: "#171b20"         // nav rail and Windows caption
    readonly property color statusBar: "#1a1f24"
    readonly property color panel: "#1d2227"
    readonly property color field: "#20262b"
    readonly property color card: "#252b30"
    readonly property color control: "#292f35"
    readonly property color hover: "#2e363c"
    readonly property color pressed: "#353d43"
    readonly property color disabled: "#23282c"

    // Lines.
    readonly property color line: "#343d44"
    readonly property color lineStrong: "#434d54"
    readonly property color scrollThumb: "#58636a"

    // Text.
    readonly property color text: "#f1f4ef"
    readonly property color textSoft: "#dfe5e2"
    readonly property color textMuted: "#b5bfc5"
    readonly property color textFaint: "#8a969c"
    readonly property color textDisabled: "#6f777f"

    // Accent (lime) and its companions.
    readonly property color accent: "#c9f27a"
    readonly property color accentHover: "#daf99a"
    readonly property color accentPressed: "#a8d84f"
    readonly property color accentSoft: "#d2f59b"
    readonly property color accentInk: "#17200e"     // text on accent
    readonly property color accentWash: "#303b30"    // selected surface
    readonly property color accentEdge: "#718d58"    // selected border
    readonly property color accentFocus: "#e5ffb3"
    readonly property color selectionFill: "#5d768941"

    // Playhead (amber) and status.
    readonly property color playhead: "#eebd86"
    readonly property color playheadInk: "#ffe3bd"
    readonly property color playheadWash: "#4b392c"
    readonly property color playheadHover: "#66472f"
    readonly property color playheadPressed: "#795436"
    readonly property color waveActive: "#232d22"   // waveform lane of the selected clip
    readonly property color chipScrim: "#cc111417"  // labels over footage
    readonly property color danger: "#e7aaa4"
    readonly property color dangerStrong: "#e8928c"
    readonly property color warning: "#e2bb8e"
    readonly property color success: "#a7d4b4"
    readonly property color scrim: "#99070809"

    // Shape and type.
    readonly property int radiusSmall: 6
    readonly property int radius: 8
    readonly property int radiusLarge: 16
    readonly property string fontFamily: "Segoe UI"

    // Motion. Springs are used for anything that moves or scales so interrupted
    // gestures keep their velocity; colors cross-fade over a short duration.
    readonly property real springSnappy: 7.0        // press feedback, small nudges
    readonly property real springSmooth: 4.2        // indicators, panels, playhead follow
    readonly property real dampingSnappy: 0.42
    readonly property real dampingSmooth: 0.36
    readonly property real springMass: 1.0
    readonly property real springEpsilon: 0.01
    readonly property int fadeFast: 120
    readonly property int fade: 150
    readonly property int reveal: 180
}
