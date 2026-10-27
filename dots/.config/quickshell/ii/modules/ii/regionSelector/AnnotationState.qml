pragma Singleton
import Quickshell
import QtQuick

// Shared tool state for the in-shell screenshot annotation editor.
// Only one monitor annotates at a time, so global state is fine.
Singleton {
    id: root

    // Current draw tool id (see AnnotationToolbar). "" = nothing selected.
    property string tool: "rect"
    property color strokeColor: root.palette[0]
    property real strokeWidth: 4
    property int fontSize: 26
    // Monotonic counter for the numbered-step tool; reset on clear.
    property int counterValue: 1

    readonly property var palette: [
        "#ff453a", "#ff9f0a", "#ffd60a", "#32d74b",
        "#0a84ff", "#5e5ce6", "#ffffff", "#1c1c1e"
    ]
    readonly property var strokeWidths: [2, 4, 7, 12]

    function isDrawTool() {
        return root.tool !== "" && root.tool !== "select";
    }

    function reset() {
        root.counterValue = 1;
        root.tool = "rect";
    }
}
