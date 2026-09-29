pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Fixed content geometry: text and audio samples never resize or reposition the pill.
Item {
    id: root
    required property MprisPlayer player
    property bool mediaVisible: false
    property bool trackVisible: false
    property bool specialVisible: false
    property string specialName: ""
    property bool vertical: false
    property bool barOnRight: false
    property bool workspaceVisible: false
    property alias middleSlot: middle
    property real workspaceMix: workspaceVisible ? 1 : 0
    property real specialMix: specialVisible ? 1 : 0
    property string displayedSpecialName: ""
    onSpecialNameChanged: if (specialName.length > 0)
        displayedSpecialName = specialName
    Component.onCompleted: displayedSpecialName = specialName
    Behavior on workspaceMix {
        NumberAnimation {
            duration: 180
            easing.type: Easing.InOutQuad
        }
    }
    Behavior on specialMix {
        NumberAnimation {
            duration: 220
            easing.type: Easing.InOutQuad
        }
    }
    property list<real> visualizerPoints: []
    readonly property bool isPlaying: player?.isPlaying ?? false
    readonly property string title: StringUtils.cleanMusicTitle(player?.trackTitle) || player?.identity || Translation.tr("No media")
    readonly property string artist: player?.trackArtist ?? ""
    property color visualizerColor: Appearance.colors.colPrimary

    ClippingRectangle {
        visible: root.mediaVisible
        x: root.vertical ? (parent.width - width) / 2 : 10
        y: root.vertical ? 10 : (parent.height - height) / 2
        width: 22
        height: 22
        radius: 6
        color: "#202020"
        Image {
            id: art
            anchors.fill: parent
            source: root.player?.trackArtUrl ?? ""
            sourceSize: Qt.size(44, 44)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            text: "music_note"
            iconSize: 17
            color: "white"
        }
    }

    Item {
        id: middle
        x: root.vertical ? 0 : (root.mediaVisible ? 40 : 16)
        y: root.vertical ? (root.mediaVisible ? 44 : 16) : 0
        width: root.vertical ? root.width : Math.max(0, root.width - (root.mediaVisible ? 76 : 32))
        height: root.vertical ? Math.max(0, root.height - (root.mediaVisible ? 88 : 32)) : root.height

        Item {
            id: orientedMiddle
            anchors.centerIn: parent
            width: root.vertical ? middle.height : middle.width
            height: root.vertical ? middle.width : middle.height
            rotation: root.vertical ? (root.barOnRight ? 90 : -90) : 0

            Item {
                id: labels
                visible: root.mediaVisible && root.trackVisible && opacity > 0
                opacity: (1 - root.workspaceMix) * (1 - root.specialMix)
                anchors {
                    left: parent.left
                    right: parent.right
                    rightMargin: root.vertical ? 0 : 46
                    verticalCenter: parent.verticalCenter
                }
                height: subtitleVisible ? 30 : 22
                readonly property bool subtitleVisible: root.height >= 32 && root.artist.length > 0
                ScrollingText {
                    id: titleLabel
                    width: parent.width
                    y: 1
                    height: labels.subtitleVisible ? 18 : 22
                    text: root.title
                    color: "white"
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.family: Appearance.font.family.main
                    backgroundColor: "black"
                    centered: false
                    scrollOnlyOnOverflow: true
                }
                StyledText {
                    id: artistLabel
                    visible: labels.subtitleVisible
                    width: parent.width
                    y: 14
                    height: 14
                    text: root.artist
                    color: "#a1a1a1"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
            }

            ScrollingText {
                visible: opacity > 0
                anchors.fill: parent
                opacity: root.specialMix * (1 - root.workspaceMix)
                text: root.displayedSpecialName
                color: root.mediaVisible ? root.visualizerColor : Appearance.colors.colPrimary
                backgroundColor: "black"
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    Item {
        id: waveform
        visible: root.mediaVisible
        anchors {
            right: root.vertical ? undefined : parent.right
            rightMargin: root.vertical ? 0 : 10
            horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            verticalCenter: root.vertical ? undefined : parent.verticalCenter
            bottom: root.vertical ? parent.bottom : undefined
            bottomMargin: root.vertical ? 10 : 0
        }
        width: 18
        height: root.vertical ? 22 : 18
        Repeater {
            model: 4
            Rectangle {
                required property int index
                readonly property real sample: root.visualizerPoints[Math.floor(index * root.visualizerPoints.length / 4)] ?? 0
                x: root.vertical ? (parent.width - width) / 2 : index * 5
                y: root.vertical ? index * 5 + 2 : (parent.height - height) / 2
                width: root.vertical ? (root.isPlaying ? Math.max(3, Math.min(18, sample / 1000 * 18)) : 3) : 3
                height: root.vertical ? 3 : (root.isPlaying ? Math.max(3, Math.min(18, sample / 1000 * 18)) : 3)
                radius: 1.5
                color: root.visualizerColor
                opacity: root.isPlaying ? 1 : 0.55
                Behavior on height {
                    NumberAnimation {
                        duration: 80
                    }
                }
                Behavior on width {
                    NumberAnimation {
                        duration: 80
                    }
                }
            }
        }
    }
}
