import QtQuick
import Quickshell

// Compositor blur (ext-background-effect-v1) behind `target` (put it inside the target's background).
// Its window needs `property list<Item> blurItems: []` and
// `BackgroundEffect.blurRegion: BlurRegion { items: blurItems }`.
Item {
    id: root
    property Item target: parent
    // false = no blur for this target at all
    property bool active: true
    // Blur only where the target is drawn (by its alpha) instead of under its whole rounded rect.
    // The shape is read back from the GPU: change `shapeKey` whenever the drawing changes.
    property bool shaped: false
    property var shapeKey

    // Read by BlurRegion: the target in window coordinates, its corner radii (top left, top right,
    // bottom right, bottom left) and, when shaped, its opaque rows in target coordinates
    property rect area: Qt.rect(0, 0, 0, 0)
    property var radii: [0, 0, 0, 0]
    property var shapeRects: []

    // Re-read on Window.window changes: items created inside a Loader get their window only after reparenting
    readonly property var win: Window.window ? QsWindow.window : null
    readonly property bool registered: active && win?.blurItems !== undefined

    function register() {
        if (!win)
            return;
        if (win.blurItems === undefined) {
            console.warn("BlurSource: the window of", target, "has no blurItems, so it is not blurred");
            return;
        }
        const has = win.blurItems.includes(root);
        if (active && !has)
            win.blurItems.push(root);
        else if (!active && has)
            win.blurItems = win.blurItems.filter(i => i !== root);
        sync();
        if (shaped)
            shapeTimer.restart();
    }
    onWinChanged: register()
    onActiveChanged: register()
    Component.onDestruction: if (win?.blurItems !== undefined) win.blurItems = win.blurItems.filter(i => i !== root)

    // Geometry is re-read on every frame the window draws, so any moving ancestor, transform or
    // fade is caught on the frame it shows up in; an idle window draws no frames and costs nothing
    Connections {
        target: root.registered ? root.Window.window : null
        function onAfterAnimating() { root.sync(); }
    }

    function sync() {
        const t = target;
        let opacity = active && t?.visible ? 1 : 0;
        for (let it = t; it && opacity > 0; it = it.parent)
            opacity *= it.opacity;
        // Nothing to blur behind an invisible or fully transparent fill
        if (opacity <= 0 || (t.color?.a ?? 1) <= 0 || t.width <= 0 || t.height <= 0) {
            if (area.width > 0 || area.height > 0)
                area = Qt.rect(0, 0, 0, 0);
            return;
        }
        const r = t.mapToItem(null, 0, 0, t.width, t.height);
        if (r.x !== area.x || r.y !== area.y || r.width !== area.width || r.height !== area.height)
            area = r;
        const k = r.width / t.width;
        const radius = t.radius ?? 0;
        const next = [t.topLeftRadius ?? radius, t.topRightRadius ?? radius, t.bottomRightRadius ?? radius, t.bottomLeftRadius ?? radius].map(v => v * k);
        if (next.some((v, i) => v !== radii[i]))
            radii = next;
    }

    // Shape read-back: render the target offscreen and keep its rows of covered pixels
    onShapedChanged: shapeTimer.restart()
    onShapeKeyChanged: shapeTimer.restart()
    Connections {
        target: root.shaped ? root.target : null
        function onWidthChanged() { shapeTimer.restart(); }
        function onHeightChanged() { shapeTimer.restart(); }
    }
    Timer {
        id: shapeTimer
        interval: 400 // let the drawing settle: layout, async loads, shape morphs
        onTriggered: root.readShape()
    }
    function readShape() {
        if (!shaped || !registered || !target || target.width < 1 || target.height < 1) {
            shapeRects = [];
            return;
        }
        const size = Qt.size(Math.ceil(target.width), Math.ceil(target.height));
        target.grabToImage(result => {
            shapeReader.width = size.width;
            shapeReader.height = size.height;
            shapeReader.grab = result;
            shapeReader.loadImage(result.url);
        }, size);
    }
    Canvas {
        id: shapeReader
        property var grab: null
        opacity: 0 // only read back, never shown
        onImageLoaded: requestPaint()
        onPaint: {
            if (!grab)
                return;
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.drawImage(grab.url, 0, 0);
            const px = ctx.getImageData(0, 0, width, height).data;
            unloadImage(grab.url);
            grab = null;
            root.shapeRects = root.coveredRects(px, width, height);
        }
    }
    // Runs of pixels above half the strongest alpha (the antialiased outline's midpoint); runs repeated
    // on consecutive rows are merged into taller rects
    function coveredRects(px, w, h) {
        let maxAlpha = 0;
        for (let i = 3; i < px.length; i += 4)
            maxAlpha = Math.max(maxAlpha, px[i]);
        const threshold = maxAlpha / 2;
        const done = [];
        let open = new Map(); // "x0,x1" -> rect still growing downwards
        for (let y = 0; y < h; y++) {
            const next = new Map();
            let start = -1;
            for (let x = 0; x <= w; x++) {
                const covered = x < w && px[(y * w + x) * 4 + 3] > threshold;
                if (covered && start < 0) {
                    start = x;
                } else if (!covered && start >= 0) {
                    const key = start + "," + x;
                    const rect = open.get(key) ?? { x: start, y: y, width: x - start, height: 0 };
                    rect.height++;
                    open.delete(key);
                    next.set(key, rect);
                    start = -1;
                }
            }
            open.forEach(rect => done.push(rect));
            open = next;
        }
        open.forEach(rect => done.push(rect));
        return done.map(r => Qt.rect(r.x, r.y, r.width, r.height));
    }
}
