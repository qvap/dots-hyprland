import QtQuick

// The morphing media widgets of one bar window. Only one of them is open at a
// time, and the window's input mask follows the one being pulled or open.
QtObject {
    id: root
    property var morphs: []

    readonly property bool expanded: morphs.some(morph => morph.expanded)
    readonly property bool interacting: morphs.some(morph => morph.interacting)
    readonly property Item active: morphs.find(morph => morph.expanded || morph.dragging)
        ?? morphs.find(morph => morph.pullSurface !== null || morph.expandedSurface !== null)
        ?? null

    function register(morph) {
        if (!morphs.includes(morph)) morphs = [...morphs, morph];
    }

    function unregister(morph) {
        if (morphs.includes(morph)) morphs = morphs.filter(item => item !== morph);
    }

    function collapseAll(except) {
        for (const morph of morphs) {
            if (morph !== except) morph.expanded = false;
        }
    }
}
