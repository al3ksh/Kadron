import QtQuick

// Grey checks behind images with transparency.
Canvas {
    id: board
    property int cell: 8
    property color light: Theme.dark ? "#3a4148" : "#ffffff"
    property color shade: Theme.dark ? "#2c3237" : "#e4e8e2"
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onLightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.fillStyle = light
        ctx.fillRect(0, 0, width, height)
        ctx.fillStyle = shade
        for (var y = 0; y < height; y += cell)
            for (var x = ((y / cell) % 2) * cell; x < width; x += cell * 2)
                ctx.fillRect(x, y, cell, cell)
    }
}
