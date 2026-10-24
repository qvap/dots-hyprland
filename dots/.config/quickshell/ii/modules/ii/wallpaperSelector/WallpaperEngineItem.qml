import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

MouseArea {
    id: root
    required property var itemData
    readonly property bool downloaded: WallpaperEngine.isDownloaded(itemData.id)
    readonly property bool downloading: WallpaperEngine.currentDownload === itemData.id
    readonly property bool queued: WallpaperEngine.queue.includes(itemData.id)
    readonly property bool busy: root.downloading || root.queued

    property alias colBackground: background.color
    property alias colText: titleText.color
    property alias margins: background.anchors.margins
    property alias padding: columnLayout.anchors.margins
    margins: Appearance.sizes.wallpaperSelectorItemMargins
    padding: Appearance.sizes.wallpaperSelectorItemPadding

    signal activated()
    signal cancelRequested()

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: event => {
        if (event.button === Qt.RightButton && root.busy) root.cancelRequested();
        else if (event.button === Qt.LeftButton) root.activated();
    }

    function formatSize(bytes) {
        if (bytes >= 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} GB`;
        return `${Math.round(bytes / 1024 / 1024)} MB`;
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Appearance.rounding.normal
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            id: columnLayout
            anchors.fill: parent
            spacing: 4

            Item {
                id: previewContainer
                Layout.fillHeight: true
                Layout.fillWidth: true

                StyledRectangularShadow {
                    target: previewImage
                    visible: previewImage.status === Image.Ready
                    radius: Appearance.rounding.small
                }

                // Previews are often GIFs. Image decodes only the first frame: AnimatedImage
                // (QMovie) on these remote GIFs recursed until the shell crashed
                Image {
                    id: previewImage
                    anchors.fill: parent
                    source: root.itemData.previewUrl
                    sourceSize.width: width * 2
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectCrop

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: previewContainer.width
                            height: previewContainer.height
                            radius: Appearance.rounding.small
                        }
                    }
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    implicitSize: 32
                    visible: previewImage.status === Image.Loading
                    loading: visible
                }

                Row {
                    anchors {
                        top: parent.top
                        right: parent.right
                        margins: 6
                    }
                    spacing: 4

                    Repeater {
                        model: [root.itemData.resolution, root.formatSize(root.itemData.fileSize)].filter(text => text.length > 0)
                        delegate: Rectangle {
                            required property string modelData
                            implicitWidth: badgeText.implicitWidth + 10
                            implicitHeight: badgeText.implicitHeight + 4
                            radius: height / 2
                            color: Appearance.colors.colScrim
                            StyledText {
                                id: badgeText
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: "white"
                                text: parent.modelData
                            }
                        }
                    }
                }

                Rectangle {
                    visible: root.downloaded || root.busy
                    anchors {
                        top: parent.top
                        left: parent.left
                        margins: 6
                    }
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: height / 2
                    color: root.downloaded ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.downloaded ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                        text: root.downloaded ? "download_done" : root.downloading ? "downloading" : "schedule"
                    }
                }

                StyledProgressBar {
                    visible: root.downloading && WallpaperEngine.downloadStatus === "downloading"
                    value: WallpaperEngine.downloadProgress
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        margins: 8
                    }
                }
                StyledIndeterminateProgressBar {
                    visible: root.downloading && WallpaperEngine.downloadStatus !== "downloading"
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        margins: 8
                    }
                }
            }

            StyledText {
                id: titleText
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10

                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                text: {
                    if (!root.downloading) return root.itemData.title;
                    switch (WallpaperEngine.downloadStatus) {
                    case "login": return Translation.tr("Logging in to Steam...");
                    case "confirm": return Translation.tr("Confirm in the Steam app");
                    case "copying": return Translation.tr("Copying...");
                    default: return Translation.tr("Downloading %1%").arg(Math.round(WallpaperEngine.downloadProgress * 100));
                    }
                }
            }
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.containsMouse
        text: root.itemData.title + (root.busy ? "\n" + Translation.tr("Right-click to cancel") : "")
    }
}
