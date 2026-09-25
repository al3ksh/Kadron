import QtQuick

Item {
    id: icon
    property string name: "edit"
    property color tint: "#aab2bb"
    implicitWidth: 20
    implicitHeight: 20

    Canvas {
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.save()
            ctx.scale(width / 20, height / 20)
            ctx.strokeStyle = icon.tint
            ctx.fillStyle = icon.tint
            ctx.lineWidth = 1.6
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.beginPath()
            if (icon.name === "edit") {
                ctx.rect(2.5, 4, 15, 12)
                ctx.moveTo(7, 4); ctx.lineTo(7, 16)
                ctx.moveTo(13, 4); ctx.lineTo(13, 16)
                ctx.moveTo(3, 9); ctx.lineTo(7, 9)
                ctx.moveTo(13, 11); ctx.lineTo(17, 11)
            } else if (icon.name === "download") {
                ctx.moveTo(10, 2); ctx.lineTo(10, 12)
                ctx.moveTo(6, 9); ctx.lineTo(10, 13); ctx.lineTo(14, 9)
                ctx.moveTo(3, 14); ctx.lineTo(3, 17); ctx.lineTo(17, 17); ctx.lineTo(17, 14)
            } else if (icon.name === "audio") {
                ctx.moveTo(4, 13); ctx.lineTo(4, 7)
                ctx.moveTo(7, 16); ctx.lineTo(7, 4)
                ctx.moveTo(10, 12); ctx.lineTo(10, 8)
                ctx.moveTo(13, 17); ctx.lineTo(13, 3)
                ctx.moveTo(16, 13); ctx.lineTo(16, 7)
            } else if (icon.name === "compress") {
                ctx.moveTo(3, 7); ctx.lineTo(7, 7); ctx.lineTo(7, 3)
                ctx.moveTo(17, 7); ctx.lineTo(13, 7); ctx.lineTo(13, 3)
                ctx.moveTo(3, 13); ctx.lineTo(7, 13); ctx.lineTo(7, 17)
                ctx.moveTo(17, 13); ctx.lineTo(13, 13); ctx.lineTo(13, 17)
            } else if (icon.name === "gif") {
                ctx.rect(2, 4, 16, 12)
                ctx.moveTo(8, 8); ctx.lineTo(12.5, 10); ctx.lineTo(8, 12); ctx.closePath()
            } else if (icon.name === "pdf") {
                ctx.moveTo(5, 2); ctx.lineTo(12, 2); ctx.lineTo(16, 6); ctx.lineTo(16, 18); ctx.lineTo(5, 18); ctx.closePath()
                ctx.moveTo(12, 2); ctx.lineTo(12, 6); ctx.lineTo(16, 6)
                ctx.moveTo(7.5, 11); ctx.lineTo(13.5, 11)
                ctx.moveTo(7.5, 14); ctx.lineTo(12, 14)
            } else if (icon.name === "qr") {
                ctx.rect(2, 2, 6, 6); ctx.rect(12, 2, 6, 6)
                ctx.rect(2, 12, 6, 6); ctx.rect(12, 12, 2, 2)
                ctx.moveTo(18, 12); ctx.lineTo(18, 18); ctx.lineTo(13, 18)
            } else if (icon.name === "publish") {
                ctx.moveTo(10, 14); ctx.lineTo(10, 3)
                ctx.moveTo(6, 7); ctx.lineTo(10, 3); ctx.lineTo(14, 7)
                ctx.moveTo(3, 13); ctx.lineTo(3, 17); ctx.lineTo(17, 17); ctx.lineTo(17, 13)
            }
            ctx.stroke()
            if (icon.name === "gif") {
                ctx.beginPath(); ctx.moveTo(8, 8); ctx.lineTo(12.5, 10); ctx.lineTo(8, 12); ctx.closePath(); ctx.fill()
            }
            ctx.restore()
        }
    }
    onNameChanged: children[0].requestPaint()
    onTintChanged: children[0].requestPaint()
}
