import QtQuick
import Quickshell
import qs.modules.common

// Blur behind `target` (put it inside the target's background).
// Compositor blur (appearance.blur.compositor): registers `target` in its window, which needs
// `property list<Item> blurItems` and `BackgroundEffect.blurRegion: BlurRegion { items: blurItems }`
// (windows listing their items in BlurRegion directly need nothing).
// Otherwise the shell draws the blurred wallpaper under the target itself.
Item {
    id: root
    property Item target: parent
    // false = no blur for this target at all
    property bool active: true
    readonly property bool compositor: Config.options.appearance.blur.compositor
    // Same filter as BlurRegion: nothing to blur behind an invisible or fully transparent fill
    readonly property bool shown: active && target !== null && target.visible && target.opacity > 0 && (target.color?.a ?? 1) > 0
    // Re-read on Window.window changes: items created inside a Loader get their window only after reparenting
    readonly property var win: Window.window ? QsWindow.window : null

    // Below the target's own fill
    z: -1
    width: target?.width ?? 0
    height: target?.height ?? 0

    function register() {
        if (win?.blurItems === undefined)
            return;
        const has = win.blurItems.includes(target);
        const want = compositor && active;
        if (want && !has)
            win.blurItems.push(target);
        else if (!want && has)
            win.blurItems = win.blurItems.filter(i => i !== target);
    }
    onWinChanged: register()
    onCompositorChanged: register()
    onActiveChanged: register()

    // Window size changes move the target without changing its own geometry; reassigning the list makes BlurRegion re-read it
    Connections {
        target: root.Window.window
        function onWidthChanged() { root.reannounce(); }
        function onHeightChanged() { root.reannounce(); }
    }
    function reannounce() {
        if (!compositor || win?.blurItems === undefined) return;
        // Reassigning identical contents does not emit a change, so clear first
        const items = [...win.blurItems];
        win.blurItems = [];
        win.blurItems = items;
    }
    Component.onDestruction: if (win?.blurItems !== undefined) win.blurItems = win.blurItems.filter(i => i !== target)

    Loader {
        anchors.fill: parent
        active: !root.compositor && root.shown
        // By URL: WindowGlass -> FastBlurred -> BlurSource would otherwise be a type cycle
        source: active ? Qt.resolvedUrl("WindowGlass.qml") : ""
        onLoaded: {
            item.blurMode = true;
            item.cardRadius = Qt.binding(() => Math.max(root.target?.radius ?? 0, root.target?.topLeftRadius ?? 0));
        }
    }
}
