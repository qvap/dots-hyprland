import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property int scaledScreenWidth
    required property int scaledScreenHeight
    required property real wallpaperScale

    property Item wallpaperItem: null

    property bool visibleWhenLocked: Config.options.lock.showWidgets
    // >= 0: this is an extra copy stored in background.widgets.imageInstances
    property int instanceIndex: -1
    property var configEntry: instanceIndex < 0
        ? Config.options.background.widgets[configEntryName]
        : Config.options.background.widgets.imageInstances[instanceIndex]
    // Entries of a list<var> aren't observed, so copies are saved by reassigning the whole list
    function setEntry(patch) {
        if (root.instanceIndex < 0) {
            for (const key in patch) root.configEntry[key] = patch[key];
            return;
        }
        const list = Array.from(Config.options.background.widgets.imageInstances);
        list[root.instanceIndex] = Object.assign({}, list[root.instanceIndex], patch);
        Config.options.background.widgets.imageInstances = list;
    }

    property string placementStrategy: configEntry.placementStrategy
    property real targetX: Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width))
    property real targetY : Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height))
    property real targetZ: configEntry.z
    x: targetX
    y: targetY
    z: targetZ
    visible: opacity > 0
    opacity: ((GlobalStates.screenLocked && !visibleWhenLocked) ? 0 : 1) * (1 - removeProgress)
    Behavior on opacity {
        // Restarting every frame would stall the removal animation
        enabled: !root.removing
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: ((draggable && containsPress) ? 1.05 : 1) * (1 - removeProgress)
    Behavior on scale {
        enabled: !root.removing
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    draggable: placementStrategy === "free" && !Config.options.background.widgetsLocked

    function requestDelete() {
        if (root.instanceIndex < 0) {
            Config.options.background.widgets[root.configEntryName].enable = false
            return
        }
        const list = Array.from(Config.options.background.widgets.imageInstances)
        list.splice(root.instanceIndex, 1)
        Config.options.background.widgets.imageInstances = list
    }
    function restoreXYBinding() {
        root.x = Qt.binding(() => root.targetX);
        root.y = Qt.binding(() => root.targetY);
        root.z = Qt.binding(() => root.targetZ);
    }

    function commitPosition() {
        root.setEntry({ x: root.x, y: root.y, z: root.z });
        root.targetX = Qt.binding(() => Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width)));
        root.targetY = Qt.binding(() => Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height)));
        root.targetZ = Qt.binding(() => configEntry.z);
        root.restoreXYBinding();
    }

    onReleased: root.commitPosition()

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property color colText: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }

    property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
    property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    
    onWallpaperPathChanged: refreshPlacementIfNeeded()
    onPlacementStrategyChanged: refreshPlacementIfNeeded()
    Connections {
        target: Config
        function onReadyChanged() { refreshPlacementIfNeeded() }
    }
    function refreshPlacementIfNeeded() {
        if (!Config.ready) return;
        if (root.placementStrategy === "free" && !root.needsColText) return;
        leastBusyRegionProc.wallpaperPath = root.wallpaperPath;
        leastBusyRegionProc.running = false;
        leastBusyRegionProc.running = true;
    }
    Process {
        id: leastBusyRegionProc
        property string wallpaperPath: root.wallpaperPath
        // TODO: make these less arbitrary
        property int contentWidth: 300
        property int contentHeight: 300
        property int horizontalPadding: 200
        property int verticalPadding: 200
        command: [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh")
            , "--screen-width", Math.round(root.scaledScreenWidth)
            , "--screen-height", Math.round(root.scaledScreenHeight)
            , "--width", contentWidth
            , "--height", contentHeight
            , "--horizontal-padding", horizontalPadding
            , "--vertical-padding", verticalPadding
            , wallpaperPath
            , ...(root.placementStrategy === "mostBusy" ? ["--busiest"] : [])
        ]
        stdout: StdioCollector {
            id: leastBusyRegionOutputCollector
            onStreamFinished: {
                const output = leastBusyRegionOutputCollector.text;
                if (output.length === 0) return;
                const parsedContent = JSON.parse(output);
                root.dominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                if (root.placementStrategy === "free") return;
                root.targetX = parsedContent.center_x * root.wallpaperScale - root.width / 2;
                root.targetY  = parsedContent.center_y * root.wallpaperScale - root.height / 2;
            }
        }
    }
}