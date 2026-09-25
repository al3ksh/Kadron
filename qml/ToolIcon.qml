import QtQuick
import QtQuick.Shapes

// Stroked vector icons drawn on a 20 × 20 grid and scaled to the item size.
Item {
    id: icon
    property string name: "edit"
    property color tint: Theme.textMuted
    property real strokeWidth: 1.6
    implicitWidth: 20
    implicitHeight: 20

    readonly property var strokes: ({
        "edit": "M2.5 4h15v12h-15z M7 4v12 M13 4v12 M3 9h4 M13 11h4",
        "download": "M10 2v10 M6 9l4 4l4-4 M3 14v3h14v-3",
        "audio": "M4 13V7 M7 16V4 M10 12V8 M13 17V3 M16 13V7",
        "compress": "M3 7h4V3 M17 7h-4V3 M3 13h4v4 M17 13h-4v4",
        "gif": "M2 4h16v12H2z",
        "pdf": "M5 2h7l4 4v12H5z M12 2v4h4 M7.5 11h6 M7.5 14H12",
        "qr": "M2 2h6v6H2z M12 2h6v6h-6z M2 12h6v6H2z M12 12h2v2h-2z M18 12v6h-5",
        "publish": "M10 14V3 M6 7l4-4l4 4 M3 13v4h14v-4",
        "play": "",
        "pause": "M7 4v12 M13 4v12",
        "plus": "M10 4v12 M4 10h12",
        "close": "M5 5l10 10 M15 5L5 15",
        "split": "M10 2v16 M5 6l-3 4l3 4 M15 6l3 4l-3 4",
        "trash": "M3.5 5.5h13 M8 5.5V3.5h4v2 M5 5.5l1 11h8l1-11 M8.5 8.5v5 M11.5 8.5v5",
        "save": "M4 3h9.5L17 6.5V17H4z M7 3v4h6V3 M7 17v-5h7v5",
        "folder": "M2.5 5.5v10h15v-8h-7.5l-2-2z",
        "drop": "M10 3v9 M6.5 8.5L10 12l3.5-3.5 M3 12.5v2.5a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-2.5",
        "link": "M8.5 11.5l3-3 M7 9L5 11a2.8 2.8 0 0 0 4 4l2-2 M13 11l2-2a2.8 2.8 0 0 0-4-4L9 7",
        "loop": "M4 9V8a3 3 0 0 1 3-3h9 M13.5 2.5L16 5l-2.5 2.5 M16 11v1a3 3 0 0 1-3 3H4 M6.5 17.5L4 15l2.5-2.5",
        "file": "M5 2h7l4 4v12H5z M12 2v4h4",
        "chevron": "M5.5 8l4.5 4.5l4.5-4.5",
        "rotateLeft": "M4.5 4.5v4h4 M4.8 8.2A6.5 6.5 0 1 1 5 13",
        "rotateRight": "M15.5 4.5v4h-4 M15.2 8.2A6.5 6.5 0 1 0 15 13",
        "undo": "M7.5 4L4 7.5L7.5 11 M4 7.5h8a4.5 4.5 0 0 1 0 9H9",
        "redo": "M12.5 4L16 7.5L12.5 11 M16 7.5H8a4.5 4.5 0 0 0 0 9h3"
    })
    readonly property var fills: ({
        "gif": "M8 8l4.5 2L8 12z",
        "play": "M6 3.5l10 6.5l-10 6.5z"
    })

    Shape {
        width: 20
        height: 20
        scale: Math.min(icon.width, icon.height) / 20
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: icon.tint
            strokeWidth: icon.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.strokes[icon.name] || "" }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: icon.tint
            PathSvg { path: icon.fills[icon.name] || "" }
        }
    }
}
