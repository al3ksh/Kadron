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

    Rectangle {
        anchors.fill: parent
        radius: 9
        color: item.active ? "#303b30" : pointer.containsMouse ? "#252a2f" : "transparent"
        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent
        radius: 9
        color: "transparent"
        border.width: item.activeFocus ? 1 : 0
        border.color: "#d9f9a3"
    }
    Rectangle {
        width: 3
        height: 18
        radius: 2
        x: 0
        anchors.verticalCenter: parent.verticalCenter
        color: "#c9f27a"
        opacity: item.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }
    ToolIcon {
        name: item.iconName
        tint: item.active ? "#c9f27a" : pointer.containsMouse ? "#e8ede7" : "#a8b0b9"
        x: 14
        anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        text: item.title
        x: 46
        anchors.verticalCenter: parent.verticalCenter
        color: item.active ? "#f6f8f2" : pointer.containsMouse ? "#e5e9e4" : "#b6bec5"
        font.family: "Segoe UI"
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
