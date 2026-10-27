pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    property bool inhibit: false
    property bool ready: false

    Timer {
        id: startupTimer
        interval: 1500
        running: true
        repeat: false
        onTriggered: {
            root.ready = true;
        }
    }

    function syncPersistentState() {
        if (Persistent.ready) {
            root.inhibit = Persistent.states?.idle?.inhibit ?? false;
        }
    }

    Component.onCompleted: syncPersistentState()

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.syncPersistentState();
        }
    }

    onInhibitChanged: {
        if (Persistent.ready && Persistent.states?.idle && Persistent.states.idle.inhibit !== root.inhibit) {
            Persistent.states.idle.inhibit = root.inhibit;
        }
    }

    function toggleInhibit(active = null) {
        root.ready = true;
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
    }

    IdleInhibitor {
        id: idleInhibitor
        enabled: root.inhibit && root.ready

        window: PanelWindow {
            id: inhibitorWindow

            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell:idleInhibitor"

            anchors {
                right: true
                bottom: true
            }

            Rectangle { // what the fuck is this? am i stupid?
                width: 1
                height: 1
                color: "transparent"
            }

            mask: Region {
                item: null
            }
        }
    }
}
