import QtQuick

Item {
    id: mark
    implicitWidth: 34
    implicitHeight: 34

    Canvas {
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var scale = Math.min(width, height) / 34
            ctx.save()
            ctx.scale(scale, scale)
            ctx.lineWidth = 3.6
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.strokeStyle = "#c9f27a"
            ctx.beginPath()
            ctx.moveTo(5, 5)
            ctx.lineTo(5, 29)
            ctx.moveTo(13, 17)
            ctx.lineTo(27, 5)
            ctx.moveTo(13, 17)
            ctx.lineTo(27, 29)
            ctx.stroke()
            ctx.fillStyle = "#f6f7f2"
            ctx.beginPath()
            ctx.arc(12, 17, 2.7, 0, Math.PI * 2)
            ctx.fill()
            ctx.restore()
        }
    }
}
