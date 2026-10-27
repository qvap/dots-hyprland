pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.modules.common.functions

Singleton {
    id: root
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false

    property real mediaWidgetX: -1
    property real mediaWidgetY: -1
    property real mediaWidgetWidth: 0
    property real mediaWidgetHeight: 0

    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool diSessionOpen: false
    property bool desktopMenuOpen: false
    property bool widgetEditorOpen: false
    property var desktopMenuScreen: null
    property real desktopMenuX: 0
    property real desktopMenuY: 0
    property bool desktopWidgetKeyboardFocus: false
    property string osdIndicatorType: "volume"
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false
    property list<real> visualizerPoints: []

    readonly property bool dynamicIslandEnabled: Config.options.bar.layouts.leftLayout.includes("dynamicIsland")
        || Config.options.bar.layouts.middleLayout.includes("dynamicIsland")
        || Config.options.bar.layouts.rightLayout.includes("dynamicIsland")
    readonly property bool barCenterOnly: Config.options.bar.layouts.leftLayout.length === 0
        && Config.options.bar.layouts.rightLayout.length === 0

    Process {
        id: cavaProc
        running: MprisController.players.length > 0
        onRunningChanged: {
            if (!running)
                root.visualizerPoints = [];
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                root.visualizerPoints = data.split(";").map(value => parseFloat(value.trim())).filter(value => !isNaN(value));
            }
        }
    }

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true;
        }
        onReleased: {
            root.superDown = false;
        }
    }
}
