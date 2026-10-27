pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: bgRoot

        required property var modelData

        // Hide when fullscreen
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: GlobalStates.screenLocked || (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
        property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
        property int lastWorkspaceId: relevantWindows[relevantWindows.length - 1]?.workspace.id || 10
        property int workspaceChunkSize: Config?.options.bar.workspaces.shown ?? 10
        property int totalWorkspaces: Math.ceil(lastWorkspaceId / workspaceChunkSize) * workspaceChunkSize
        // Wallpaper
        // A separate lock screen wallpaper can be set in Settings > Background
        property string sourcePath: (GlobalStates.screenLocked && Config.options.background.lockWall !== "") ? Config.options.background.lockWall : Config.options.background.wallpaperPath
        property bool wallpaperIsVideo: [".mp4", ".webm", ".mkv", ".avi", ".mov"].some(ext => sourcePath.endsWith(ext))
        property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : sourcePath
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        readonly property real parallaxRation: Config.options.background.parallax.workspaceZoom
        property real minSuitableScale: 1 // Some reasonable init, to be updated
        property real effectiveWallpaperScale: minSuitableScale * parallaxRation
        property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
        property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
        property real scaledWallpaperWidth: wallpaperWidth * effectiveWallpaperScale
        property real scaledWallpaperHeight: wallpaperHeight * effectiveWallpaperScale
        property real parallaxTotalPixelsX: Math.max(0, scaledWallpaperWidth - screen.width)
        property real parallaxTotalPixelsY: Math.max(0, scaledWallpaperHeight - screen.height)
        readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical
        // Colors
        property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        property color dominantColor: Appearance.colors.colPrimary // Default, to be changed
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Layer props
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        // While locked, wayhaven lifts the wallpaper to the overlay layer once its zoom/blur-in is done;
        // follow it a bit later so these widgets stay above it
        property bool onLockLayer: false
        WlrLayershell.layer: onLockLayer ? WlrLayer.Overlay : WlrLayer.Bottom
        Timer {
            id: lockLayerTimer
            interval: Config.options.lock.blur.enable ? 550 : 150
            onTriggered: bgRoot.onLockLayer = GlobalStates.screenLocked
        }
        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                bgRoot.sendLock();
                if (GlobalStates.screenLocked)
                    lockLayerTimer.restart();
                else
                    bgRoot.onLockLayer = false;
            }
        }
        WlrLayershell.namespace: "quickshell:background"
        property list<Item> blurItems: [] // widget backgrounds in compositor blur mode (BlurSource)
        BackgroundEffect.blurRegion: BlurRegion { items: bgRoot.blurItems }
        // Desktop widgets take the keyboard while being edited (text entry, Del to remove)
        WlrLayershell.keyboardFocus: GlobalStates.desktopWidgetKeyboardFocus ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        onWallpaperPathChanged: {
            bgRoot.updateZoomScale();
            // Clock position gets updated after zoom scale is updated
        }

        // Wallpaper zoom scale
        function updateZoomScale() {
            getWallpaperSizeProc.path = bgRoot.wallpaperPath;
            getWallpaperSizeProc.running = true;
        }
        Process {
            id: getWallpaperSizeProc
            property string path: bgRoot.wallpaperPath
            command: ["magick", "identify", "-format", "%w %h", path]
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    const output = wallpaperSizeOutputCollector.text;
                    const [width, height] = output.split(" ").map(Number);
                    const [screenWidth, screenHeight] = [bgRoot.screen.width, bgRoot.screen.height];
                    bgRoot.wallpaperWidth = width;
                    bgRoot.wallpaperHeight = height;

                    // Perfect image; scale = 1
                    // Small picture; scale > 1; will zoom in the picture
                    // Big picture; scale < 1; will zoom out the picture
                    // Choose max number so every side will fit
                    bgRoot.minSuitableScale = Math.max(screenWidth / width, screenHeight / height);
                }
            }
        }

        // The wayhaven daemon draws the wallpaper (picture or video) on the background layer.
        // We feed it the parallax fractions; it animates them itself with the same curve
        // (OutCubic, 600ms) as `wallpaper` below, so the wallpaper and widgets move in sync.
        function sendParallax() {
            if (!wallpaperSocket.connected)
                return;
            wallpaperSocket.write(`parallax ${bgRoot.monitor?.name ?? "*"} ${wallpaper.usedFractionX} ${wallpaper.usedFractionY} ${bgRoot.parallaxRation}\n`);
            wallpaperSocket.flush();
        }
        // Lock screen: wayhaven zooms/blurs the wallpaper (lock.blur) and shows lockWall if set
        function sendLock() {
            if (!wallpaperSocket.connected)
                return;
            wallpaperSocket.write(`lock ${GlobalStates.screenLocked ? 1 : 0}\n`);
            wallpaperSocket.flush();
        }
        onParallaxRationChanged: sendParallax()
        Connections {
            target: wallpaper
            function onUsedFractionXChanged() {
                bgRoot.sendParallax();
            }
            function onUsedFractionYChanged() {
                bgRoot.sendParallax();
            }
        }
        Socket {
            id: wallpaperSocket
            path: `${Quickshell.env("XDG_RUNTIME_DIR")}/wayhaven.sock`
            onConnectionStateChanged: {
                bgRoot.sendParallax();
                bgRoot.sendLock();
            }
        }
        Timer {
            // (Re)connect: the daemon may start after the shell, or be restarted
            interval: 2000
            repeat: true
            triggeredOnStart: true
            running: !wallpaperSocket.connected
            onTriggered: wallpaperSocket.connected = true
        }

        Item {
            anchors.fill: parent

            // Desktop menu
            MouseArea {
                anchors.fill: parent
                z: -2
                acceptedButtons: Qt.RightButton
                onClicked: mouse => {
                    GlobalStates.desktopMenuScreen = bgRoot.screen;
                    GlobalStates.desktopMenuX = mouse.x;
                    GlobalStates.desktopMenuY = mouse.y;
                    GlobalStates.desktopMenuOpen = true;
                }
            }

            // Not drawn (wayhaven shows the wallpaper): an invisible copy laid out exactly like it, which the
            // shell-side blur/glass of widgets samples. Only loaded while one of those effects is on.
            StyledImage {
                id: wallpaper
                opacity: 0 // ShaderEffectSource still captures it
                cache: false
                smooth: false

                property int workspaceIndex: (bgRoot.monitor.activeWorkspace?.id ?? 1) - 1
                property real middleFraction: 0.5
                property real fraction: {
                    // 0 - start of the picture
                    // 1 - end of the picture
                    if (bgRoot.totalWorkspaces <= 1) {
                        return middleFraction;
                    }
                    return Math.max(0, Math.min(1, workspaceIndex / (bgRoot.totalWorkspaces - 1)));
                }

                property real usedFractionX: {
                    let usedFraction = middleFraction;
                    if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                        usedFraction = fraction;
                    }
                    if (Config.options.background.parallax.enableSidebar) {
                        let sidebarFraction = bgRoot.parallaxRation / bgRoot.workspaceChunkSize / 2;
                        usedFraction += (sidebarFraction * GlobalStates.sidebarRightOpen - sidebarFraction * GlobalStates.sidebarLeftOpen);
                    }
                    return Math.max(0, Math.min(1, usedFraction));
                }
                property real usedFractionY: {
                    let usedFraction = middleFraction;
                    if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                        usedFraction = fraction;
                    }
                    return Math.max(0, Math.min(1, usedFraction));
                }

                x: {
                    if (bgRoot.screen.width > width) {
                        // Center the picture
                        return (bgRoot.screen.width - width) / 2;
                    }
                    return - bgRoot.parallaxTotalPixelsX * usedFractionX;
                }
                y: {
                    if (bgRoot.screen.height > height) {
                        // Center the picture
                        return (bgRoot.screen.height - height) / 2;
                    }
                    return - bgRoot.parallaxTotalPixelsY * usedFractionY;
                }

                readonly property bool needed: Config.options.background.widgets.glass.enable
                    || (Config.options.background.widgets.blurWidgets && !Config.options.appearance.blur.compositor)
                source: (bgRoot.wallpaperSafetyTriggered || !needed) ? "" : bgRoot.wallpaperPath
                fillMode: Image.PreserveAspectCrop
                Behavior on x {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                width: bgRoot.scaledWallpaperWidth
                height: bgRoot.scaledWallpaperHeight
            }

            // Lock screen dim over wayhaven's blurred wallpaper
            Rectangle {
                anchors.fill: parent
                color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                opacity: bgRoot.shouldBlur ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                // Widgets stay put: no parallax with the wallpaper
                anchors.fill: parent

                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                    AnchorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                WidgetsLoader {
                    anchors.fill: parent
                    screen: bgRoot.screen
                    wallpaperItem: wallpaper
                    wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                }
            }
        }
    }
}
