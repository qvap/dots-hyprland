import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false

    Variants {
        // For each monitor
        model: Quickshell.screens

        PanelWindow {
            id: dockRoot
            // Window
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked && !GlobalStates.widgetEditorOpen

            property bool reveal: root.pinned || (Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse) || dockApps.requestDockShow || (!ToplevelManager.activeToplevel?.activated)
            readonly property real baseHeight: (Config.options?.dock.height ?? 70) + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut
            // Room above the dock for magnified icons
            readonly property real magnifyRoom: Config.options?.dock.magnify ? (Config.options?.dock.height ?? 70) * ((Config.options?.dock.magnifyScale ?? 1) - 1) : 0
            readonly property bool magnifying: magnifyRoom > 0 && reveal && dockMouseArea.containsMouse

            anchors {
                bottom: true
                left: true
                right: true
            }

            exclusiveZone: root.pinned ? baseHeight - (Appearance.sizes.hyprlandGapsOut) - (Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut) : 0

            implicitWidth: dockBackground.implicitWidth
            WlrLayershell.namespace: "quickshell:dock"
            BackgroundEffect.blurRegion: BlurRegion { items: [dockVisualBackground] }
            color: "transparent"

            implicitHeight: baseHeight + magnifyRoom

            mask: Region {
                item: dockMouseArea
            }

            // Cursor x for magnification, in window coordinates so that the dock
            // resizing under it can't feed back. (dockMouseArea.mouseX stops
            // updating while a button is hovered.)
            property real cursorX: 0
            // On the window's content item: it doesn't move, and handlers of
            // ancestors still see the cursor over the buttons
            HoverHandler {
                id: cursorTracker
            }
            // Sampled once a frame rather than bound, so nothing the icons do
            // within a frame can feed back into it
            FrameAnimation {
                running: dockRoot.magnifying
                onTriggered: dockRoot.cursorX = cursorTracker.point.position.x
            }

            MouseArea {
                id: dockMouseArea
                // How far the dock is slid down out of view
                property real slide: dockRoot.reveal ? 0 : Config.options?.dock.hoverToReveal ? (dockRoot.baseHeight - Config.options.dock.hoverRegionHeight) : (dockRoot.baseHeight + 1)
                // While magnifying, also covers the room above so the enlarged icons stay hovered
                readonly property real room: dockRoot.magnifying ? dockRoot.magnifyRoom : 0
                height: dockRoot.baseHeight + room
                anchors {
                    top: parent.top
                    topMargin: dockRoot.magnifyRoom - room + slide
                    horizontalCenter: parent.horizontalCenter
                }
                implicitWidth: dockHoverRegion.implicitWidth + Appearance.sizes.elevationMargin * 2
                hoverEnabled: true

                Behavior on slide {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item {
                    id: dockHoverRegion
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: dockRoot.baseHeight
                    implicitWidth: dockBackground.implicitWidth

                    Item { // Wrapper for the dock background
                        id: dockBackground
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                        }

                        implicitWidth: dockRow.implicitWidth + 5 * 2
                        height: parent.height - Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut

                        StyledRectangularShadow {
                            target: dockVisualBackground
                        }
                        Rectangle { // The real rectangle that is visible
                            id: dockVisualBackground
                            BlurSource {}
                            property real margin: Appearance.sizes.elevationMargin
                            anchors.fill: parent
                            anchors.topMargin: Appearance.sizes.elevationMargin
                            anchors.bottomMargin: Appearance.sizes.hyprlandGapsOut
                            color: Appearance.colors.colLayer0
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border
                            radius: Appearance.rounding.large
                        }

                        RowLayout {
                            id: dockRow
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3
                            property real padding: 5

                            VerticalButtonGroup {
                                Layout.topMargin: Appearance.sizes.hyprlandGapsOut // why does this work
                                GroupButton {
                                    // Pin button
                                    baseWidth: 35
                                    baseHeight: 35
                                    clickedWidth: baseWidth
                                    clickedHeight: baseHeight + 20
                                    buttonRadius: Appearance.rounding.normal
                                    toggled: root.pinned
                                    onClicked: root.pinned = !root.pinned
                                    contentItem: MaterialSymbol {
                                        text: "keep"
                                        horizontalAlignment: Text.AlignHCenter
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: root.pinned ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                                    }
                                }
                            }
                            DockSeparator {}
                            DockApps {
                                id: dockApps
                                buttonPadding: dockRow.padding
                                magnifying: dockRoot.magnifying
                                // The list's center doesn't move as icons grow (the dock stays
                                // centered and the items around the list keep their size)
                                magnifyX: dockRoot.cursorX - dockRoot.width / 2 - (dockApps.x - (dockRow.spacing * 2 + trailingSeparator.width + overviewButton.width)) / 2
                            }
                            DockSeparator {
                                id: trailingSeparator
                            }
                            DockButton {
                                id: overviewButton
                                Layout.fillHeight: true
                                onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                                topInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                bottomInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                contentItem: MaterialSymbol {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: parent.width / 2
                                    text: "apps"
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
