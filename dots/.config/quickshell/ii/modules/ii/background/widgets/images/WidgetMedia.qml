pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import qs.modules.common.widgets

// Keep image-widget masks and sizing shared across still images, GIFs and video.
Item {
    id: root

    property url source
    property int fillMode: Image.PreserveAspectCrop
    property size sourceSize: Qt.size(-1, -1)
    property bool mipmap: false
    readonly property string extension: root.source.toString().split(/[?#]/)[0].split(".").pop().toLowerCase()
    readonly property bool isVideo: root.extension === "mp4"
    readonly property int status: mediaLoader.media?.status ?? Image.Null

    clip: true

    Loader {
        id: mediaLoader
        readonly property var media: mediaLoader.item
        anchors.fill: parent
        sourceComponent: root.source.toString() === "" ? null
            : root.isVideo ? videoComponent
            : root.extension === "gif" ? animatedComponent : imageComponent
    }

    Component {
        id: imageComponent
        StyledImage {
            source: root.source
            fillMode: root.fillMode
            sourceSize: root.sourceSize
            cache: false
            antialiasing: true
            smooth: root.smooth
            mipmap: root.mipmap
        }
    }

    Component {
        id: animatedComponent
        AnimatedImage {
            source: root.source
            fillMode: root.fillMode
            sourceSize: root.sourceSize
            asynchronous: true
            cache: false
            playing: true
            paused: !root.visible
            antialiasing: true
            smooth: root.smooth
            mipmap: root.mipmap
        }
    }

    Component {
        id: videoComponent
        VideoOutput {
            id: video
            readonly property int status: player.error !== MediaPlayer.NoError ? Image.Error
                : player.hasVideo ? Image.Ready : Image.Loading
            fillMode: root.fillMode === Image.PreserveAspectFit ? VideoOutput.PreserveAspectFit
                : root.fillMode === Image.Stretch ? VideoOutput.Stretch : VideoOutput.PreserveAspectCrop

            MediaPlayer {
                id: player
                source: root.source
                videoOutput: video
                autoPlay: root.visible
                loops: MediaPlayer.Infinite
                // Desktop decorations never play sound.
                audioOutput: null
            }

            Connections {
                target: root
                function onVisibleChanged() {
                    if (root.visible) player.play()
                    else player.pause()
                }
            }
        }
    }
}
