pragma Singleton
import QtQuick

// Shared palette, type, shape and motion tokens. Components reference these
// instead of literal values so the whole app moves and reads as one surface.
// Colors follow Prefs: dark or light surfaces, and one accent from which
// every accent shade is derived.
QtObject {
    id: theme

    readonly property bool dark: Prefs.themeMode === "system"
                                 ? Qt.styleHints.colorScheme !== Qt.ColorScheme.Light
                                 : Prefs.themeMode !== "light"

    // Palette presets offered in the appearance picker.
    readonly property var accentPresets: ["#c9f27a", "#7cc4ff", "#b89cff", "#ff9d7a", "#ffd166", "#5ee0b5", "#ff7ab6"]

    function luminance(c) {
        function lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }
    // `amount` of `over` laid on `base`.
    function tint(base, over, amount) {
        var b = Qt.color(base), o = Qt.color(over)
        return Qt.rgba(b.r + (o.r - b.r) * amount, b.g + (o.g - b.g) * amount, b.b + (o.b - b.b) * amount, 1)
    }
    function pick(darkValue, lightValue) { return dark ? darkValue : lightValue }

    // Surfaces, darkest to lightest (dark) / lightest to darkest (light).
    readonly property color canvas: pick("#0b0d10", "#1d2227")       // source monitor, previews
    readonly property color window: pick("#101317", "#eef1ec")
    readonly property color rail: pick("#171b20", "#f8faf6")         // nav rail and Windows caption
    readonly property color statusBar: pick("#1a1f24", "#f3f5f1")
    readonly property color panel: pick("#1d2227", "#ffffff")
    readonly property color field: pick("#20262b", "#f5f7f3")
    readonly property color card: pick("#252b30", "#f0f3ee")
    readonly property color control: pick("#292f35", "#ffffff")
    readonly property color hover: pick("#2e363c", "#e8ece6")
    readonly property color pressed: pick("#353d43", "#dfe4dc")
    readonly property color disabled: pick("#23282c", "#eceeea")

    // Lines.
    readonly property color line: pick("#343d44", "#dde3dc")
    readonly property color lineStrong: pick("#434d54", "#c5cdc4")
    readonly property color scrollThumb: pick("#58636a", "#b3bcb7")

    // Text.
    readonly property color text: pick("#f1f4ef", "#1c2320")
    readonly property color textSoft: pick("#dfe5e2", "#2c3531")
    readonly property color textMuted: pick("#b5bfc5", "#56615c")
    readonly property color textFaint: pick("#8a969c", "#7c8782")
    readonly property color textDisabled: pick("#6f777f", "#a3aca7")

    // Accent and its companions. On light surfaces a pale accent is deepened
    // so it still reads as text and as a fill.
    readonly property color accentBase: Qt.color(Prefs.accent).valid ? Qt.color(Prefs.accent) : Qt.color("#c9f27a")
    readonly property color accent: dark || luminance(accentBase) < 0.4 ? accentBase : tint(accentBase, "#000000", 0.38)
    readonly property color accentHover: dark ? tint(accent, "#ffffff", 0.25) : tint(accent, "#000000", 0.1)
    readonly property color accentPressed: tint(accent, "#000000", 0.15)
    readonly property color accentSoft: dark ? tint(accent, "#ffffff", 0.2) : tint(accent, "#000000", 0.1)
    readonly property color accentInk: luminance(accent) > 0.35 ? tint(accent, "#000000", 0.85) : "#ffffff"     // text on accent
    readonly property color accentWash: tint(panel, accent, dark ? 0.12 : 0.16)      // selected surface
    readonly property color accentEdge: tint(panel, accent, dark ? 0.52 : 0.7)       // selected border
    readonly property color accentFocus: dark ? tint(accent, "#ffffff", 0.5) : tint(accent, "#000000", 0.2)
    readonly property color selectionFill: "#5d768941"

    // Playhead (amber) and status.
    readonly property color playhead: pick("#eebd86", "#c77d2e")
    readonly property color playheadInk: pick("#ffe3bd", "#5a3510")
    readonly property color playheadWash: pick("#4b392c", "#f6e3cf")
    readonly property color playheadHover: pick("#66472f", "#f0d3b4")
    readonly property color playheadPressed: pick("#795436", "#e8c29a")
    readonly property color waveActive: tint(panel, accent, dark ? 0.08 : 0.12)   // waveform lane of the selected clip
    readonly property color waveInk: pick("#ffffff", "#2c3531")                    // waveform strokes
    readonly property color chipScrim: "#cc111417"  // labels over footage
    readonly property color danger: pick("#e7aaa4", "#b9483e")
    readonly property color dangerStrong: pick("#e8928c", "#a33b31")
    readonly property color warning: pick("#e2bb8e", "#a66a1f")
    readonly property color success: pick("#a7d4b4", "#3f8f5a")
    readonly property color scrim: pick("#99070809", "#8cdfe4dc")

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
