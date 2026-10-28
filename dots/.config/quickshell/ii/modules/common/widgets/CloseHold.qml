import QtQuick

// Hyprland animates a closing layer from a snapshot of its last frame and blurs that snapshot by alpha,
// ignoring the blur region, so soft shadows around a panel turn into a blurred halo.
// Keeps the window mapped (`mapped`) for two more frames after `open` turns false, so the snapshot is
// a frame drawn with `open` already false: bind the shadows' visibility to `open`.
Item {
    id: root
    required property bool open
    readonly property bool mapped: open || frames > 0
    property int frames: 0
    onOpenChanged: frames = open ? 0 : 2

    Connections {
        target: root.frames > 0 ? root.Window.window : null
        // Emitted on the GUI thread as each frame starts: the first frame carries the change, the second
        // is synced only after the first was committed
        function onAfterAnimating() {
            if (root.frames > 1) {
                root.frames--;
                root.Window.window.update();
            } else {
                // Hiding the window from inside its own frame preparation is not safe
                Qt.callLater(() => root.frames = 0);
            }
        }
    }
    Timer {
        // Never stay on screen if no frames come
        running: root.frames > 0
        interval: 150
        onTriggered: root.frames = 0
    }
}
