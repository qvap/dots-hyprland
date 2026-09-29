pragma ComponentBehavior: Bound
import QtQuick

// A looping name viewport shared by the workspace pill and Island.
Item {
    id: root
    property string text: ""
    property color color: "white"
    property color backgroundColor: "black"
    property alias font: measure.font
    property bool scrolling: true
    property bool scrollOnlyOnOverflow: false
    property bool centered: true
    readonly property bool overflowing: measure.implicitWidth > width
    readonly property bool looping: scrolling && (!scrollOnlyOnOverflow || overflowing)
    property real scrollProgress: 0
    readonly property real scrollDistance: measure.implicitWidth + 24
    implicitWidth: measure.implicitWidth
    implicitHeight: measure.implicitHeight
    clip: true

    Text { id: measure; text: root.text; visible: false; renderType: Text.QtRendering; font.hintingPreference: Font.PreferNoHinting }
    Row {
        anchors.verticalCenter: parent.verticalCenter
        // Move one cached strip so repeated glyphs share the same subpixel translation.
        layer.enabled: true
        layer.smooth: true
        x: (root.centered ? Math.max(0, (root.width - measure.implicitWidth) / 2) : 0)
            - (root.looping ? (1 + root.scrollProgress) * root.scrollDistance : 0)
        spacing: 24
        Repeater {
            model: root.looping ? Math.ceil(root.width / root.scrollDistance) + 3 : 1
            Text {
                text: root.text
                color: root.color
                font: measure.font
                renderType: Text.QtRendering
                width: measure.implicitWidth
                height: measure.implicitHeight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
    Repeater {
        model: 2
        Rectangle {
            required property int index
            visible: root.looping
            x: index === 0 ? 0 : root.width - width
            width: Math.min(measure.font.pixelSize, root.width / 3)
            height: parent.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: index === 0 ? root.backgroundColor : "transparent" }
                GradientStop { position: 1; color: index === 0 ? "transparent" : root.backgroundColor }
            }
        }
    }
    NumberAnimation on scrollProgress {
        from: 0
        to: 1
        duration: Math.max(1, root.scrollDistance / 24 * 1000)
        loops: Animation.Infinite
        running: root.visible && root.looping && root.text.length > 0 && root.width > 0
        easing.type: Easing.Linear
    }
}
