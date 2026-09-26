import QtQuick
import QtQuick.Layouts

// Sidebar footer for app updates: the running version (click to check), and a
// card once a newer release exists that downloads it and restarts into it.
ColumnLayout {
    id: card
    // AppUpdater (or a stand-in with the same properties).
    property QtObject updater: null
    signal restartRequested()
    spacing: 8

    readonly property bool offering: !!updater && updater.updateAvailable
    // A manual check's answer stays visible briefly, then fades.
    property bool showStatus: false
    readonly property string status: updater && !updater.checking ? updater.statusText : ""
    onStatusChanged: {
        showStatus = status.length > 0
        if (showStatus) statusTimer.restart()
    }
    Timer { id: statusTimer; interval: 4000; onTriggered: card.showStatus = false }

    Rectangle {
        id: offer
        Layout.fillWidth: true
        Layout.preferredHeight: card.offering ? offerColumn.implicitHeight + 24 : 0
        visible: Layout.preferredHeight > 0.5
        opacity: card.offering ? 1 : 0
        clip: true
        radius: Theme.radius
        color: Theme.accentWash
        border.color: Theme.accentEdge
        Behavior on Layout.preferredHeight { SmoothSpring {} }
        Behavior on opacity { NumberAnimation { duration: Theme.fade } }

        ColumnLayout {
            id: offerColumn
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "UPDATE"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                    Layout.fillWidth: true
                }
                Text {
                    id: notesLink
                    text: "What's new"
                    color: notesMouse.containsMouse ? Theme.text : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.underline: notesMouse.containsMouse
                    MouseArea {
                        id: notesMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally(card.updater.releaseUrl)
                    }
                }
            }
            Text {
                text: card.updater ? "Kadron " + card.updater.latestVersion : ""
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: !card.updater ? ""
                      : card.updater.ready ? "Downloaded and verified."
                      : card.updater.downloading ? "Downloading… " + Math.round(card.updater.progress * 100) + "%"
                      : card.updater.canInstall ? "You have " + card.updater.currentVersion + "."
                      : "Portable copy: get the new zip."
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
            StudioProgress {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: !!card.updater && card.updater.downloading
                value: card.updater ? card.updater.progress : 0
            }
            EditorButton {
                objectName: "updateButton"
                Layout.fillWidth: true
                Layout.topMargin: 6
                implicitHeight: 32
                visible: !!card.updater && !card.updater.downloading
                primary: true
                iconName: card.updater && card.updater.ready ? "rotateRight" : card.updater && card.updater.canInstall ? "download" : "link"
                text: card.updater && card.updater.ready ? "Restart to update"
                      : card.updater && card.updater.canInstall ? "Update" : "Open release"
                onClicked: {
                    if (card.updater.ready) {
                        card.updater.restartToUpdate()
                        card.restartRequested()
                    } else if (card.updater.canInstall) {
                        card.updater.install()
                    } else {
                        Qt.openUrlExternally(card.updater.releaseUrl)
                    }
                }
            }
        }
    }

    // Manual check result, e.g. "Kadron 0.1.0 is up to date".
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 9
        visible: opacity > 0
        opacity: card.showStatus && !card.offering ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fade } }
        text: card.updater ? card.updater.statusText : ""
        color: Theme.textFaint
        font.family: Theme.fontFamily
        font.pixelSize: 10
        wrapMode: Text.WordWrap
    }
}
