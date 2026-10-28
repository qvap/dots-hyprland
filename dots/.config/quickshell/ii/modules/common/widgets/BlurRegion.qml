import QtQuick
import Quickshell

// Compositor blur (ext-background-effect-v1) under every BlurSource of a window:
// `BackgroundEffect.blurRegion: BlurRegion { items: blurItems }` (BlurSources add themselves to `blurItems`)
Region {
    id: root
    property list<Item> items
    // Shrinks each rect (and its corners) so the pixel-aligned region stays inside antialiased edges
    property real inset: 0

    regions: sourceRegions.instances
    property Variants sourceRegions: Variants {
        model: root.items
        Region {
            id: sourceRegion
            required property Item modelData
            readonly property rect area: modelData.area
            readonly property var radii: modelData.radii
            readonly property bool shaped: modelData.shaped
            // Region coordinates are ints: snap every edge inwards instead of letting both truncate leftwards
            readonly property int left: Math.ceil(area.x + root.inset)
            readonly property int top: Math.ceil(area.y + root.inset)
            x: left
            y: top
            width: shaped ? 0 : Math.max(0, Math.floor(area.x + area.width - root.inset) - left)
            height: shaped ? 0 : Math.max(0, Math.floor(area.y + area.height - root.inset) - top)
            topLeftRadius: Math.max(0, radii[0] - root.inset)
            topRightRadius: Math.max(0, radii[1] - root.inset)
            bottomRightRadius: Math.max(0, radii[2] - root.inset)
            bottomLeftRadius: Math.max(0, radii[3] - root.inset)

            // A shaped source is the union of its covered rows instead
            regions: shapeParts.instances
            property Variants shapeParts: Variants {
                model: sourceRegion.shaped && sourceRegion.area.width > 0 ? sourceRegion.modelData.shapeRects : []
                Region {
                    required property rect modelData
                    readonly property real scale: sourceRegion.area.width / Math.max(1, sourceRegion.modelData.target.width)
                    readonly property int left: Math.ceil(sourceRegion.area.x + modelData.x * scale + root.inset)
                    x: left
                    y: Math.round(sourceRegion.area.y + modelData.y * scale)
                    width: Math.max(0, Math.floor(sourceRegion.area.x + (modelData.x + modelData.width) * scale - root.inset) - left)
                    height: Math.round(modelData.height * scale)
                }
            }
        }
    }
}
