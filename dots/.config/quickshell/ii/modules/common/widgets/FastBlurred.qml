import QtQuick

// Tinted card over the compositor's blur of what is behind it
Item {
    id: root
    property real cardRadius: 30
    property color tint: "white"
    property real tintOpacity: 0.15
    readonly property real radius: cardRadius // read by BlurSource

    BlurSource {}

    Rectangle {
        anchors.fill: parent
        radius: root.cardRadius
        color: root.tint
        opacity: root.tintOpacity
    }
}
