pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: bar
    property bool showBarBackground: Config.options.bar.showBackground

    Variants {
        // For each monitor
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }
        LazyLoader {
            id: barLoader
            active: GlobalStates.barOpen && !GlobalStates.screenLocked
            required property ShellScreen modelData
            component: PanelWindow { // Bar window
                id: barRoot
                screen: barLoader.modelData

                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: {
                        barRoot.superShow = true;
                    }
                }
                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable)
                            return;
                        if (GlobalStates.superDown)
                            showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            barRoot.superShow = false;
                        }
                    }
                }

                property bool showCorners: !Config.options.bar.autoHide.enable || mustShow

                Timer {
                    id: cornerRevealTimer
                    interval: 65
                    onTriggered: barRoot.showCorners = true
                }

                onMustShowChanged: {
                    if (!Config.options.bar.autoHide.enable)
                        return;
                    if (mustShow) {
                        cornerRevealTimer.restart();
                    } else {
                        cornerRevealTimer.stop();
                        barRoot.showCorners = false;
                    }
                }
                property bool superShow: false
                readonly property bool islandInteracting: (islandItem?.interacting ?? false) || (mediaItem?.interacting ?? false)
                readonly property bool hasIsland: [Config.options.bar.layouts.leftLayout,
                    Config.options.bar.layouts.middleLayout, Config.options.bar.layouts.rightLayout]
                    .some(layout => layout.includes("island"))
                readonly property bool hasMorphingMedia: [Config.options.bar.layouts.leftLayout,
                    Config.options.bar.layouts.middleLayout, Config.options.bar.layouts.rightLayout]
                    .some(layout => layout.includes("media"))
                property var islandItem: null
                property var mediaItem: null
                property alias islandOverlay: islandOverlayLayer
                readonly property bool islandExpanded: (islandItem?.expanded ?? false) || (mediaItem?.expanded ?? false)
                WlrLayershell.keyboardFocus: islandExpanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                onIslandExpandedChanged: {
                    if (islandExpanded) GlobalFocusGrab.addDismissable(barRoot);
                    else GlobalFocusGrab.removeDismissable(barRoot);
                }
                function close() {
                    if (islandItem) islandItem.expanded = false;
                    if (mediaItem) mediaItem.expanded = false;
                }
                // Allocate the animation's extent once; keep the visual bar and exclusive zone at the edge.
                Item { id: islandOverlayLayer; anchors.fill: parent; z: 100 }

                property bool mustShow: hoverRegion.containsMouse || superShow || islandInteracting
                property var thisMonitorData: HyprlandData.monitors.find(m => m.name === barRoot.screen?.name)
                property bool monitorHasFullscreen: HyprlandData.workspaceById[thisMonitorData?.activeWorkspace?.id]?.hasfullscreen ?? false
                property bool monitorHasSpecialOpen: (thisMonitorData?.specialWorkspace?.name ?? "") !== ""
                exclusionMode: ExclusionMode.Ignore
                property int normalExclusiveZone: (Config?.options.bar.autoHide.enable && (!mustShow || !Config?.options.bar.autoHide.pushWindows)) ? 0 : Appearance.sizes.baseBarHeight + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0) + (Config.options.bar.cornerStyle === 2 ? -6 : 0) + (Config.options.bar.cornerStyle === 3 ? (10 - Appearance.sizes.hyprlandGapsOut) : 0)

                exclusiveZone: (barContent.centerOnly && Config.options.bar.centerOnlyReserveFrame) ? Config.options.bar.frameThickness : normalExclusiveZone
                WlrLayershell.namespace: "quickshell:bar"
                // Overlay layer only while special workspace sits on top of a fullscreen window on this monitor,
                // else Top layer so fullscreen apps cover the bar as normal (Hyprland buries Top layer under fullscreen+special).
                WlrLayershell.layer: (monitorHasFullscreen && monitorHasSpecialOpen) ? WlrLayer.Overlay : WlrLayer.Top
                implicitHeight: hasIsland || hasMorphingMedia ? Math.min(screen.height, Appearance.sizes.barHeight + Appearance.sizes.mediaControlsHeight + 32)
                    : Appearance.sizes.barHeight + Appearance.rounding.screenRounding
                // When Overlay-layer, bar shares a layer with the screen-corner click zones (ScreenCorners.qml)
                // and same-layer overlap is resolved by stacking, not layer priority - bar was winning and
                // swallowing the tiny corner-open hit rects. Carve them out of the bar's own mask so clicks
                // reach the corners underneath. Only relevant on the edge the bar and corners share.
                property bool cutOutCornerOpenZones: (monitorHasFullscreen && monitorHasSpecialOpen) && (Config.options.bar.bottom === Config.options.sidebar.cornerOpen.bottom)
                property int cornerOpenCutWidth: cutOutCornerOpenZones ? Config.options.sidebar.cornerOpen.cornerRegionWidth : 0
                property int cornerOpenCutHeight: cutOutCornerOpenZones ? Config.options.sidebar.cornerOpen.cornerRegionHeight : 0
                mask: Region {
                    item: hoverMaskRegion
                    Region {
                        intersection: Intersection.Combine
                        item: barRoot.islandItem?.pullSurface ?? null
                    }
                    Region {
                        intersection: Intersection.Combine
                        item: barRoot.islandItem?.expandedSurface ?? null
                        radius: barRoot.islandItem?.expandedSurface?.radius ?? 0
                    }
                    Region {
                        intersection: Intersection.Combine
                        item: barRoot.mediaItem?.pullSurface ?? null
                    }
                    Region {
                        intersection: Intersection.Combine
                        item: barRoot.mediaItem?.expandedSurface ?? null
                        radius: barRoot.mediaItem?.expandedSurface?.radius ?? 0
                    }
                    Region {
                        intersection: Intersection.Subtract
                        x: 0
                        y: Config.options.bar.bottom ? (barRoot.height - barRoot.cornerOpenCutHeight) : 0
                        width: barRoot.cornerOpenCutWidth
                        height: barRoot.cornerOpenCutHeight
                    }
                    Region {
                        intersection: Intersection.Subtract
                        x: barRoot.width - barRoot.cornerOpenCutWidth
                        y: Config.options.bar.bottom ? (barRoot.height - barRoot.cornerOpenCutHeight) : 0
                        width: barRoot.cornerOpenCutWidth
                        height: barRoot.cornerOpenCutHeight
                    }
                }
                color: "transparent"

                // Positioning
                anchors {
                    top: !Config.options.bar.bottom
                    bottom: Config.options.bar.bottom
                    left: true
                    right: true
                }

                margins {
                    right: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) ? -1 : 0
                    bottom: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) ? -1 : 0
                }

                // Include in focus grab
                Component.onCompleted: {
                    GlobalFocusGrab.addPersistent(barRoot);
                }
                Component.onDestruction: {
                    GlobalFocusGrab.removePersistent(barRoot);
                    GlobalFocusGrab.removeDismissable(barRoot);
                }

                MouseArea {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors {
                        fill: parent
                        rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * 1
                        bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * 1
                    }

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: !Config.options.bar.bottom ? parent.top : undefined
                            bottom: Config.options.bar.bottom ? parent.bottom : undefined
                        }

                        height: {
                            if (!Config?.options?.bar?.autoHide?.enable) {
                                return barContent.height + (Config.options.bar.cornerStyle === 3 ? 10 : 0);
                            }

                            const triggerWidth = Config?.options?.bar?.autoHide?.hoverRegionWidth ?? 5;

                            const visibleContentHeight = !Config.options.bar.bottom ? (barContent.y + barContent.height) : (parent.height - barContent.y);

                            return Math.max(triggerWidth, visibleContentHeight);
                        }
                    }

                    BarContent {
                        id: barContent

                        implicitHeight: Appearance.sizes.barHeight
                        anchors {
                            right: parent.right
                            left: parent.left
                            top: parent.top
                            bottom: undefined
                            topMargin: (Config?.options.bar.autoHide.enable && !mustShow) ? -Appearance.sizes.barHeight : (Config.options.bar.cornerStyle === 3 ? 5 : 0)
                            bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1
                            rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                        }
                        Behavior on anchors.topMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on anchors.bottomMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: parent.bottom
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.bottomMargin: (Config?.options.bar.autoHide.enable && !mustShow) ? -Appearance.sizes.barHeight : (Config.options.bar.cornerStyle === 3 ? 5 : 0)
                            }
                        }
                    }

                    // Round decorators
                    Loader {
                        id: roundDecorators
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: barContent.bottom
                            bottom: undefined
                        }
                        height: Appearance.rounding.screenRounding
                        active: showBarBackground && Config.options.bar.cornerStyle === 0 && !barContent.centerOnly// Hug

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: barContent.top
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding

                            readonly property color decoratorColor: showBarBackground ? (Config.options.bar.followFrameColor && Config.options.bar.frameColor ? Appearance.getColorFromName(Config.options.bar.frameColor) : Appearance.colors.colLayer0) : "transparent"

                            RoundCorner {
                                id: leftCorner
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: parent.left
                                }

                                implicitSize: Appearance.rounding.screenRounding
                                color: parent.decoratorColor

                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        leftCorner.corner: RoundCorner.CornerEnum.BottomLeft
                                    }
                                }
                            }
                            RoundCorner {
                                id: rightCorner
                                anchors {
                                    right: parent.right
                                    top: !Config.options.bar.bottom ? parent.top : undefined
                                    bottom: Config.options.bar.bottom ? parent.bottom : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: parent.decoratorColor

                                corner: RoundCorner.CornerEnum.TopRight
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        rightCorner.corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }

        function close(): void {
            GlobalStates.barOpen = false;
        }

        function open(): void {
            GlobalStates.barOpen = true;
        }
    }

    CompositorGlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }
    }

    CompositorGlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            GlobalStates.barOpen = true;
        }
    }

    CompositorGlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            GlobalStates.barOpen = false;
        }
    }
}
