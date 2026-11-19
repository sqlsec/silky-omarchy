// Text in a Silky widget: the host card supplies palette and fonts.
import QtQuick

Text {
    required property var host
    property int px: 13
    property bool strong: false
    property bool dim: false
    color: dim ? host.fg2 : host.fg
    font.family: strong ? host.bold : host.fam
    font.pixelSize: px
    font.weight: strong ? Font.DemiBold : Font.Normal
    elide: Text.ElideRight
    textFormat: Text.PlainText
    maximumLineCount: 1
}
