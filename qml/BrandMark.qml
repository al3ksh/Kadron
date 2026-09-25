import QtQuick
import QtQuick.Shapes

// The Kadron mark: a frame bracket (kadr) cut by a chevron, reading as a K.
// Drawn on a 64-unit grid; assets/kadron-mark.svg is the same mark on an app tile.
Item {
    id: mark
    implicitWidth: 34
    implicitHeight: 34

    Shape {
        width: 64
        height: 64
        scale: Math.min(mark.width, mark.height) / 64
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Theme.text
            strokeWidth: 6.5
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M42.5 8.5H12.5V55.5H42.5" }
        }
        ShapePath {
            strokeColor: Theme.accent
            strokeWidth: 6.5
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M52.5 11L30 32L52.5 53" }
        }
    }
}
