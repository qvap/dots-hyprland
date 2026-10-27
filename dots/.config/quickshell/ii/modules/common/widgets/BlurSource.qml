import QtQuick
import Quickshell

// Registers `target` for compositor-side blur in its window.
// The window needs `property list<Item> blurItems` and `BackgroundEffect.blurRegion: BlurRegion { items: blurItems }`.
Item {
    id: root
    property Item target: parent
    // Re-read on Window.window changes: items created inside a Loader get their window only after reparenting
    readonly property var win: Window.window ? QsWindow.window : null

    onWinChanged: if (win?.blurItems !== undefined && !win.blurItems.includes(target)) win.blurItems.push(target)
    // Window size changes move the target without changing its own geometry; reassigning the list makes BlurRegion re-read it
    Connections {
        target: root.Window.window
        function onWidthChanged() { root.reannounce(); }
        function onHeightChanged() { root.reannounce(); }
    }
    function reannounce() {
        if (win?.blurItems === undefined) return;
        // Reassigning identical contents does not emit a change, so clear first
        const items = [...win.blurItems];
        win.blurItems = [];
        win.blurItems = items;
    }
    Component.onDestruction: if (win?.blurItems !== undefined) win.blurItems = win.blurItems.filter(i => i !== target)
}
