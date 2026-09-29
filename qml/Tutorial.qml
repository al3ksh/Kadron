import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A short tour on first run: one card per area of the app, with the page
// behind it switched to match. Skipping or finishing marks it done in Prefs.
Dialog {
    id: tour
    property int step: 0
    signal pageRequested(int page)

    readonly property var steps: [
        { icon: "edit", page: 0, title: "Welcome to Kadron",
          text: "Drop a video anywhere on the window or press Ctrl+O. Trim with I and O, split with Ctrl+K and export with the button at the top." },
        { icon: "music", page: 0, title: "Clips, music and captions",
          text: "The timeline has a lane for extra audio and one for text over the video. Double-click an empty lane to add something at that spot." },
        { icon: "download", page: 1, title: "Download from a link",
          text: "On the Download page press Ctrl+V and Enter. Queue several links or a whole playlist, and find finished files under Recent." },
        { icon: "compress", page: 3, title: "Quick tools",
          text: "Audio, Compress, GIF Studio, Reframe, Images, PDF and QR work on their own files. Drag a finished file straight out of Kadron." },
        { icon: "sliders", page: 0, title: "Make it yours",
          text: "Ctrl+P finds any command. Settings (Ctrl+,) holds the theme, the tray and background notifications. This tour lives there too." }
    ]
    readonly property var current: steps[step]

    function start() {
        step = 0
        pageRequested(steps[0].page)
        open()
    }
    function finish() {
        Prefs.tutorialDone = true
        close()
    }

    modal: true
    focus: true
    anchors.centerIn: parent
    width: Math.min(460, parent ? parent.width - 48 : 460)
    padding: 0
    standardButtons: Dialog.NoButton
    closePolicy: Popup.CloseOnEscape
    onStepChanged: if (visible) pageRequested(steps[step].page)
    onRejected: Prefs.tutorialDone = true

    Overlay.modal: Rectangle {
        color: Theme.scrim
        Behavior on opacity { NumberAnimation { duration: Theme.reveal } }
    }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.reveal; easing.type: Easing.OutCubic }
            SnapSpring { property: "scale"; from: 0.94; to: 1 }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.fadeFast; easing.type: Easing.InCubic }
    }
    background: Rectangle {
        color: Theme.card
        radius: Theme.radiusLarge
        border.color: Theme.lineStrong
    }

    contentItem: ColumnLayout {
        spacing: 0
        Keys.onRightPressed: nextButton.clicked()
        Keys.onLeftPressed: if (tour.step > 0) tour.step--

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 24
            Layout.bottomMargin: 0
            spacing: 14
            Rectangle {
                implicitWidth: 44
                implicitHeight: 44
                radius: 12
                color: Theme.accentWash
                border.color: Theme.accentEdge
                ToolIcon {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    name: tour.current.icon
                    tint: Theme.accent
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Text {
                    text: (tour.step + 1) + " of " + tour.steps.length
                    color: Theme.textFaint
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
                Text {
                    objectName: "tutorialTitle"
                    Layout.fillWidth: true
                    text: tour.current.title
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }
        }
        Text {
            Layout.fillWidth: true
            Layout.margins: 24
            Layout.topMargin: 14
            Layout.preferredHeight: 58
            text: tour.current.text
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 13
            lineHeight: 1.25
            wrapMode: Text.WordWrap
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 24
            Layout.topMargin: 0
            spacing: 8
            Row {
                spacing: 6
                Repeater {
                    model: tour.steps.length
                    Rectangle {
                        required property int index
                        width: index === tour.step ? 18 : 6
                        height: 6
                        radius: 3
                        color: index === tour.step ? Theme.accent : Theme.lineStrong
                        Behavior on width { SnapSpring {} }
                    }
                }
            }
            Item { Layout.fillWidth: true }
            EditorButton {
                objectName: "tutorialSkip"
                text: "Skip"
                subtle: true
                visible: tour.step < tour.steps.length - 1
                onClicked: tour.finish()
            }
            EditorButton {
                text: "Back"
                visible: tour.step > 0
                onClicked: tour.step--
            }
            EditorButton {
                id: nextButton
                objectName: "tutorialNext"
                text: tour.step < tour.steps.length - 1 ? "Next" : "Get started"
                primary: true
                onClicked: {
                    if (tour.step < tour.steps.length - 1) tour.step++
                    else tour.finish()
                }
            }
        }
    }
}
