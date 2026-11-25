import QtQuick
import "Fonts.js" as Fonts

// Interactive settings row for Trackpad and Touchscreen panes:
// passively tracks hover across the whole row (including controls) to switch the top gesture animation,
// and lets clicking/tapping the label area replay the gesture without stealing events from switches/sliders.
Item {
    id: gr
    required property var t
    property string title: ""
    property string subtitle: ""
    property string gestureId: ""
    property string activeGesture: ""
    default property alias control: grSlot.data
    signal activated(string gid, string label, bool clicked)

    readonly property bool selected: gestureId !== "" && activeGesture === gestureId
    width: parent ? parent.width : 0
    height: Math.max(48, grTextCol.height + 22, grSlot.height + 20)

    HoverHandler {
        id: grHover
        onHoveredChanged: if (hovered && gr.gestureId !== "") gr.activated(gr.gestureId, gr.title, false)
    }

    Rectangle {
        visible: gr.y > 0.5
        x: 14
        width: parent.width - 14
        height: 1
        color: gr.t.sep
    }

    Rectangle {
        x: 5
        y: 4
        width: parent.width - 10
        height: parent.height - 8
        radius: 17
        color: gr.selected
               ? (gr.t.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.055))
               : (grHover.hovered ? gr.t.hover : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        x: 0
        y: 0
        width: Math.max(0, gr.width - grSlot.width - 20)
        height: parent.height
        cursorShape: Qt.PointingHandCursor
        onClicked: if (gr.gestureId !== "") gr.activated(gr.gestureId, gr.title, true)
    }

    Column {
        id: grTextCol
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, gr.width - x - grSlot.width - 30)
        spacing: 2
        Text {
            width: parent.width
            text: gr.title
            elide: Text.ElideRight
            color: gr.t.text
            font.family: Fonts.forWeight(gr.selected ? Font.Medium : Font.Normal, gr.t.fam)
            font.weight: gr.selected ? Font.Medium : Font.Normal
            font.pixelSize: 13
        }
        Text {
            visible: gr.subtitle !== ""
            width: parent.width
            text: gr.subtitle
            wrapMode: Text.WordWrap
            color: gr.t.text2
            font.family: Fonts.forWeight(Font.Normal, gr.t.fam)
            font.pixelSize: 12
        }
    }

    Item {
        id: grSlot
        z: 2
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
