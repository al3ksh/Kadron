import QtQuick

Item {
    id: item
    property string title: ""
    property string iconName: "edit"
    property bool active: false
    signal clicked()
    activeFocusOnTab: true
    implicitHeight: 43
    implicitWidth: 172
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            item.clicked()
            event.accepted = true
        }
    }

    // The active fill and accent bar are drawn once by the rail so they can
    // travel between items; each item only paints its own hover state.
    Rectangle {
        anchors.fill: parent
        radius: 9
        color: Theme.hover
        opacity: pointer.containsMouse && !item.active ? 0.8 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fade; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent
        radius: 9
        color: "transparent"
        border.width: item.activeFocus ? 1 : 0
        border.color: Theme.accentFocus
    }
    ToolIcon {
        name: item.iconName
        tint: item.active ? Theme.accent : pointer.containsMouse ? Theme.textSoft : Theme.textMuted
        x: 14
        anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        text: item.title
        x: 46
        anchors.verticalCenter: parent.verticalCenter
        color: item.active ? Theme.text : pointer.containsMouse ? Theme.textSoft : Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: item.active ? Font.DemiBold : Font.Medium
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { item.forceActiveFocus(); item.clicked() }
    }
}
