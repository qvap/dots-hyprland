pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    id: root

    property bool inhibit: false

    function syncPersistentState() {
        if (Persistent.ready) {
            root.inhibit = Persistent.states.idle.inhibit;
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
        if (Persistent.ready && Persistent.states.idle.inhibit !== root.inhibit) {
            Persistent.states.idle.inhibit = root.inhibit;
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
    }

    IdleInhibitor {
        id: idleInhibitor
        enabled: root.inhibit
        window: PanelWindow {
            // Inhibitor requires a "visible" surface
            // Actually not lol
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            // Just in case...
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }
        }
    }
}
