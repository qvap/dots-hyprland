pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

BarMediaMorph {
    id: root

    vertical: Config.options.bar.vertical
    property bool initialized: false
    readonly property color mediaAccent: playerCard?.hasArtColors ? playerCard.blendedColors.colPrimary : Appearance.colors.colPrimary
    readonly property var mediaColors: playerCard?.blendedColors ?? Appearance.colors
    readonly property bool specialActive: workspaces.workspaceModel.specialWorkspace != null
        && workspaces.workspaceModel.specialWorkspaceActive
    readonly property string specialName: workspaces.workspaceModel.specialWorkspaceName
    readonly property bool showActivity: hasActivity || specialActive
    readonly property string mode: expanded && activePlayer !== null ? "expanded" : (showActivity ? "notif" : "idle")

    readonly property bool themed: Config.options.bar.island.followTheme
    readonly property color pillColor: themed ? ColorUtils.applyAlpha(Appearance.colors.colLayer0, 1) : "black"

    readonly property real compactHeight: Math.max(24, Appearance.sizes.barHeight - 8)
    readonly property real compactWidth: workspaces.implicitWidth + compactContent.chromeLength
    readonly property real compactLength: workspaces.implicitHeight + compactContent.chromeLength
    readonly property real verticalWidth: Appearance.sizes.baseVerticalBarWidth
        - (Config.options.bar.cornerStyle === 3 ? 6 : 0)
    Layout.fillHeight: !vertical
    Layout.fillWidth: vertical
    implicitWidth: vertical ? verticalWidth : Math.max(workspaces.implicitWidth, showActivity ? compactWidth : 0)
    implicitHeight: vertical ? (showActivity ? compactLength : workspaces.implicitHeight) : Appearance.sizes.barHeight
    Behavior on implicitWidth { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    readonly property bool showTrackDetails: hasActivity && !workspacePreviewTimer.running
        && (barHover.hovered || trackPreviewTimer.running || dragging)
    readonly property bool showSpecial: specialActive && !showTrackDetails && !workspacePreviewTimer.running
    readonly property bool revealWorkspaces: !dragging && !showTrackDetails && !showSpecial
    property real activityVisibility: showActivity ? 1 : 0
    Behavior on activityVisibility {
        NumberAnimation { duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
    }

    holdsBar: barHover.hovered
    boundsSource: surface
    idleSurfaceWidth: vertical ? Math.min(32, width) : compactWidth
    idleSurfaceHeight: vertical ? height : compactHeight
    idleSurfaceOpacity: activityVisibility
    animateIdleSurfaceHeight: !vertical
    surfaceColor: pillColor

    HoverHandler { id: barHover }
    function showWorkspacePreview() {
        if (!initialized || !exposed || mode === "idle") return;
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
        if (initialized && exposed && hasActivity) trackPreviewTimer.restart();
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
    onActivePlayerChanged: showTrackPreview()
    Component.onCompleted: initialized = true

    Workspaces {
        id: workspaces
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        vertical: root.vertical
        showSpecialIndicator: false
        switchOnPress: false
        enabled: !root.collapsing && (root.mode === "idle" || root.revealWorkspaces || root.expansion > 0.9)
        opacity: root.showActivity ? Math.max(compactContent.workspaceMix * (1 - root.expansion), root.expansion) : 1
        visible: opacity > 0
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
        acceptedButtons: root.activePlayer && root.mode !== "idle" && !workspacePreviewTimer.running
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

    IslandContent {
        id: compactContent
        parent: root.surface.contentItem
        anchors.centerIn: parent
        width: root.expansion > 0 ? root.compactBounds.width : root.surface.width
        height: root.expansion > 0 ? root.compactBounds.height : root.surface.height
        opacity: Math.max(0, 1 - root.expansion * 3)
        // Only the fade needs the content flattened into one texture
        layer.enabled: root.expansion > 0
        layer.smooth: true
        workspaceVisible: root.revealWorkspaces && !root.collapsing
        player: root.activePlayer
        artSource: root.playerCard?.displayedArtFilePath ?? ""
        mediaVisible: root.hasActivity
        trackVisible: root.showTrackDetails
        specialVisible: root.showSpecial
        specialName: root.specialName
        vertical: root.vertical
        barOnRight: Config.options.bar.bottom
        visualizerPoints: GlobalStates.visualizerPoints
        visualizerColor: root.mediaAccent
        surfaceColor: root.pillColor
        textColor: root.themed ? Appearance.colors.colOnLayer0 : "white"
        subtextColor: root.themed ? Appearance.colors.colSubtext : "#a1a1a1"
        artPlaceholderColor: root.themed ? Appearance.colors.colLayer2 : "#202020"
    }
    BarMediaPlayButton {
        z: 4
        x: Math.round(root.surface.x + root.surface.width - 40 - width)
        y: Math.round(root.surface.y + (root.surface.height - height) / 2)
        player: root.activePlayer
        colors: root.mediaColors
        visible: opacity > 0 && root.expansion === 0 && !root.vertical
        opacity: root.hasActivity && barHover.hovered && !root.revealWorkspaces ? 1 : 0
        enabled: opacity > 0.95
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }
}
