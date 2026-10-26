pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.common.models
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets

BarMediaMorph {
    id: root

    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3

    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")

    readonly property string trackTitle: activePlayer?.trackTitle ?? ""
    readonly property string trackArtist: activePlayer?.trackArtist ?? ""
    readonly property bool isPlaying: activePlayer?.isPlaying ?? false
    readonly property bool hasTrack: trackTitle.length > 0
    property var barGroup: null
    function registerWithGroup() {
        if (barGroup?.morphingMedia === root) barGroup.morphingMedia = null;
        barGroup = null;
        let item = root.parent;
        while (item) {
            if (typeof item.morphingMedia !== "undefined") {
                barGroup = item;
                item.morphingMedia = root;
                return;
            }
            item = item.parent;
        }
    }
    readonly property Item groupBackground: barGroup?.visualBackground ?? null
    Component.onCompleted: registerWithGroup()
    Component.onDestruction: if (barGroup?.morphingMedia === root) barGroup.morphingMedia = null
    onParentChanged: registerWithGroup()

    boundsSource: groupBackground ?? root
    surfaceColor: {
        const base = groupBackground?.color ?? (isMaterial ? materialPillColor : Appearance.colors.colLayer0);
        return ColorUtils.applyAlpha(base, base.a + (1 - base.a) * Math.min(1, expansion * 3));
    }

    // The player card downloads the art and extracts its colors
    readonly property string displayedArtFilePath: playerCard?.displayedArtFilePath ?? ""
    readonly property QtObject blendedColors: isMaterial && hasTrack && displayedArtFilePath !== "" && playerCard.hasArtColors
        ? playerCard.blendedColors : Appearance.colors

    readonly property color materialPillColor: root.hasTrack ? root.blendedColors.colLayer0 : Appearance.colors.colSecondaryContainer

    function updateWidgetPosition() {
        if (root.width <= 0)
            return;

        const rootItem = barWindow?.contentItem ?? null;
        const pos = rootItem ? root.mapToItem(rootItem, 0, 0) : Qt.point(0, 0);

        if (pos.x <= 0 && pos.y <= 0) return;
        GlobalStates.mediaWidgetX = pos.x;
        GlobalStates.mediaWidgetY = pos.y;
        GlobalStates.mediaWidgetWidth = root.width;
        GlobalStates.mediaWidgetHeight = root.height;
    }

    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen) {
                root.updateWidgetPosition();
            }
        }
    }

    readonly property real trackProgress: activePlayer && activePlayer.length > 0
        ? Math.max(0, Math.min(1, activePlayer.position / activePlayer.length)) : 0

    component PlaybackProgress: ClippedFilledCircularProgress {
        implicitSize: 20
        lineWidth: Appearance.rounding.unsharpen
        value: root.trackProgress
        colPrimary: Appearance.colors.colOnSecondaryContainer
        enableAnimation: false
        Item {
            anchors.centerIn: parent
            width: 20
            height: 20
            MaterialSymbol {
                anchors.centerIn: parent
                fill: 1
                text: root.activePlayer?.isPlaying ? "pause" : "music_note"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3onSecondaryContainer
            }
        }
    }

    Layout.fillHeight: true
    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (isMaterial ? materialRow.implicitWidth : Math.max(Config.options.bar.media.minWidth, Math.min(rowLayout.implicitWidth + 8, Config.options.bar.media.maxWidth)))
    implicitHeight: vertical ? (isMaterial ? 32 : mediaCircProg.implicitHeight + 12) : Appearance.sizes.barHeight

    Timer {
        running: root.exposed && !root.isMaterial && root.expansion === 0 && root.isPlaying
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: root.activePlayer?.positionChanged()
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.exposed && !root.expanded && root.expansion === 0
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        onPressed: event => {
            if (event.button === Qt.MiddleButton)
                activePlayer?.togglePlaying();
            else if (event.button === Qt.BackButton)
                activePlayer?.previous();
            else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton)
                activePlayer?.next();
        }
        onClicked: event => {
            if (event.button === Qt.LeftButton && root.activePlayer) root.expanded = true;
        }
        onWheel: event => {
            if (event.angleDelta.y === 0) return;
            WM.switchWorkspaceRelative(event.angleDelta.y < 0 ? "next" : "prev");
            event.accepted = true;
        }
    }
    Item {
        id: compactContent
        parent: root.expansion > 0 ? root.surface.contentItem : root
        anchors.centerIn: parent
        width: root.expansion > 0 ? root.compactBounds.width : root.width
        height: root.expansion > 0 ? root.compactBounds.height : root.height
        opacity: Math.max(0, 1 - root.expansion * 3)
        enabled: root.expansion === 0
        layer.enabled: root.expansion > 0
        layer.smooth: true

        // Vertical default
        Loader {
            id: mediaCircProg
            active: root.vertical && !root.isMaterial
            visible: active
            anchors.centerIn: parent
            sourceComponent: PlaybackProgress {}
        }

        // Vertical Material
        Rectangle {
            visible: root.vertical && root.isMaterial
            anchors.centerIn: parent
            color: root.blendedColors.colSecondaryContainer
            radius: Appearance.rounding.full
            implicitWidth: 32
            implicitHeight: 32

            MaterialSymbol {
                anchors.centerIn: parent
                fill: 1
                text: root.activePlayer?.isPlaying ? "pause" : "music_note"
                iconSize: Appearance.font.pixelSize.normal
                color: root.blendedColors.colOnSecondaryContainer
            }
        }

        // Horizontal default
        Loader {
            id: rowLayout
            active: !root.vertical && !root.isMaterial
            visible: active
            anchors.fill: parent
            sourceComponent: RowLayout {
                spacing: 4
                PlaybackProgress {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 3
                }
                ScrollingText {
                    visible: Config.options.bar.verbose
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    Layout.rightMargin: 0
                    color: Appearance.colors.colOnLayer1
                    font.family: Appearance.font.family.main
                    backgroundColor: ColorUtils.applyAlpha(root.groupBackground?.color ?? Appearance.colors.colLayer0, 1)
                    scrollOnlyOnOverflow: true
                    text: Config.options.bar.media.onlyTitle ? root.cleanedTitle : `${root.cleanedTitle}${root.activePlayer?.trackArtist ? ' • ' + root.activePlayer.trackArtist : ''}`
                }
            }
        }

        // Horizontal Material
        Loader {
            id: materialRow
            active: !root.vertical && root.isMaterial
            visible: active
            anchors.centerIn: parent
            sourceComponent: RowLayout {
                id: innerRow
                anchors.centerIn: parent
                spacing: 6

                // Profile fallback
                Loader {
                    active: !root.hasTrack
                    visible: active
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: RowLayout {
                        spacing: 6

                        // Avatar
                        ClippingRectangle {
                            id: avatarRect
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colPrimaryContainer
                            Layout.alignment: Qt.AlignVCenter

                            Image {
                                id: avatarImage
                                anchors.fill: parent
                                source: "file://" + (Config.options.profile.avatarPicture || `${FileUtils.trimFileProtocol(Directories.home)}/.face`)
                                sourceSize.width: avatarRect.width * 2
                                sourceSize.height: avatarRect.height * 2
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "account_circle"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnPrimaryContainer
                                visible: avatarImage.status === Image.Error || avatarImage.status === Image.Null
                            }
                        }

                        ColumnLayout {
                            spacing: -3
                            Layout.alignment: Qt.AlignVCenter
                            Layout.topMargin: -2

                            StyledText {
                                text: Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSecondaryContainer
                                elide: Text.ElideRight
                                Layout.maximumWidth: 120
                            }

                            StyledText {
                                id: distroLabel
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSecondaryContainer
                                opacity: 0.7
                                elide: Text.ElideRight
                                Layout.rightMargin: 8
                                Layout.maximumWidth: 120
                                text: SystemInfo.distroName
                            }
                        }
                    }
                }

                // Player
                Loader {
                    active: root.hasTrack
                    visible: active
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: RowLayout {
                        spacing: 6

                        // Art
                        ClippingRectangle {
                            id: artRect
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: Appearance.rounding.full
                            color: root.blendedColors.colSecondaryContainer
                            Layout.alignment: Qt.AlignVCenter

                            StyledImage {
                                anchors.fill: parent
                                source: root.displayedArtFilePath
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                                antialiasing: true
                                sourceSize.width: artRect.width
                                sourceSize.height: artRect.height
                                visible: root.displayedArtFilePath !== ""
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                fill: 1
                                text: "music_note"
                                iconSize: Appearance.font.pixelSize.normal
                                color: root.blendedColors.colOnSecondaryContainer
                                visible: root.displayedArtFilePath === ""
                            }
                        }

                        // Title + Artist
                        ColumnLayout {
                            spacing: -4
                            Layout.alignment: Qt.AlignVCenter
                            Layout.topMargin: Config.options.bar.media.onlyTitle ? 0 : 2

                            StyledText {
                                id: artistText
                                text: root.trackArtist
                                visible: !Config.options.bar.media.onlyTitle
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.blendedColors.colSubtext
                                elide: Text.ElideRight
                                Layout.maximumWidth: 120
                                Behavior on text {
                                    SequentialAnimation {
                                        NumberAnimation {
                                            target: artistText
                                            property: "x"
                                            to: -artistText.width
                                            duration: 150
                                            easing.type: Easing.InQuad
                                        }
                                        PropertyAction {
                                            target: artistText
                                            property: "text"
                                        }
                                        NumberAnimation {
                                            target: artistText
                                            property: "x"
                                            from: artistText.width
                                            to: 0
                                            duration: 150
                                            easing.type: Easing.OutQuad
                                        }
                                    }
                                }
                            }
                            ScrollingText {
                                Layout.topMargin: (!root.activePlayer || root.trackArtist.length === 0) ? -13 : 0
                                Layout.maximumWidth: 120
                                Layout.preferredWidth: Math.min(120, implicitWidth)
                                Layout.preferredHeight: implicitHeight
                                text: root.cleanedTitle
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                font.family: Appearance.font.family.main
                                color: root.blendedColors.colOnLayer0
                                backgroundColor: ColorUtils.applyAlpha(root.blendedColors.colLayer0, 1)
                                centered: false
                                scrollOnlyOnOverflow: true
                            }
                        }

                        // Play/Pause
                        BarMediaPlayButton {
                            player: root.activePlayer
                            colors: root.blendedColors
                        }

                        // Next
                        RippleButton {
                            implicitWidth: 26
                            implicitHeight: 26
                            Layout.leftMargin: -4
                            buttonRadius: 13
                            colBackground: "transparent"
                            colBackgroundHover: root.blendedColors.colSecondaryContainerHover
                            colRipple: root.blendedColors.colSecondaryContainerActive
                            downAction: () => root.activePlayer?.next()
                            altAction: () => root.activePlayer?.previous()
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "skip_next"
                                iconSize: Appearance.font.pixelSize.large
                                fill: 1
                                color: root.blendedColors.colOnSecondaryContainer
                            }
                        }
                    }
                }
            }
        }
    }
}
