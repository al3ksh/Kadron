import QtQuick

// Lets a finished file be dragged out of Kadron onto Explorer, Discord or a
// browser. Fill a row with it underneath its buttons: presses on the buttons
// stay theirs, a drag anywhere else carries the file.
Item {
    id: dragOut
    property url file

    Drag.active: handler.active
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction
    Drag.mimeData: ({ "text/uri-list": dragOut.file.toString() })

    DragHandler {
        id: handler
        target: null
        enabled: dragOut.file.toString().length > 0
    }
    HoverHandler {
        enabled: handler.enabled
        cursorShape: handler.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    }
}
