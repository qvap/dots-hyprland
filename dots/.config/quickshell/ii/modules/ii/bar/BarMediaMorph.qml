pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "BarMediaUtils.js" as MediaUtils

// A bar widget that morphs into the media player when clicked or pulled from
// the bar. Subclasses provide the compact look; the surface is the morphing pill.
Item {
    id: root

    property bool vertical: false
    readonly property MprisPlayer activePlayer: MediaUtils.selectPlayer(
        MprisController.players, MprisController.activePlayer, Config.options.bar.media.preferredPlayer)
    readonly property bool hasActivity: activePlayer !== null && activePlayer.playbackState !== MprisPlaybackState.Stopped
    // The prewarmed player card; it also downloads the art and extracts its colors.
    readonly property Item playerCard: playerLoader.item

    property bool expanded: false
    property bool collapsing: false
    property bool dragging: false
    property real pullDistance: 0
    readonly property real pullThreshold: 70
    property real expansion: 0
    Behavior on expansion {
        enabled: !root.dragging
        NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
    }

    readonly property var barWindow: root.QsWindow.window
    readonly property BarMorphRegistry registry: barWindow?.morphRegistry ?? null
    readonly property bool exposed: visible && (barWindow?.visible ?? false)
    // Keeps an auto-hiding bar on screen
    property bool holdsBar: false
    readonly property bool interacting: exposed && (holdsBar || expanded || dragging || expansion > 0)

    // What the morph starts from; mapped into the window when it begins
    property Item boundsSource: root
    // The pill in its resting state, centered in the widget
    property real idleSurfaceWidth: root.width
    property real idleSurfaceHeight: root.height
    property real idleSurfaceOpacity: 0
    property bool animateIdleSurfaceHeight: false
    property color surfaceColor: Appearance.colors.colLayer0
    property alias surface: surface

    // PlayerControl's regular popup keeps an elevation margin around its visible card.
    readonly property real playerWidth: Math.min(Appearance.sizes.mediaControlsWidth - 2 * Appearance.sizes.elevationMargin,
        (barWindow?.screen?.width ?? 440) - 16)
    readonly property real playerHeight: Math.min(Appearance.sizes.mediaControlsHeight - 2 * Appearance.sizes.elevationMargin,
        (barWindow?.screen?.height ?? 160) - 16)
    // Both endpoints are frozen before opening; bar layout and metadata cannot retarget a running morph.
    property rect compactBounds: Qt.rect(0, 0, 240, 32)
    property rect expandedBounds: Qt.rect(0, 0, 440, 160)

    readonly property Item pullSurface: dragging || (expanded && pullDistance >= pullThreshold && expansion < 1)
        ? pullCorridor : null
    readonly property Item expandedSurface: exposed && expansion > 0 ? surface : null

    function interpolate(from, to) { return from + (to - from) * expansion; }

    function captureBounds() {
        if (!barWindow) return;
        const pos = boundsSource.mapToItem(barWindow.contentItem, 0, 0);
        compactBounds = Qt.rect(pos.x, pos.y, boundsSource.width, boundsSource.height);
        expandedBounds = MediaUtils.expandedBounds(compactBounds, playerWidth, playerHeight,
            barWindow.width, barWindow.height, vertical, Config.options.bar.bottom,
            Appearance.sizes.verticalBarWidth, Appearance.sizes.barHeight);
    }

    function cancelPull() { pullGesture.cancelPull(); }

    function updateRegistration() {
        if (!registry) return;
        if (exposed) registry.register(root);
        else registry.unregister(root);
    }

    onExpansionChanged: if (collapsing && expansion === 0) collapsing = false
    onExpandedChanged: {
        if (expanded) {
            collapsing = false;
            registry?.collapseAll(root);
            GlobalStates.mediaControlsOpen = false;
            if (expansion === 0) captureBounds();
            if (playerLoader.status === Loader.Ready) expansion = 1;
        } else {
            collapsing = expansion > 0;
            expansion = 0;
        }
    }
    function dropInactivePlayer() {
        if (hasActivity) return;
        expanded = false;
        cancelPull();
    }
    onActivePlayerChanged: dropInactivePlayer()
    onHasActivityChanged: dropInactivePlayer()
    onExposedChanged: {
        if (!exposed) {
            expanded = false;
            if (dragging) cancelPull();
        }
        updateRegistration();
    }
    onRegistryChanged: updateRegistration()
    Component.onCompleted: {
        dropInactivePlayer();
        updateRegistration();
    }
    Component.onDestruction: registry?.unregister(root)

    // The regular popup and the morph show the same player; keep only one open.
    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen) root.expanded = false;
        }
    }

    // Let short clicks finish; take over the pointer only after a drag begins.
    BarMediaPullHandler {
        id: pullGesture
        host: root
    }

    // The area that accepts input while the pill is pulled out of the bar
    Item {
        id: pullCorridor
        parent: root.barWindow?.islandOverlay ?? root
        x: root.compactBounds.x - (root.vertical && Config.options.bar.bottom ? root.pullThreshold : 0)
        y: root.compactBounds.y - (!root.vertical && Config.options.bar.bottom ? root.pullThreshold : 0)
        width: root.compactBounds.width + (root.vertical ? root.pullThreshold : 0)
        height: root.compactBounds.height + (!root.vertical ? root.pullThreshold : 0)
    }

    Item {
        id: overlay
        parent: root.barWindow?.islandOverlay ?? root
        anchors.fill: parent
        visible: root.exposed
    }

    BarMediaSurface {
        id: surface
        readonly property bool morphing: root.expansion > 0
        parent: morphing ? overlay : root
        clipping: morphing
        textureSize: Qt.size(Math.ceil(Math.max(root.compactBounds.width, root.expandedBounds.width)),
            Math.ceil(Math.max(root.compactBounds.height, root.expandedBounds.height)))
        x: morphing ? root.interpolate(root.compactBounds.x, root.expandedBounds.x) : (root.width - width) / 2
        y: morphing ? root.interpolate(root.compactBounds.y, root.expandedBounds.y) : (root.height - height) / 2
        width: morphing ? root.interpolate(root.compactBounds.width, root.expandedBounds.width) : root.idleSurfaceWidth
        height: morphing ? root.interpolate(root.compactBounds.height, root.expandedBounds.height) : root.idleSurfaceHeight
        Behavior on height {
            enabled: !surface.morphing && root.animateIdleSurfaceHeight
            NumberAnimation { duration: 180; easing.type: Easing.InOutQuad }
        }
        radius: morphing
            ? root.interpolate(Math.min(root.compactBounds.width, root.compactBounds.height) / 2, 24)
            : Math.min(width, height) / 2
        color: root.surfaceColor
        opacity: morphing ? 1 : root.idleSurfaceOpacity
        visible: root.exposed && opacity > 0
        z: 1
        focus: root.expanded
        Keys.onEscapePressed: event => {
            root.expanded = false;
            event.accepted = true;
        }

        StyledRectangularShadow {
            parent: surface
            target: surface
            opacity: root.expansion
            visible: opacity > 0
            // Geometry changes every frame; caching would recreate the shadow texture.
            cached: false
            z: -1
        }

        // Prewarm fixed-size controls; only the pill contributes to the window's input mask.
        BarMediaPlayerLoader {
            id: playerLoader
            host: root
        }
    }
}
