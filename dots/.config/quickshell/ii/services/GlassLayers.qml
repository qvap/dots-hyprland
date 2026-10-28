pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var layers: ({})

    function refresh() {
        debounce.restart()
    }

    Timer {
        id: debounce
        interval: 40
        onTriggered: {
            collector.running = false
            collector.running = true
        }
    }

    Process {
        id: collector
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.layers = JSON.parse(text)
                } catch (e) {}
            }
        }
    }
}
