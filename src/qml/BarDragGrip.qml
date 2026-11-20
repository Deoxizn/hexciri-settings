import QtQuick

// Picks a bar widget up to drop somewhere else on the Bar page: a row in
// the lists, or a chip in the picture of the bar. The page works out where
// it would land; this only reports where the pointer is. A MouseArea rather
// than a DragHandler: it can keep the page's scrolling from taking the drag
// over.
MouseArea {
    id: grip
    // The Bar page, and the widget as the page lists it ({id, name, index}).
    required property Item bar
    required property var widget
    required property string section
    property bool dragging: false
    property point start

    enabled: !bar.working
    hoverEnabled: true
    preventStealing: true
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

    onPressed: mouseEvent => start = Qt.point(mouseEvent.x, mouseEvent.y)
    onPositionChanged: mouseEvent => {
        if (!pressed) return
        if (!dragging) {
            if (Math.hypot(mouseEvent.x - start.x, mouseEvent.y - start.y) < Qt.styleHints.startDragDistance) return
            dragging = true
            bar.beginDrag(widget, section)
        }
        bar.dragMoved(mapToGlobal(mouseEvent.x, mouseEvent.y))
    }
    onReleased: finish(true)
    onCanceled: finish(false)
    // The list can be read again while a drag is on (the bar changed from
    // elsewhere), which takes this row away mid-drag.
    Component.onDestruction: finish(false)

    function finish(drop) {
        if (!dragging) return
        dragging = false
        bar.endDrag(drop)
    }
}
