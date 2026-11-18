import QtQuick

Item {
    id: cell

    required property var modelData
    required property bool dark
    required property color foreground
    required property color secondary
    required property color accent
    required property string dayFont
    required property string labelFont

    readonly property color holidayColor: dark ? "#ffb3a4" : "#993425"
    readonly property color workColor: dark ? "#acd5ff" : "#285b91"

    height: 42
    opacity: modelData.cur || modelData.today ? 1 : 0.5

    Rectangle {
        visible: cell.modelData.today
        anchors.horizontalCenter: parent.horizontalCenter
        width: 22
        height: width
        radius: width / 2
        color: cell.accent
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        height: 22
        verticalAlignment: Text.AlignVCenter
        text: cell.modelData.n
        color: cell.modelData.today ? "white" : cell.foreground
        font.family: cell.dayFont
        font.pixelSize: 13
        font.weight: cell.modelData.today ? Font.DemiBold : Font.Normal
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 22
        textFormat: Text.PlainText
        text: cell.modelData.china.lunar
        color: cell.secondary
        font.family: cell.labelFont
        font.pixelSize: 10
    }

    Text {
        width: parent.width
        y: 33
        textFormat: Text.PlainText
        // Two festivals can share one date, such as National Day and Mid-Autumn.
        text: cell.modelData.china.festival.includes("·")
              ? cell.modelData.china.festival.replace(/节/g, "")
              : cell.modelData.china.festival
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        color: cell.holidayColor
        font.family: cell.labelFont
        font.pixelSize: 9
    }

    Text {
        visible: text !== ""
        anchors.right: parent.right
        anchors.rightMargin: 1
        y: 1
        textFormat: Text.PlainText
        text: cell.modelData.china.status
        color: text === "休" ? cell.holidayColor : cell.workColor
        font.family: cell.labelFont
        font.pixelSize: 9
    }
}
