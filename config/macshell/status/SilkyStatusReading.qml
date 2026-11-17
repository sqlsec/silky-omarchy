import QtQuick

Column {
    id: reading
    required property string label
    required property string value
    required property string symbol
    required property color ink
    required property color foreground
    required property color muted
    required property string fontFamily
    spacing: 3
    Row {
        spacing: 4
        SilkyStatusIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 13
            height: 13
            kind: reading.symbol
            ink: reading.ink
        }
        Text {
            text: reading.label
            textFormat: Text.PlainText
            color: reading.muted
            font.family: reading.fontFamily
            font.pixelSize: 11
        }
    }
    Text {
        text: reading.value
        textFormat: Text.PlainText
        color: reading.foreground
        font.family: reading.fontFamily
        font.pixelSize: 22
        font.weight: Font.DemiBold
    }
}
