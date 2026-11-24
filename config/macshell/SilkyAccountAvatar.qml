import QtQuick
import QtQuick.Shapes

Shape {
    id: avatar
    required property url source
    required property color placeholder
    required property int sourcePixels
    preferredRendererType: Shape.CurveRenderer

    Item {
        id: pictureTexture
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        Rectangle {
            anchors.fill: parent
            color: avatar.placeholder
        }

        Image {
            anchors.fill: parent
            source: avatar.source
            sourceSize: Qt.size(avatar.sourcePixels, avatar.sourcePixels)
            fillMode: Image.PreserveAspectCrop
            cache: false
            smooth: true
            mipmap: true
        }
    }

    ShapePath {
        strokeWidth: -1
        fillItem: pictureTexture
        PathAngleArc {
            centerX: avatar.width / 2
            centerY: avatar.height / 2
            radiusX: centerX
            radiusY: centerY
            startAngle: 0
            sweepAngle: 360
        }
    }
}
