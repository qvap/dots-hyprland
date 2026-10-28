import QtQuick
import QtQuick.Effects
import qs.modules.common

Rectangle {
    id: root
    required property var widget
    property bool blurred: Config.options.background.widgets.blurWidgets
    property bool shadowed: Config.options.background.widgets.shadow
    property color tint: Appearance.colors.colLayer1
    property real tintOpacity: 0.55
    property bool glass: true

    radius: Appearance.rounding?.verylarge ?? 30
    // Glass and blur show what is behind the card; FastBlurred paints the tint
    color: (glass && Config.options.background.widgets.glass.enable) || blurred
        ? "transparent" : Appearance.colors.colPrimaryContainer

    Item { // The shadow's fill would show through a see-through card: cut it out under the card
        id: shadowArea
        readonly property real pad: Appearance.sizes.elevationMargin * 2
        anchors.fill: parent
        anchors.margins: -pad
        z: -2
        visible: root.shadowed
        layer.enabled: root.color.a < 1
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: shadowCutout
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        Item { // anchors only reach siblings and the parent, so mirror the card here
            id: shadowTarget
            anchors.fill: parent
            anchors.margins: shadowArea.pad
            readonly property real radius: root.radius
        }
        StyledRectangularShadow {
            target: shadowTarget
        }
    }
    Item {
        id: shadowCutout
        anchors.fill: shadowArea
        layer.enabled: true
        visible: false
        Rectangle {
            anchors.fill: parent
            anchors.margins: shadowArea.pad
            radius: root.radius
        }
    }

    FrostedGlass {
        anchors.fill: parent
        blurSource: root.widget.wallpaperItem
        cardRadius: root.radius
        tint: Appearance.colors.colPrimaryContainer
        trackX: root.widget.x + root.x
        trackY: root.widget.y + root.y
        visible: root.glass && Config.options.background.widgets.glass.enable
    }

    FastBlurred {
        anchors.fill: parent
        cardRadius: root.radius
        tint: root.tint
        tintOpacity: root.tintOpacity
        visible: root.blurred && !(root.glass && Config.options.background.widgets.glass.enable)
    }
}
