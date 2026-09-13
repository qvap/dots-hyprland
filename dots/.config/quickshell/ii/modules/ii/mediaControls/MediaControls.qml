pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool visible: false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var realPlayers: MprisController.players
    readonly property var meaningfulPlayers: {
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase();
        if (preferred.length === 0)
            return filterDuplicatePlayers(realPlayers);
        const filtered = realPlayers.filter(p => (p.identity ?? "").toLowerCase().includes(preferred) || (p.desktopEntry ?? "").toLowerCase().includes(preferred));
        if (filtered.length === 0)
            return filterDuplicatePlayers(realPlayers);
        return filterDuplicatePlayers(filtered);
    }
    readonly property real osdWidth: Appearance.sizes.osdWidth
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real widgetHeight: Appearance.sizes.mediaControlsHeight
    property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
    property list<real> visualizerPoints: []

    function filterDuplicatePlayers(players) {
        let filtered = [];
        let used = new Set();

        for (let i = 0; i < players.length; ++i) {
            if (used.has(i))
                continue;
            let p1 = players[i];
            let group = [i];

            // Find duplicates by trackTitle prefix
            for (let j = i + 1; j < players.length; ++j) {
                let p2 = players[j];
                if (p1.trackTitle && p2.trackTitle && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle)) || (p1.position - p2.position <= 2 && p1.length - p2.length <= 2)) {
                    group.push(j);
                }
            }

            // Pick the one with non-empty trackArtUrl, or fallback to the first
            let chosenIdx = group.find(idx => players[idx].trackArtUrl && players[idx].trackArtUrl.length > 0);
            if (chosenIdx === undefined)
                chosenIdx = group[0];

            filtered.push(players[chosenIdx]);
            group.forEach(idx => used.add(idx));
        }
        return filtered;
    }

    Process {
        id: cavaProc
        running: root.realPlayers.length > 0
        onRunningChanged: {
            if (!cavaProc.running) {
                root.visualizerPoints = [];
            }
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                root.visualizerPoints = points;
            }
        }
    }

    // lazy fix for broken exit animation
    Timer {
        id: unloadTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (!GlobalStates.mediaControlsOpen) {
                mediaControlsLoader.active = false;
            }
        }
    }

    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen) {
                unloadTimer.stop();
                mediaControlsLoader.active = true;
            } else {
                unloadTimer.restart();
            }
        }
    }

    Loader {
        id: mediaControlsLoader
        active: false

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: GlobalStates.mediaControlsOpen

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: root.widgetWidth
            implicitHeight: playerColumnLayout.implicitHeight
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mediaControls"

            anchors {
                top: !Config.options.bar.bottom || Config.options.bar.vertical
                bottom: Config.options.bar.bottom && !Config.options.bar.vertical
                left: !(Config.options.bar.vertical && Config.options.bar.bottom)
                right: Config.options.bar.vertical && Config.options.bar.bottom
            }

            property real lastCalculatedLeft: (panelWindow.screen.width / 2) - (widgetWidth / 2)
            property real lastCalculatedTop: (panelWindow.screen.height / 2) - (widgetHeight * 1.5)

            readonly property real calculatedLeftMargin: {
                if (Config.options.bar.vertical) {
                    return Appearance.sizes.barHeight;
                }

                const wx = GlobalStates.mediaWidgetX;
                const ww = GlobalStates.mediaWidgetWidth;

                if (GlobalStates.mediaControlsOpen && !isNaN(wx) && wx > 0 && !isNaN(ww) && ww > 0) {
                    let widgetCenter = wx + (ww / 2);
                    let targetLeft = widgetCenter - (root.widgetWidth / 2);

                    let minLeft = Appearance.sizes.hyprlandGapsOut;
                    let maxLeft = panelWindow.screen.width - root.widgetWidth - Appearance.sizes.hyprlandGapsOut;
                    lastCalculatedLeft = Math.max(minLeft, Math.min(maxLeft, targetLeft));
                }

                return lastCalculatedLeft;
            }

            readonly property real calculatedTopMargin: {
                if (!Config.options.bar.vertical) {
                    return Appearance.sizes.barHeight;
                }

                const wy = GlobalStates.mediaWidgetY;
                const wh = GlobalStates.mediaWidgetHeight;

                if (GlobalStates.mediaControlsOpen && !isNaN(wy) && wy > 0 && !isNaN(wh) && wh > 0) {
                    let widgetCenter = wy + (wh / 2);
                    let targetTop = widgetCenter - (playerColumnLayout.implicitHeight / 2);

                    let minTop = Appearance.sizes.hyprlandGapsOut;
                    let maxTop = panelWindow.screen.height - playerColumnLayout.implicitHeight - Appearance.sizes.hyprlandGapsOut;
                    lastCalculatedTop = Math.max(minTop, Math.min(maxTop, targetTop));
                }

                return lastCalculatedTop;
            }

            margins {
                top: panelWindow.calculatedTopMargin
                bottom: Appearance.sizes.barHeight
                left: panelWindow.calculatedLeftMargin
                right: Appearance.sizes.barHeight
            }

            mask: Region {
                item: GlobalStates.mediaControlsOpen ? playerColumnLayout : null
            }

            Component.onCompleted: {
                if (GlobalStates.mediaControlsOpen) {
                    GlobalFocusGrab.addDismissable(panelWindow);
                }
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }

            Connections {
                target: GlobalStates
                function onMediaControlsOpenChanged() {
                    if (GlobalStates.mediaControlsOpen) {
                        GlobalFocusGrab.addDismissable(panelWindow);
                    } else {
                        GlobalFocusGrab.removeDismissable(panelWindow);
                    }
                }
            }

            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.mediaControlsOpen = false;
                }
            }

            ColumnLayout {
                id: playerColumnLayout
                anchors.fill: parent
                spacing: -Appearance.sizes.elevationMargin

                Repeater {
                    model: ScriptModel {
                        values: root.meaningfulPlayers
                    }
                    delegate: PlayerControl {
                        required property MprisPlayer modelData
                        player: modelData
                        visualizerPoints: root.visualizerPoints
                        implicitWidth: root.widgetWidth
                        implicitHeight: root.widgetHeight
                        radius: root.popupRounding
                    }
                }

                Item {
                    // No player placeholder
                    Layout.alignment: {
                        if (panelWindow.anchors.left)
                            return Qt.AlignLeft;
                        if (panelWindow.anchors.right)
                            return Qt.AlignRight;
                        return Qt.AlignHCenter;
                    }
                    Layout.leftMargin: Appearance.sizes.hyprlandGapsOut
                    Layout.rightMargin: Appearance.sizes.hyprlandGapsOut
                    visible: root.meaningfulPlayers.length === 0
                    implicitWidth: placeholderBackground.implicitWidth + Appearance.sizes.elevationMargin
                    implicitHeight: placeholderBackground.implicitHeight + Appearance.sizes.elevationMargin

                    StyledRectangularShadow {
                        target: placeholderBackground
                    }

                    Rectangle {
                        id: placeholderBackground
                        anchors.centerIn: parent
                        color: Appearance.colors.colLayer0
                        radius: root.popupRounding
                        property real padding: 20
                        implicitWidth: placeholderLayout.implicitWidth + padding * 2
                        implicitHeight: placeholderLayout.implicitHeight + padding * 2

                        ColumnLayout {
                            id: placeholderLayout
                            anchors.centerIn: parent

                            StyledText {
                                text: Translation.tr("No active player")
                                font.pixelSize: Appearance.font.pixelSize.large
                            }
                            StyledText {
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Make sure your player has MPRIS support\nor try turning off duplicate player filtering")
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
            if (GlobalStates.mediaControlsOpen)
                Notifications.timeoutAll();
        }

        function close(): void {
            GlobalStates.mediaControlsOpen = false;
        }

        function open(): void {
            GlobalStates.mediaControlsOpen = true;
            Notifications.timeoutAll();
        }
    }

    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
        }
    }
    GlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = true;
        }
    }
    GlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = false;
        }
    }
}
