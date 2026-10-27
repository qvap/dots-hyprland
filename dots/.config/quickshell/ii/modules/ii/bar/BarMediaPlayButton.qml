pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    required property MprisPlayer player
    required property QtObject colors
    readonly property bool isPlaying: player?.isPlaying ?? false
    implicitWidth: 40
    implicitHeight: 23
    buttonRadius: root.isPlaying ? Appearance.rounding.normal : 13
    colBackground: root.isPlaying ? root.colors.colPrimary : root.colors.colSecondaryContainer
    colBackgroundHover: root.isPlaying ? root.colors.colPrimaryHover : root.colors.colSecondaryContainerHover
    colRipple: root.isPlaying ? root.colors.colPrimaryActive : root.colors.colSecondaryContainerActive
    downAction: () => root.player?.togglePlaying()
    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: root.isPlaying ? "pause" : "play_arrow"
        iconSize: Appearance.font.pixelSize.large
        fill: 1
        color: root.isPlaying ? root.colors.colOnPrimary : root.colors.colOnSecondaryContainer
    }
}
