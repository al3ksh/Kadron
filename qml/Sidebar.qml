import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kadron.Backend

// The left rail: the brand, one item per workspace with a shared highlight,
// the update card, Settings and the running version.
Rectangle {
    id: sidebar
    required property var app
    // Settings is open, so its button stays lit.
    property bool settingsOpen: false
    signal openSettings()

    // The card's own step (download, then restart), for Settings to start.
    function installUpdate() { updateCard.act() }

    color: Theme.rail
    // One shared highlight travels between rail items on a spring.
    Item {
        id: navHighlight
        readonly property Item target: [navEditor, navDownload, navAudio, navCompress, navGif, navPdf, navQr, navClips, navDrop, navShortener, navImages, navReframe][sidebar.app.workspace] || null
        visible: target !== null
        x: navColumn.x + (target ? target.x : 0)
        y: navColumn.y + (target ? target.y : 0)
        width: target ? target.width : 0
        height: target ? target.height : 0
        Behavior on y { SmoothSpring {} }
        Rectangle { anchors.fill: parent; radius: 9; color: Theme.accentWash }
        Rectangle { width: 3; height: 18; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
    }
    ColumnLayout {
        id: navColumn
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 15
        anchors.bottomMargin: 16
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.preferredHeight: 48
            spacing: 8
            BrandMark { Layout.preferredWidth: 34; Layout.preferredHeight: 34 }
            Column {
                spacing: 0
                Text { text: "KADRON"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 16; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                Text { text: "MEDIA STUDIO"; color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 8; font.weight: Font.DemiBold; font.letterSpacing: 1.5 }
            }
        }
        Item { Layout.preferredHeight: sidebar.app.height < 820 ? 10 : 23 }
        Text { text: "WORKSPACE"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2; Layout.leftMargin: 13; Layout.bottomMargin: 7 }
        NavItem { id: navEditor; Layout.fillWidth: true; title: "Editor"; iconName: "edit"; active: sidebar.app.workspace === 0 && sidebar.app.inspectorMode === 0; onClicked: { sidebar.app.workspace = 0; sidebar.app.inspectorMode = 0 } }
        NavItem { id: navDownload; Layout.fillWidth: true; title: "Download"; iconName: "download"; active: sidebar.app.workspace === 1; onClicked: sidebar.app.workspace = 1 }
        NavItem { id: navAudio; Layout.fillWidth: true; title: "Audio"; iconName: "audio"; active: sidebar.app.workspace === 2; onClicked: sidebar.app.workspace = 2 }
        NavItem { id: navCompress; Layout.fillWidth: true; title: "Compress"; iconName: "compress"; active: sidebar.app.workspace === 3; onClicked: sidebar.app.workspace = 3 }
        NavItem { id: navGif; Layout.fillWidth: true; title: "GIF Studio"; iconName: "gif"; active: sidebar.app.workspace === 4; onClicked: sidebar.app.workspace = 4 }
        NavItem { id: navReframe; objectName: "navReframe"; Layout.fillWidth: true; title: "Reframe"; iconName: "reframe"; active: sidebar.app.workspace === 11; onClicked: sidebar.app.workspace = 11 }
        NavItem { id: navImages; objectName: "navImages"; Layout.fillWidth: true; title: "Images"; iconName: "image"; active: sidebar.app.workspace === 10; onClicked: sidebar.app.workspace = 10 }
        Item { Layout.preferredHeight: sidebar.app.height < 820 ? 12 : 20 }
        Text { text: "UTILITIES"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2; Layout.leftMargin: 13; Layout.bottomMargin: 7 }
        NavItem { id: navPdf; Layout.fillWidth: true; title: "PDF Tools"; iconName: "pdf"; active: sidebar.app.workspace === 5; onClicked: sidebar.app.workspace = 5 }
        NavItem { id: navQr; Layout.fillWidth: true; title: "QR Code"; iconName: "qr"; active: sidebar.app.workspace === 6; onClicked: sidebar.app.workspace = 6 }
        Item { Layout.preferredHeight: sidebar.app.height < 820 ? 12 : 20 }
        Text { text: "YOUR TOOLS SERVER"; color: Theme.textFaint; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.2; Layout.leftMargin: 13; Layout.bottomMargin: 7 }
        NavItem { id: navClips; Layout.fillWidth: true; title: "Clips"; iconName: "publish"; active: sidebar.app.workspace === 7; onClicked: sidebar.app.workspace = 7 }
        NavItem { id: navDrop; Layout.fillWidth: true; title: "Drop"; iconName: "publish"; active: sidebar.app.workspace === 8; onClicked: sidebar.app.workspace = 8 }
        NavItem { id: navShortener; Layout.fillWidth: true; title: "Shortener"; iconName: "publish"; active: sidebar.app.workspace === 9; onClicked: sidebar.app.workspace = 9 }
        Item { Layout.fillHeight: true }
        UpdateCard {
            id: updateCard
            Layout.fillWidth: true
            Layout.bottomMargin: 12
            updater: Core.appUpdater
            // Everything else in the sidebar stays put; the card shrinks
            // to one row when the full one would push Settings off screen.
            compact: navColumn.implicitHeight - implicitHeight + fullHeight > navColumn.height
            onRestartRequested: sidebar.app.quitApp()
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.line }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.leftMargin: 4
            spacing: 8
            // Settings, with the running version beside it (click the version to look for an update).
            Rectangle {
                id: settingsButton
                objectName: "settingsButton"
                Layout.fillWidth: true
                implicitHeight: 32
                radius: Theme.radiusSmall
                color: settingsMouse.containsMouse || sidebar.settingsOpen ? Theme.hover : Theme.hoverClear
                Accessible.role: Accessible.Button
                Accessible.name: "Settings"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 5
                    spacing: 9
                    ToolIcon { name: "sliders"; tint: settingsMouse.containsMouse || sidebar.settingsOpen ? Theme.text : Theme.textMuted }
                    Text { text: "Settings"; color: settingsMouse.containsMouse || sidebar.settingsOpen ? Theme.text : Theme.textMuted; font.pixelSize: 12; Layout.fillWidth: true }
                }
                MouseArea {
                    id: settingsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sidebar.openSettings()
                }
                ToolTip.visible: settingsMouse.containsMouse
                ToolTip.delay: 600
                ToolTip.text: "Settings  Ctrl+,"
            }
            Text {
                objectName: "versionLink"
                Layout.rightMargin: 6
                text: Core.appUpdater.checking ? "Checking…" : "v" + Core.appUpdater.currentVersion
                color: versionMouse.containsMouse ? Theme.text : Theme.textFaint
                font.pixelSize: 10
                font.features: { "tnum": 1 }
                MouseArea {
                    id: versionMouse
                    anchors.fill: parent
                    anchors.margins: -5
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Asking again brings back a card that was closed.
                    onClicked: { Prefs.dismissedUpdate = ""; Core.appUpdater.check() }
                }
            }
        }
    }
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }
}
