pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Qt5Compat.GraphicalEffects

// Rounded clipping with a stable allocation throughout the morph. The regular
// ClippingRectangle resizes both its content and mask textures on every frame.
// Clipping is only needed while the content can overflow, so it can be switched
// off to skip the offscreen passes.
Item {
    id: root
    required property size textureSize
    property bool clipping: true
    property alias radius: background.radius
    property alias color: background.color
    readonly property alias contentItem: content
    default property alias contentData: content.data
    readonly property size backingTextureSize: Qt.size(
        Math.ceil(textureSize.width * Screen.devicePixelRatio),
        Math.ceil(textureSize.height * Screen.devicePixelRatio))

    Rectangle {
        id: background
        anchors.fill: parent
        antialiasing: true
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        color: "white"
        antialiasing: true
        visible: false
        layer.enabled: root.clipping
        layer.textureSize: root.backingTextureSize
        layer.smooth: true
    }

    Item {
        id: content
        anchors.fill: parent
        layer.enabled: root.clipping
        layer.textureSize: root.backingTextureSize
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: mask
        }
    }
}
