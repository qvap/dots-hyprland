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
    property string artSource: ""
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
    property color surfaceColor: "black"
    property color textColor: "white"
    property color subtextColor: "#a1a1a1"
    property color artPlaceholderColor: "#202020"

    // Art at the start and the waveform at the end, each `edgeInset` from the edge
    readonly property real edgeInset: 10
    readonly property real artSize: 22
    readonly property real waveformLength: 18
    readonly property real waveformExtent: vertical ? 22 : waveformLength
    readonly property real gap: vertical ? 12 : 8
    // Where the middle slot starts and how much of the length the chrome takes
    readonly property real middleStart: mediaVisible ? edgeInset + artSize + gap : 16
    readonly property real chromeLength: mediaVisible ? middleStart + gap + waveformExtent + edgeInset : 32
    readonly property real maxSample: 1000

    ClippingRectangle {
        visible: root.mediaVisible
        x: root.vertical ? (parent.width - width) / 2 : root.edgeInset
        y: root.vertical ? root.edgeInset : (parent.height - height) / 2
        width: root.artSize
        height: root.artSize
        radius: 6
        color: root.artPlaceholderColor
        Image {
            id: art
            anchors.fill: parent
            source: root.artSource
            sourceSize: Qt.size(root.artSize * 2, root.artSize * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            text: "music_note"
            iconSize: 17
            color: root.textColor
        }
    }

    Item {
        id: middle
        x: root.vertical ? 0 : root.middleStart
        y: root.vertical ? root.middleStart : 0
        width: root.vertical ? root.width : Math.max(0, root.width - root.chromeLength)
        height: root.vertical ? Math.max(0, root.height - root.chromeLength) : root.height

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
                    color: root.textColor
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.family: Appearance.font.family.main
                    backgroundColor: root.surfaceColor
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
                    color: root.subtextColor
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
                backgroundColor: root.surfaceColor
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
            rightMargin: root.vertical ? 0 : root.edgeInset
            horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
            verticalCenter: root.vertical ? undefined : parent.verticalCenter
            bottom: root.vertical ? parent.bottom : undefined
            bottomMargin: root.vertical ? root.edgeInset : 0
        }
        width: root.waveformLength
        height: root.waveformExtent
        Repeater {
            model: 4
            Rectangle {
                required property int index
                readonly property real sample: root.visualizerPoints[Math.floor(index * root.visualizerPoints.length / 4)] ?? 0
                readonly property real level: root.isPlaying
                    ? Math.max(3, Math.min(root.waveformLength, sample / root.maxSample * root.waveformLength)) : 3
                x: root.vertical ? (parent.width - width) / 2 : index * 5
                y: root.vertical ? index * 5 + 2 : (parent.height - height) / 2
                width: root.vertical ? level : 3
                height: root.vertical ? 3 : level
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
