import QtQuick
import Quickshell

// Compositor-side blur (ext-background-effect-v1) under each visible, non-transparent item.
// Use as `BackgroundEffect.blurRegion: BlurRegion { items: [...] }` on a window.
Region {
    id: root
    property list<Item> items
    // Mapped rects don't track geometry by themselves; bumping this re-reads them without clearing the region
    property int revision: 0
    // Shrinks each rect (and its corner radius) so the pixel-aligned region stays inside antialiased edges
    property real inset: 0
    onItemsChanged: revision++

    regions: itemRegions.instances
    property Variants itemRegions: Variants {
        model: root.items
        Region {
            id: itemRegion
            required property Item modelData
            readonly property bool shown: modelData && modelData.visible && modelData.opacity > 0 && (modelData.color?.a ?? 1) > 0
            // Mapped to window coordinates so parent movement and transforms (e.g. a scale-in transition) are included
            readonly property rect mapped: {
                root.revision;
                return shown ? modelData.mapToItem(null, 0, 0, modelData.width, modelData.height) : Qt.rect(0, 0, 0, 0);
            }
            x: mapped.x + root.inset
            y: mapped.y + root.inset
            width: Math.max(0, mapped.width - root.inset * 2)
            height: Math.max(0, mapped.height - root.inset * 2)
            radius: shown && modelData.width > 0 ? Math.max(0, Math.max(modelData.radius ?? 0, modelData.topLeftRadius ?? 0) * mapped.width / modelData.width - root.inset) : 0

            component GeometryWatcher: Connections {
                function onXChanged() { root.revision++; }
                function onYChanged() { root.revision++; }
                function onWidthChanged() { root.revision++; }
                function onHeightChanged() { root.revision++; }
                function onScaleChanged() { root.revision++; }
            }
            property GeometryWatcher selfWatcher: GeometryWatcher { target: itemRegion.modelData }
            property GeometryWatcher parentWatcher: GeometryWatcher { target: itemRegion.modelData?.parent ?? null }
            property GeometryWatcher grandparentWatcher: GeometryWatcher { target: itemRegion.modelData?.parent?.parent ?? null }
        }
    }
}
