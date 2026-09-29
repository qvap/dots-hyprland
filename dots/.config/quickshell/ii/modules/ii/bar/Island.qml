pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.mediaControls

Item {
    id: root

    property bool vertical: Config.options.bar.vertical
    property bool expanded: false
    property bool collapsing: false
    property bool initialized: false
    readonly property var barWindow: root.QsWindow.window
    readonly property bool exposed: visible && (barWindow?.visible ?? false)
    readonly property MprisPlayer activePlayer: {
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase();
        return (preferred ? MprisController.players.find(p => (p.identity ?? "").toLowerCase().includes(preferred)
            || (p.desktopEntry ?? "").toLowerCase().includes(preferred)) : null) ?? MprisController.activePlayer;
    }
    readonly property color mediaAccent: playerLoader.item?.hasArtColors
        ? playerLoader.item.blendedColors.colPrimary : Appearance.colors.colPrimary
    readonly property var mediaColors: playerLoader.item?.blendedColors ?? Appearance.colors
    readonly property bool isPlaying: activePlayer?.isPlaying ?? false
    readonly property bool hasActivity: activePlayer !== null && activePlayer.playbackState !== MprisPlaybackState.Stopped
    readonly property bool mediaActivity: hasActivity
    readonly property bool specialActive: workspaces.workspaceModel.specialWorkspace != null
        && workspaces.workspaceModel.specialWorkspaceActive
    readonly property string specialName: workspaces.workspaceModel.specialWorkspaceName
    readonly property bool showActivity: mediaActivity || specialActive
    state: expanded && activePlayer !== null ? "expanded" : (showActivity ? "notif" : "idle")

    readonly property real compactHeight: Math.max(24, Appearance.sizes.barHeight - 8)
    readonly property real compactWidth: workspaces.implicitWidth + (mediaActivity ? 76 : 32)
    readonly property real compactLength: workspaces.implicitHeight + (mediaActivity ? 88 : 32)
    readonly property real verticalWidth: Appearance.sizes.baseVerticalBarWidth
        - (Config.options.bar.cornerStyle === 3 ? 6 : 0)
    Layout.fillHeight: !vertical
    Layout.fillWidth: vertical
    implicitWidth: vertical ? verticalWidth : Math.max(workspaces.implicitWidth, showActivity ? compactWidth : 0)
    implicitHeight: vertical ? (showActivity ? compactLength : workspaces.implicitHeight) : Appearance.sizes.barHeight
    Behavior on implicitWidth { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    readonly property bool showTrackDetails: mediaActivity && !workspacePreviewTimer.running
        && (barHover.hovered || trackPreviewTimer.running || dragging)
    readonly property bool showSpecial: specialActive && !showTrackDetails && !workspacePreviewTimer.running
    readonly property bool revealWorkspaces: !dragging && !showTrackDetails && !showSpecial
    property real activityVisibility: showActivity ? 1 : 0
    Behavior on activityVisibility {
        NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
    }
    HoverHandler { id: barHover }
    function showWorkspacePreview() {
        if (!initialized || !exposed || state === "idle") return;
        workspacePreviewTimer.restart();
        expanded = false;
    }
    Timer {
        id: workspacePreviewTimer
        interval: 750
    }
    Timer {
        id: trackPreviewTimer
        interval: 2000
    }
    function showTrackPreview() {
        if (initialized && exposed && mediaActivity) trackPreviewTimer.restart();
    }
    Connections {
        target: workspaces.workspaceModel
        function onActiveNumberChanged() { root.showWorkspacePreview(); }
    }
    Connections {
        target: root.activePlayer
        function onPostTrackChanged() { root.showTrackPreview(); }
        function onTrackTitleChanged() { root.showTrackPreview(); }
    }

    function refreshActivity() {
        if (!hasActivity) {
            expanded = false;
            cancelPull();
        }
    }
    onActivePlayerChanged: { refreshActivity(); showTrackPreview(); }
    onHasActivityChanged: refreshActivity()
    function registerWithBar() {
        if (!barWindow || typeof barWindow.islandItem === "undefined") return;
        if (exposed) barWindow.islandItem = root;
        else if (barWindow.islandItem === root) barWindow.islandItem = null;
    }
    Component.onCompleted: { initialized = true; refreshActivity(); registerWithBar(); }
    onBarWindowChanged: registerWithBar()
    onExposedChanged: {
        if (!exposed) { expanded = false; if (dragging) cancelPull(); }
        registerWithBar();
    }
    Workspaces {
        id: workspaces
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        vertical: root.vertical
        showSpecialIndicator: false
        switchOnPress: false
        enabled: !root.collapsing && (root.state === "idle" || root.revealWorkspaces || root.expansion > 0.9)
        opacity: root.showActivity ? Math.max(compactContent.workspaceMix * (1 - root.expansion), root.expansion) : 1
        readonly property real retreat: (1 - compactContent.workspaceMix) * (1 - root.expansion)
        scale: 1 - 0.08 * retreat
        layer.enabled: retreat > 0
        layer.smooth: true
        layer.effect: MultiEffect {
            brightness: -0.1 * workspaces.retreat
            blurEnabled: true
            blur: workspaces.retreat
            blurMax: 32
        }
        z: 2
    }
    // This area receives wheel events over both the workspaces and the pill.
    MouseArea {
        anchors.fill: parent
        z: 3
        enabled: root.exposed && !root.expanded
        acceptedButtons: root.activePlayer && root.state !== "idle" && !workspacePreviewTimer.running
            ? Qt.LeftButton : Qt.NoButton
        cursorShape: acceptedButtons === Qt.LeftButton ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.expanded = true
        onWheel: event => {
            if (event.angleDelta.y === 0) return;
            root.showWorkspacePreview();
            WM.switchWorkspaceRelative(event.angleDelta.y < 0 ? "next" : "prev");
            event.accepted = true;
        }
    }
    // Let short clicks finish; take over the pointer only after a drag begins.
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
    property bool dragging: false
    property real pullDistance: 0
    readonly property real pullThreshold: 70
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
            // Commit immediately; release is no longer needed to complete the gesture.
            dragging = false;
            expanded = true;
        } else expansion = pullDistance / pullThreshold * 0.12;
    }
    function cancelPull() { dragging = false; pullDistance = 0; expansion = 0; }

    // Freeze both endpoints before opening; bar layout and metadata cannot retarget a running morph.
    property rect compactBounds: Qt.rect(0, 0, 240, 32)
    property rect expandedBounds: Qt.rect(0, 0, 440, 160)
    // PlayerControl's regular popup keeps an elevation margin around its visible card.
    readonly property real playerWidth: Math.min(Appearance.sizes.mediaControlsWidth - 2 * Appearance.sizes.elevationMargin,
        (barWindow?.screen?.width ?? 440) - 16)
    readonly property real playerHeight: Math.min(Appearance.sizes.mediaControlsHeight - 2 * Appearance.sizes.elevationMargin,
        (barWindow?.screen?.height ?? 160) - 16)
    property real expansion: 0
    onExpansionChanged: if (collapsing && expansion === 0) collapsing = false
    Behavior on expansion {
        enabled: !root.dragging
        NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
    }
    function captureBounds() {
        if (!barWindow) return;
        const pos = root.mapToItem(barWindow.contentItem, surface.x, surface.y);
        const x = pos.x;
        const y = pos.y;
        compactBounds = Qt.rect(x, y, surface.width, surface.height);
        const cx = x + compactBounds.width / 2;
        const cy = y + compactBounds.height / 2;
        const targetX = vertical
            ? (Config.options.bar.bottom ? cx - Appearance.sizes.verticalBarWidth / 2 - 8 - playerWidth
                : cx + Appearance.sizes.verticalBarWidth / 2 + 8) : cx - playerWidth / 2;
        const targetY = vertical ? cy - playerHeight / 2
            : (Config.options.bar.bottom ? cy - Appearance.sizes.barHeight / 2 - 8 - playerHeight
                : cy + Appearance.sizes.barHeight / 2 + 8);
        expandedBounds = Qt.rect(Math.max(8, Math.min(barWindow.width - playerWidth - 8, targetX)),
            Math.max(8, Math.min(barWindow.height - playerHeight - 8, targetY)), playerWidth, playerHeight);
    }
    onExpandedChanged: {
        if (expanded) {
            collapsing = false;
            if (expansion === 0) captureBounds();
            if (playerLoader.status === Loader.Ready) expansion = 1;
        } else {
            collapsing = expansion > 0;
            expansion = 0;
        }
    }

    readonly property bool interacting: exposed && (barHover.hovered || dragging || expanded || expansion > 0 || revealWorkspaces)
    Component.onDestruction: {
        if (barWindow?.islandItem === root) barWindow.islandItem = null;
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
    function interpolate(from, to) { return from + (to - from) * expansion; }

    Item {
        id: overlay
        parent: root.barWindow?.islandOverlay ?? root
        anchors.fill: parent
        visible: root.exposed
    }
    ClippingRectangle {
        id: surface
        parent: root.expansion > 0 ? overlay : root
        x: root.expansion > 0 ? root.interpolate(root.compactBounds.x, root.expandedBounds.x) : (root.width - width) / 2
        y: root.expansion > 0 ? root.interpolate(root.compactBounds.y, root.expandedBounds.y) : (root.height - height) / 2
        width: root.expansion > 0 ? root.interpolate(root.compactBounds.width, root.expandedBounds.width)
            : (root.vertical ? Math.min(32, root.width) : root.compactWidth)
        height: root.expansion > 0 ? root.interpolate(root.compactBounds.height, root.expandedBounds.height)
            : (root.vertical ? root.height : root.compactHeight)
        Behavior on height {
            enabled: root.expansion === 0 && !root.vertical
            NumberAnimation { duration: 180; easing.type: Easing.InOutQuad }
        }
        radius: root.interpolate(root.compactHeight / 2, 24)
        color: "black"
        opacity: root.expansion > 0 ? 1 : root.activityVisibility
        visible: root.exposed && opacity > 0
        z: 1
        focus: root.expanded
        Keys.onEscapePressed: event => { root.expanded = false; event.accepted = true; }
        StyledRectangularShadow { parent: surface; target: surface; opacity: root.expansion; z: -1 }
        IslandContent {
            id: compactContent
            anchors.centerIn: parent
            width: root.expansion > 0 ? root.compactBounds.width : surface.width
            height: root.expansion > 0 ? root.compactBounds.height : surface.height
            opacity: Math.max(0, 1 - root.expansion * 3)
            workspaceVisible: root.revealWorkspaces && !root.collapsing
            player: root.activePlayer
            mediaVisible: root.mediaActivity
            trackVisible: root.showTrackDetails
            specialVisible: root.showSpecial
            specialName: root.specialName
            vertical: root.vertical
            barOnRight: Config.options.bar.bottom
            visualizerPoints: GlobalStates.visualizerPoints
            visualizerColor: root.mediaAccent
            layer.enabled: true
            layer.smooth: true
        }
        RippleButton {
            parent: root
            z: 4
            x: Math.round(surface.x + surface.width - 40 - width)
            y: Math.round(surface.y + (surface.height - height) / 2)
            implicitWidth: 40
            implicitHeight: 23
            visible: opacity > 0 && root.expansion === 0 && !root.vertical
            opacity: root.mediaActivity && barHover.hovered && !root.revealWorkspaces ? 1 : 0
            enabled: opacity > 0.95
            Behavior on opacity { NumberAnimation { duration: 150 } }
            buttonRadius: root.isPlaying ? Appearance.rounding.normal : 13
            colBackground: root.isPlaying ? root.mediaColors.colPrimary : root.mediaColors.colSecondaryContainer
            colBackgroundHover: root.isPlaying ? root.mediaColors.colPrimaryHover : root.mediaColors.colSecondaryContainerHover
            colRipple: root.isPlaying ? root.mediaColors.colPrimaryActive : root.mediaColors.colSecondaryContainerActive
            downAction: () => root.activePlayer?.togglePlaying()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: root.isPlaying ? "pause" : "play_arrow"
                iconSize: Appearance.font.pixelSize.large
                fill: 1
                color: root.isPlaying ? root.mediaColors.colOnPrimary : root.mediaColors.colOnSecondaryContainer
            }
        }

        // Prewarm fixed-size controls; only the pill contributes to the window's input mask.
        Loader {
            id: playerLoader
            anchors.centerIn: parent
            width: root.playerWidth
            height: root.playerHeight
            active: root.exposed && root.activePlayer !== null
            asynchronous: true
            onStatusChanged: if (status === Loader.Ready && root.expanded) root.expansion = 1
            visible: root.expansion > 0
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
}
