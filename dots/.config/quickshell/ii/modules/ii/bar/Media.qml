pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.common.models
import qs
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.modules.ii.mediaControls

Item {
    id: root

    property bool vertical: false
    property bool borderless: Config.options.bar.borderless
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    readonly property MprisPlayer activePlayer: {
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase();
        if (preferred.length === 0)
            return MprisController.activePlayer;
        const _ = MprisController.players.count;
        for (const p of MprisController.players) {
            if ((p.identity ?? "").toLowerCase().includes(preferred) || (p.desktopEntry ?? "").toLowerCase().includes(preferred))
                return p;
        }
        return MprisController.activePlayer;
    }

    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")

    property var artUrl: activePlayer?.trackArtUrl ?? ""
    property string trackTitle: activePlayer?.trackTitle ?? ""
    property string trackArtist: activePlayer?.trackArtist ?? ""
    property bool isPlaying: activePlayer?.isPlaying ?? false
    property bool hasTrack: trackTitle.length > 0
    readonly property bool hasActivity: activePlayer !== null && activePlayer.playbackState !== MprisPlaybackState.Stopped
    property bool expanded: false
    property bool collapsing: false
    property bool dragging: false
    property real pullDistance: 0
    readonly property real pullThreshold: 70
    readonly property var barWindow: root.QsWindow.window
    property var barGroup: null
    function registerWithGroup() {
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
    readonly property bool exposed: visible && (barWindow?.visible ?? false)
    readonly property bool interacting: exposed && (expanded || dragging || expansion > 0)
    readonly property real playerWidth: Math.min(Appearance.sizes.mediaControlsWidth - 2 * Appearance.sizes.elevationMargin,
        (barWindow?.screen?.width ?? 440) - 16)
    readonly property real playerHeight: Math.min(Appearance.sizes.mediaControlsHeight - 2 * Appearance.sizes.elevationMargin,
        (barWindow?.screen?.height ?? 160) - 16)
    property rect compactBounds: Qt.rect(0, 0, 240, 32)
    property rect expandedBounds: Qt.rect(0, 0, 440, 160)
    property real expansion: 0
    onExpansionChanged: if (collapsing && expansion === 0) collapsing = false
    Behavior on expansion {
        enabled: !root.dragging
        NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
    }
    function interpolate(from, to) { return from + (to - from) * expansion; }
    function captureBounds() {
        if (!barWindow) return;
        const source = groupBackground ?? root;
        const pos = source.mapToItem(barWindow.contentItem, 0, 0);
        compactBounds = Qt.rect(pos.x, pos.y, source.width, source.height);
        const cx = pos.x + source.width / 2;
        const cy = pos.y + source.height / 2;
        const targetX = root.vertical
            ? (Config.options.bar.bottom ? cx - Appearance.sizes.verticalBarWidth / 2 - 8 - playerWidth
                : cx + Appearance.sizes.verticalBarWidth / 2 + 8) : cx - playerWidth / 2;
        const targetY = root.vertical ? cy - playerHeight / 2
            : (Config.options.bar.bottom ? cy - Appearance.sizes.barHeight / 2 - 8 - playerHeight
                : cy + Appearance.sizes.barHeight / 2 + 8);
        expandedBounds = Qt.rect(Math.max(8, Math.min(barWindow.width - playerWidth - 8, targetX)),
            Math.max(8, Math.min(barWindow.height - playerHeight - 8, targetY)), playerWidth, playerHeight);
    }
    function beginPull() {
        if (!activePlayer) return;
        captureBounds();
        dragging = true;
        pullDistance = 0;
        expansion = 0;
    }
    function updatePull(distance) {
        if (!dragging) return;
        pullDistance = Math.max(0, distance);
        if (pullDistance >= pullThreshold) {
            dragging = false;
            expanded = true;
        } else expansion = pullDistance / pullThreshold * 0.12;
    }
    function cancelPull() { dragging = false; pullDistance = 0; expansion = 0; }
    onExpandedChanged: {
        if (expanded) {
            collapsing = false;
            if (barWindow?.islandItem) barWindow.islandItem.expanded = false;
            GlobalStates.mediaControlsOpen = false;
            if (expansion === 0) captureBounds();
            if (playerLoader.status === Loader.Ready) expansion = 1;
        } else {
            collapsing = expansion > 0;
            expansion = 0;
        }
    }
    onHasActivityChanged: if (!hasActivity) { expanded = false; cancelPull(); }
    function registerWithBar() {
        if (!barWindow || typeof barWindow.mediaItem === "undefined") return;
        if (exposed) barWindow.mediaItem = root;
        else if (barWindow.mediaItem === root) barWindow.mediaItem = null;
    }
    Component.onCompleted: { registerWithBar(); registerWithGroup(); }
    Component.onDestruction: {
        if (barWindow?.mediaItem === root) barWindow.mediaItem = null;
        if (barGroup?.morphingMedia === root) barGroup.morphingMedia = null;
    }
    onBarWindowChanged: registerWithBar()
    onParentChanged: registerWithGroup()
    onExposedChanged: {
        if (!exposed) { expanded = false; if (dragging) cancelPull(); }
        registerWithBar();
    }
    readonly property Item pullSurface: dragging || (expanded && pullDistance >= pullThreshold && expansion < 1)
        ? pullCorridor : null
    Item {
        id: pullCorridor
        parent: root.barWindow?.islandOverlay ?? root
        x: root.compactBounds.x - (root.vertical && Config.options.bar.bottom ? root.pullThreshold : 0)
        y: root.compactBounds.y - (!root.vertical && Config.options.bar.bottom ? root.pullThreshold : 0)
        width: root.compactBounds.width + (root.vertical ? root.pullThreshold : 0)
        height: root.compactBounds.height + (!root.vertical ? root.pullThreshold : 0)
    }
    readonly property Item expandedSurface: exposed && expansion > 0 ? surface : null
    Item {
        id: overlay
        parent: root.barWindow?.islandOverlay ?? root
        anchors.fill: parent
        visible: root.exposed
    }
    ClippingRectangle {
        id: surface
        parent: overlay
        x: root.interpolate(root.compactBounds.x, root.expandedBounds.x)
        y: root.interpolate(root.compactBounds.y, root.expandedBounds.y)
        width: root.interpolate(root.compactBounds.width, root.expandedBounds.width)
        height: root.interpolate(root.compactBounds.height, root.expandedBounds.height)
        radius: root.interpolate(Math.min(root.compactBounds.width, root.compactBounds.height) / 2, 24)
        color: {
            const base = root.groupBackground?.color ?? (root.isMaterial ? root.materialPillColor : Appearance.colors.colLayer0);
            return ColorUtils.applyAlpha(base, base.a + (1 - base.a) * Math.min(1, root.expansion * 3));
        }
        visible: root.exposed && root.expansion > 0
        focus: root.expanded
        Keys.onEscapePressed: event => { root.expanded = false; event.accepted = true; }
        StyledRectangularShadow { parent: surface; target: surface; opacity: root.expansion; z: -1 }
        Loader {
            id: playerLoader
            anchors.centerIn: parent
            width: root.playerWidth
            height: root.playerHeight
            active: root.exposed && root.activePlayer !== null
            asynchronous: true
            onStatusChanged: if (status === Loader.Ready && root.expanded) root.expansion = 1
            opacity: Math.max(0, (root.expansion - 0.25) / 0.75)
            enabled: root.expanded && root.expansion > 0.95
            z: 1
            layer.enabled: true
            layer.smooth: true
            sourceComponent: PlayerControl {
                player: root.activePlayer
                visualizerPoints: GlobalStates.visualizerPoints
                animateTrackChanges: false
                backgroundMargin: 0
                radius: 24
            }
        }
    }

    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`
    property bool artDownloaded: false

    property string displayedArtFilePath: {
        if (!root.artDownloaded)
            return "";
        if (root.artUrl.startsWith("file://"))
            return root.artUrl;
        return Qt.resolvedUrl(artFilePath);
    }

    readonly property color artDominantColor: ColorUtils.mix(colorQuantizer.colors[0] ?? Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.8)
    readonly property QtObject blendedColors: root.isMaterial && root.hasTrack && root.displayedArtFilePath !== "" && colorQuantizer.colors.length > 0 ? adaptedColors : Appearance.colors

    readonly property color materialPillColor: root.hasTrack ? root.blendedColors.colLayer0 : Appearance.colors.colSecondaryContainer

    ColorQuantizer {
        id: colorQuantizer
        source: root.isMaterial && root.hasTrack ? root.displayedArtFilePath : ""
        depth: 0
        rescaleSize: 1
    }

    AdaptedMaterialScheme {
        id: adaptedColors
        color: root.artDominantColor
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length === 0) {
            root.artDownloaded = false;
            return;
        }
        if (root.artUrl.startsWith("file://")) {
            root.artDownloaded = true;
            return;
        }
        artDownloader.targetFile = root.artUrl;
        artDownloader.artFilePath = root.artFilePath;
        root.artDownloaded = false;
        artDownloader.running = true;
    }

    function updateWidgetPosition() {
        if (root.width <= 0)
            return;

        let rootItem = root.Window?.contentItem ?? null;
        let pos = rootItem ? root.mapToItem(rootItem, 0, 0) : Qt.point(0, 0);

        if (pos.x > 0 || pos.y > 0) {
            GlobalStates.mediaWidgetX = pos.x;
            GlobalStates.mediaWidgetY = pos.y;
            GlobalStates.mediaWidgetWidth = root.width;
            GlobalStates.mediaWidgetHeight = root.height;
        }
    }

    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen) {
                root.updateWidgetPosition();
            }
        }
    }

    Process {
        id: artDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: ["bash", "-c", `[ -f ${artFilePath} ] || curl -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: {
            root.artDownloaded = true;
        }
    }

    Layout.fillHeight: true
    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (isMaterial ? materialRow.implicitWidth : Math.max(Config.options.bar.media.minWidth, Math.min(rowLayout.implicitWidth + 8, Config.options.bar.media.maxWidth)))
    implicitHeight: vertical ? (isMaterial ? 32 : mediaCircProg.implicitHeight + 12) : Appearance.sizes.barHeight

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
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
    DragHandler {
        id: pullGesture
        target: null
        enabled: root.activePlayer !== null && !root.expanded && (root.expansion === 0 || root.dragging)
        acceptedButtons: Qt.LeftButton
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        xAxis.enabled: root.vertical
        yAxis.enabled: !root.vertical
        onActiveChanged: {
            if (active) root.beginPull();
            else if (root.dragging) root.cancelPull();
        }
        onTranslationChanged: {
            const distance = root.vertical ? activeTranslation.x : activeTranslation.y;
            if (active) root.updatePull(distance * (Config.options.bar.bottom ? -1 : 1));
        }
        onCanceled: if (root.dragging) root.cancelPull()
    }

    Item {
        id: compactContent
        parent: root.expansion > 0 ? surface : root
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
        sourceComponent: ClippedFilledCircularProgress {
            implicitSize: 20
            lineWidth: Appearance.rounding.unsharpen
            value: root.activePlayer?.position / root.activePlayer?.length
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
            ClippedFilledCircularProgress {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 3
                implicitSize: 20
                lineWidth: Appearance.rounding.unsharpen
                value: root.activePlayer?.position / root.activePlayer?.length
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

            // No platyer
            Loader {
                active: !root.hasTrack
                visible: active
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: RowLayout {
                    spacing: 6

                    // Avatar
                    Rectangle {
                        id: avatarRect
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer
                        Layout.alignment: Qt.AlignVCenter

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: avatarRect.width
                                height: avatarRect.height
                                radius: avatarRect.radius
                            }
                        }

                        Image {
                            id: avatarImage
                            anchors.fill: parent
                            source: Config.options.profile.avatarPath !== "" ? "file://" + Config.options.profile.avatarPicture : "file:///home/" + (Quickshell.env("USER") ?? "user") + "/.face"
                            sourceSize.width: avatarRect.width * 2
                            sourceSize.height: avatarRect.height * 2
                            fillMode: Image.PreserveAspectCrop
                            onStatusChanged: {
                                if (status === Image.Error)
                                    visible = false;
                            }
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
                    Rectangle {
                        id: artRect
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: root.blendedColors.colSecondaryContainer
                        Layout.alignment: Qt.AlignVCenter

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: artRect.width
                                height: artRect.height
                                radius: artRect.radius
                            }
                        }

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
                            text: StringUtils.cleanMusicTitle(root.trackTitle) || Translation.tr("No media")
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.family: Appearance.font.family.main
                            color: root.blendedColors.colOnLayer0
                            backgroundColor: ColorUtils.applyAlpha(root.blendedColors.colLayer0, 1)
                            centered: false
                            scrollOnlyOnOverflow: true
                        }
                    }

                    // Play/Pause
                    RippleButton {
                        implicitWidth: 40
                        implicitHeight: 23
                        buttonRadius: root.isPlaying ? Appearance.rounding.normal : 13
                        colBackground: root.isPlaying ? root.blendedColors.colPrimary : root.blendedColors.colSecondaryContainer
                        colBackgroundHover: root.isPlaying ? root.blendedColors.colPrimaryHover : root.blendedColors.colSecondaryContainerHover
                        colRipple: root.isPlaying ? root.blendedColors.colPrimaryActive : root.blendedColors.colSecondaryContainerActive
                        downAction: () => root.activePlayer?.togglePlaying()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: root.isPlaying ? "pause" : "play_arrow"
                            iconSize: Appearance.font.pixelSize.large
                            fill: 1
                            color: root.isPlaying ? root.blendedColors.colOnPrimary : root.blendedColors.colOnSecondaryContainer
                        }
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
