import QtQuick
import QtQuick.Layouts

// What sits on the bar and where. Moves go through `omarchy bar move` and
// adding and removing through `omarchy plugin enable/disable`, so the shell
// stays the one that writes its layout.
SettingsPage {
    id: page
    configFiles: ["shell"]
    resetPane: "bar"
    pane: "bar"
    title: qsTr("Bar")
    tagline: qsTr("%n widgets", "", page.placedCount)
    glyph: "\u{F06EB}"
    description: qsTr("Choose what the bar shows and arrange it. Drag a widget to move it. Changes appear on the bar right away.")
    lists: ["bar", "hardware"]
    settings: ["desktop.layout"]

    readonly property var bar: backend.lists.bar || ({})
    readonly property var sections: bar.sections || ({})
    readonly property var available: bar.available || []
    readonly property bool working: ["bar.move", "bar.drop", "bar.add", "bar.remove"].some(a => backend.busy.indexOf(a) >= 0)
    readonly property var order: ["left", "centerBegin", "center", "centerEnd", "right", "tray"]
    readonly property var sectionNames: ({
        left: qsTr("Left"), centerBegin: qsTr("Center, before the clock"), center: qsTr("Center"),
        centerEnd: qsTr("Center, after the clock"), right: qsTr("Right"), tray: qsTr("Tray drawer")
    })
    readonly property int placedCount: order.reduce((n, s) => n + (sections[s] || []).length, 0)
    // Widgets with something to set: a schema in their manifest, or one of
    // Omarchy's that Settings has a form for.
    readonly property var forms: ["omarchy.clock", "omarchy.weather", "omarchy.spacer", "omarchy.active-window"]
    function hasOptions(w) { return (w.schema || []).length > 0 || forms.indexOf(w.id) >= 0 }
    readonly property bool sideways: ["left", "right"].indexOf(backend.values["desktop.barPosition"]) >= 0
    function move(widget, from, to, index) { backend.act("bar.move", [widget.id, from, widget.index, to, index], ["bar"]) }

    // ---- Dragging a widget to a new place -----------------------------------
    // The widget picked up ({id, name, section, index}), where it would land
    // now ({section, gap}, the gap between widgets counted from 0), and where
    // the pointer is on screen.
    property var dragged: null
    property var target: null
    property point dragAt

    function beginDrag(widget, section) {
        dragged = { id: widget.id, name: widget.name, section: section, index: widget.index }
        target = null
    }
    function dragMoved(globalPos) {
        // The button can still be held after Escape let the widget go.
        if (!dragged) return
        dragAt = globalPos
        target = findTarget(globalPos)
    }
    function endDrag(drop) {
        const d = dragged, t = target
        dragged = null
        target = null
        if (drop && d && t)
            backend.act("bar.drop", [d.id, d.section, d.index, t.section, t.gap], ["bar"])
    }
    // Escape lets go without moving anything; true when there was a drag.
    function cancelDrag() {
        if (!dragged) return false
        endDrag(false)
        return true
    }
    function isDragged(widget, section) {
        return dragged !== null && dragged.section === section && dragged.index === widget.index && dragged.id === widget.id
    }
    function isTarget(section, gap) { return target !== null && target.section === section && target.gap === gap }

    function under(item, g) {
        if (!item || !item.visible) return false
        const p = item.mapFromGlobal(g.x, g.y)
        return p.x >= 0 && p.y >= 0 && p.x < item.width && p.y < item.height
    }
    // Where a widget let go at `g` would land, or null for nowhere new.
    function findTarget(g) {
        // Off the page, sections scrolled out of sight are still laid out
        // there; nothing is under the pointer that it can see.
        if (!under(page, g)) return null
        let found = null
        // The picture of the bar: before or after the chip it is over, or at
        // the end of the strip past the last chip.
        for (const strip of [leftStrip, centerStrip, rightStrip]) {
            if (found || !under(strip, g)) continue
            for (let i = 0; i < strip.chips.count && !found; ++i) {
                const chip = strip.chips.itemAt(i)
                if (!under(chip, g)) continue
                const after = chip.mapFromGlobal(g.x, g.y).x > chip.width / 2
                found = { section: chip.modelData.section, gap: chip.modelData.index + (after ? 1 : 0) }
            }
            // Past the last chip is the end of the strip's last section, so
            // the clock in the middle keeps its place; an empty strip takes
            // it in its home section.
            if (!found) {
                const empty = strip.holds.every(s => (sections[s] || []).length === 0)
                const section = empty ? strip.home : strip.holds[strip.holds.length - 1]
                found = { section: section, gap: (sections[section] || []).length }
            }
        }
        // The lists: the section it is over, after every row whose middle is
        // above the pointer.
        for (let i = 0; i < groups.count && !found; ++i) {
            const group = groups.itemAt(i)
            if (!under(group, g)) continue
            let gap = 0
            for (let j = 0; j < group.widgetRows.count; ++j) {
                const row = group.widgetRows.itemAt(j)
                if (row && row.mapFromGlobal(g.x, g.y).y > row.height / 2)
                    gap = Math.max(gap, row.modelData.index + 1)
            }
            found = { section: group.modelData, gap: gap }
        }
        // Either side of itself is where it is already.
        if (found && dragged && found.section === dragged.section
                && (found.gap === dragged.index || found.gap === dragged.index + 1))
            return null
        return found
    }

    // Near the top or bottom of the page, the page scrolls to bring more of
    // the lists into reach.
    Timer {
        interval: 16
        repeat: true
        running: page.dragged !== null
        onTriggered: {
            const y = page.mapFromGlobal(page.dragAt.x, page.dragAt.y).y
            const edge = ui.s(48)
            const speed = y < edge ? -Math.min(1, (edge - y) / edge)
                        : y > page.height - edge ? Math.min(1, (y - page.height + edge) / edge) : 0
            if (speed === 0) return
            const to = Math.max(0, Math.min(page.flick.contentY + speed * ui.s(14), page.maxY))
            if (to === page.flick.contentY) return
            page.flick.contentY = to
            page.target = page.findTarget(page.dragAt)
        }
    }

    // The widget's name, following the pointer while it is carried.
    Rectangle {
        parent: win.contentItem
        z: 100
        visible: page.dragged !== null
        readonly property point at: page.dragged ? parent.mapFromGlobal(page.dragAt.x, page.dragAt.y) : Qt.point(0, 0)
        x: at.x + ui.s(14)
        y: at.y + ui.s(10)
        width: ghostText.implicitWidth + ui.s(16)
        height: ghostText.implicitHeight + ui.s(8)
        radius: theme.radius
        color: ui.selectedFill
        border.width: 1
        border.color: ui.accent
        Text {
            id: ghostText
            anchors.centerIn: parent
            text: page.dragged ? page.dragged.name : ""
            color: ui.fg
            font.family: ui.font
            font.pixelSize: ui.caption
            textFormat: Text.PlainText
        }
    }

    // A line where a carried widget would go.
    component DropLine: Rectangle {
        property bool shown: false
        visible: shown
        z: 2
        color: ui.accent
        radius: Math.min(width, height) / 2
    }

    SettingsGroup {
        separated: true
        ToggleRow { setting: "desktop.barVisible"; label: qsTr("Show the bar") }
        ChoiceRow {
            setting: "desktop.barPosition"
            label: qsTr("Position on screen")
            options: [
                { value: "top", text: qsTr("Top") }, { value: "bottom", text: qsTr("Bottom") },
                { value: "left", text: qsTr("Left") }, { value: "right", text: qsTr("Right") }
            ]
        }
        ToggleRow {
            visible: (backend.lists.hardware || {}).laptop === true
            setting: "bar.batteryPercentage"
            label: qsTr("Show battery percentage")
        }
        ChoiceRow {
            setting: "appearance.barBackground"
            label: qsTr("Bar background")
            options: [
                { value: "opaque", text: qsTr("Opaque") },
                { value: "glassy", text: qsTr("Glassy") },
                { value: "none", text: qsTr("None") }
            ]
        }
        SliderRow {
            visible: backend.values["appearance.barBackground"] !== "none"
            setting: "bar.backgroundAlpha"
            label: qsTr("Bar background opacity")
            from: 0.2
            to: 1
            stepSize: 0.05
            format: v => qsTr("%1%").arg(Math.round(v * 100).toLocaleString(Qt.locale(), 'f', 0))
        }
        SliderRow {
            visible: !page.sideways
            setting: "bar.height"
            label: qsTr("Bar height")
            from: 18
            to: 48
            format: v => qsTr("%1 px").arg(Math.round(v).toLocaleString(Qt.locale(), 'f', 0))
        }
        SliderRow {
            visible: page.sideways
            setting: "bar.sideWidth"
            label: qsTr("Bar width on the side of the screen")
            from: 18
            to: 56
            format: v => qsTr("%1 px").arg(Math.round(v).toLocaleString(Qt.locale(), 'f', 0))
        }
        ToggleRow {
            setting: "bar.scaleWithFont"
            label: qsTr("Bar grows with the text size")
            sublabel: qsTr("The size above is for the standard text size, and follows Fonts › Text size")
        }
    }

    // What the mouse does on the bar. Omarchy's bar has these built in, so
    // they are explained here, each with a button that does the same.
    SettingsGroup {
        title: qsTr("Mouse on the bar")
        footer: qsTr("These are built into Omarchy's bar.")
        SettingRow {
            label: qsTr("Double-click empty space")
            sublabel: qsTr("Switches the background between none, glassy and opaque")
            OmaButton {
                text: qsTr("Next background")
                spinning: backend.busy.indexOf("bar.cycleBackground") >= 0
                anchors.verticalCenter: parent.verticalCenter
                onClicked: backend.act("bar.cycleBackground", [], [], "bar")
            }
        }
        SettingRow {
            id: edges
            label: qsTr("Drag empty space")
            sublabel: qsTr("Moves the bar to the edge of the screen you let go nearest. Pressing and holding works too.")
            readonly property string at: backend.values["desktop.barPosition"] || "top"
            Repeater {
                model: [
                    { value: "top", glyph: "\u{F005D}", text: qsTr("Top") },
                    { value: "bottom", glyph: "\u{F0045}", text: qsTr("Bottom") },
                    { value: "left", glyph: "\u{F004D}", text: qsTr("Left") },
                    { value: "right", glyph: "\u{F0054}", text: qsTr("Right") }
                ]
                delegate: OmaButton {
                    required property var modelData
                    glyph: modelData.glyph
                    tooltip: modelData.text
                    selected: edges.at === modelData.value
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    Accessible.name: modelData.text
                    onClicked: if (!selected) backend.set("desktop.barPosition", modelData.value)
                }
            }
        }
        SettingRow {
            label: qsTr("Click the workspace you're on")
            sublabel: qsTr("Switches its windows between tiling, scrolling and floating. Scrolling over the workspaces moves between them.")
            OmaButton {
                text: qsTr("Switch layout")
                tooltip: qsTr("Switches the workspace this window is on")
                spinning: backend.busy.indexOf("workspace.cycleLayout") >= 0
                anchors.verticalCenter: parent.verticalCenter
                onClicked: backend.act("workspace.cycleLayout", [])
            }
        }
        ChoiceRow {
            setting: "desktop.layout"
            label: qsTr("Arrange new workspaces by")
            options: [
                { value: "dwindle", text: qsTr("Tiling") },
                { value: "scrolling", text: qsTr("Scrolling") },
                { value: "floating", text: qsTr("Floating") }
            ]
        }
    }

    // A small picture of the bar as it is laid out now; its widgets can be
    // dragged too. The bar itself is never mirrored, so neither is its
    // picture.
    Rectangle {
        Layout.fillWidth: true
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true
        implicitHeight: Math.max(preview.implicitHeight, ui.s(22)) + ui.s(12)
        radius: theme.radius
        color: ui.normalFill
        border.width: 1
        border.color: page.dragged ? ui.accent : ui.normalBorder

        RowLayout {
            id: preview
            anchors.fill: parent
            anchors.margins: ui.s(6)
            spacing: ui.s(6)
            // One strip of the bar. `holds` are the sections it shows, in
            // order; `home` takes a drop when they are all empty.
            component Strip: Item {
                // Ids outside an inline component aren't seen inside it.
                required property Item host
                property alias chips: chipRepeater
                property var holds: []
                property string home
                readonly property var widgets: holds.reduce((all, s) =>
                    all.concat((host.sections[s] || []).map(w => Object.assign({ section: s }, w))), [])
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                implicitHeight: flow.implicitHeight
                Flow {
                    id: flow
                    width: parent.width
                    spacing: ui.s(4)
                    Repeater {
                        id: chipRepeater
                        model: parent.parent.widgets
                        delegate: Rectangle {
                            id: chipBox
                            required property var modelData
                            readonly property bool last: modelData.index === (host.sections[modelData.section] || []).length - 1
                            // A long name is cut short rather than run past the picture.
                            width: Math.min(chip.implicitWidth + ui.s(8), flow.width)
                            height: chip.implicitHeight + ui.s(4)
                            radius: theme.radius
                            color: ui.hoverFill
                            opacity: host.isDragged(modelData, modelData.section) ? 0.45 : 1
                            Text {
                                id: chip
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, parent.width - ui.s(8))
                                elide: Text.ElideRight
                                text: chipBox.modelData.name
                                color: ui.fg
                                font.family: ui.font
                                font.pixelSize: ui.caption
                                textFormat: Text.PlainText
                            }
                            DropLine {
                                shown: host.isTarget(chipBox.modelData.section, chipBox.modelData.index)
                                width: ui.s(2); height: parent.height; x: -ui.s(3)
                            }
                            DropLine {
                                shown: chipBox.last && host.isTarget(chipBox.modelData.section, chipBox.modelData.index + 1)
                                width: ui.s(2); height: parent.height; x: parent.width + ui.s(1)
                            }
                            BarDragGrip {
                                anchors.fill: parent
                                bar: host
                                widget: chipBox.modelData
                                section: chipBox.modelData.section
                            }
                        }
                    }
                    // Where a drop goes on a strip with nothing on it yet.
                    DropLine {
                        shown: parent.parent.widgets.length === 0 && host.target !== null
                               && parent.parent.holds.indexOf(host.target.section) >= 0
                        width: ui.s(2)
                        height: ui.s(18)
                    }
                }
            }
            Strip { id: leftStrip; host: page; holds: ["left"]; home: "left" }
            Strip { id: centerStrip; host: page; holds: ["centerBegin", "center", "centerEnd"]; home: "center" }
            Strip { id: rightStrip; host: page; holds: ["right"]; home: "right" }
        }
    }

    Repeater {
        id: groups
        model: page.order
        delegate: SettingsGroup {
            id: group
            required property string modelData
            readonly property var widgets: page.sections[modelData] || []
            property alias widgetRows: rowRepeater
            Layout.fillWidth: true
            title: page.sectionNames[modelData]
            footer: modelData === "tray" ? qsTr("Widgets here open from the tray's drawer instead of sitting on the bar.")
                  : modelData === "center" ? qsTr("Put widgets beside the clock in the sections before and after it, or the clock moves off center.")
                  : ""

            Repeater {
                id: rowRepeater
                model: group.widgets
                delegate: SettingRow {
                    id: wrow
                    required property var modelData
                    readonly property bool last: modelData.index === group.widgets.length - 1
                    label: modelData.name
                    sublabel: modelData.description || modelData.id
                    glyph: "\u{F01DD}"
                    tint: ui.muted
                    dimmed: page.isDragged(modelData, group.modelData)
                    tappable: false
                    // The whole row picks the widget up; the buttons on it
                    // still take their clicks.
                    BarDragGrip {
                        parent: wrow
                        anchors.fill: parent
                        z: -1
                        bar: page
                        widget: wrow.modelData
                        section: group.modelData
                    }
                    DropLine {
                        parent: wrow
                        shown: page.isTarget(group.modelData, wrow.modelData.index)
                        width: parent.width; height: ui.s(2); y: -ui.s(2)
                    }
                    DropLine {
                        parent: wrow
                        shown: wrow.last && page.isTarget(group.modelData, wrow.modelData.index + 1)
                        width: parent.width; height: ui.s(2); y: parent.height
                    }
                    // Its own options, on a page of their own.
                    OmaButton {
                        visible: page.hasOptions(wrow.modelData)
                        glyph: "\u{F0493}"
                        bordered: false
                        tooltip: qsTr("Options")
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: win.openSub("BarWidget", wrow.modelData.name,
                                               { id: wrow.modelData.id, section: group.modelData, index: wrow.modelData.index })
                    }
                    OmaButton {
                        glyph: "\u{F0143}"
                        bordered: false
                        enabled: !page.working && wrow.modelData.index > 0
                        tooltip: qsTr("Move up")
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: page.move(wrow.modelData, group.modelData, group.modelData, wrow.modelData.index - 1)
                    }
                    OmaButton {
                        glyph: "\u{F0140}"
                        bordered: false
                        enabled: !page.working && wrow.modelData.index < group.widgets.length - 1
                        tooltip: qsTr("Move down")
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: page.move(wrow.modelData, group.modelData, group.modelData, wrow.modelData.index + 1)
                    }
                    ChoiceBox {
                        enabled: !page.working
                        maxWidth: Math.round(220 * ui.scale)
                        model: page.order.map(s => ({ value: s, text: page.sectionNames[s] }))
                        textRole: "text"
                        valueRole: "value"
                        currentIndex: page.order.indexOf(group.modelData)
                        onActivated: {
                            if (currentValue !== group.modelData)
                                page.move(wrow.modelData, group.modelData, currentValue, (page.sections[currentValue] || []).length)
                            currentIndex = Qt.binding(() => page.order.indexOf(group.modelData))
                        }
                        Accessible.name: qsTr("Section")
                    }
                    OmaButton {
                        glyph: "\u{F0156}"
                        bordered: false
                        enabled: !page.working
                        tooltip: qsTr("Remove from the bar")
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: backend.act("bar.remove", [wrow.modelData.id], ["bar", "plugins"])
                    }
                }
            }

            // A section with nothing in it yet, and a place to drop into it.
            // It is there before a drag too, so nothing moves when one starts.
            Rectangle {
                visible: group.widgets.length === 0
                width: parent ? parent.width : 0
                height: ui.rowHeight
                radius: theme.radius
                color: page.isTarget(group.modelData, 0) ? ui.hoverFill : "transparent"
                border.width: 1
                border.color: page.isTarget(group.modelData, 0) ? ui.accent : ui.normalBorder
                Text {
                    anchors.centerIn: parent
                    text: page.dragged ? qsTr("Drop here") : qsTr("Nothing here yet.")
                    color: ui.muted
                    font.family: ui.font
                    font.pixelSize: ui.caption
                    textFormat: Text.PlainText
                }
            }
        }
    }

    SettingsGroup {
        title: qsTr("Add to the Bar")
        footer: page.available.length === 0 ? qsTr("Every widget is on the bar already. Plugins adds more.")
                                            : qsTr("Removing a widget turns its plugin off; adding it turns it back on.")
        SettingRow {
            visible: page.available.length > 0
            label: qsTr("Widget")
            ChoiceBox {
                id: widget
                maxWidth: Math.round(220 * ui.scale)
                model: page.available
                textRole: "name"
                valueRole: "id"
                currentIndex: -1
                placeholder: qsTr("Choose a widget")
                onCountChanged: Qt.callLater(() => currentIndex = -1)
                Accessible.name: qsTr("Widget to add")
            }
            ChoiceBox {
                id: where
                maxWidth: Math.round(220 * ui.scale)
                model: page.order.map(s => ({ value: s, text: page.sectionNames[s] }))
                textRole: "text"
                valueRole: "value"
                currentIndex: page.order.indexOf("right")
                Accessible.name: qsTr("Section")
            }
            OmaButton {
                text: qsTr("Add")
                enabled: widget.currentIndex >= 0 && !page.working
                anchors.verticalCenter: parent.verticalCenter
                onClicked: backend.act("bar.add", [widget.currentValue, where.currentValue], ["bar", "plugins"])
            }
        }
    }
}
