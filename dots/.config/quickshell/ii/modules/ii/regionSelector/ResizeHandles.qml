pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import "AnnotationGeometry.js" as Geometry

Item {
    id: root
    required property rect targetRect
    required property rect limitRect
    property bool cornersOnly: false
    signal resizeStarted()
    signal resized(rect bounds)
    signal resizeFinished()

    Rectangle {
        x: root.targetRect.x
        y: root.targetRect.y
        width: root.targetRect.width
        height: root.targetRect.height
        color: "transparent"
        border.width: 1
        border.color: Appearance.colors.colPrimary
    }
    Repeater {
        model: root.cornersOnly ? ["nw", "ne", "se", "sw"] : ["nw", "n", "ne", "e", "se", "s", "sw", "w"]
        delegate: Rectangle {
            id: handle
            required property string modelData
            width: 12
            height: 12
            radius: 3
            color: Appearance.colors.colPrimary
            border.color: Appearance.colors.colOnPrimary
            border.width: 1
            x: Math.max(0, Math.min(root.width - width, root.targetRect.x + (modelData.includes("w") ? 0 : modelData.includes("e") ? root.targetRect.width : root.targetRect.width / 2) - width / 2))
            y: Math.max(0, Math.min(root.height - height, root.targetRect.y + (modelData.includes("n") ? 0 : modelData.includes("s") ? root.targetRect.height : root.targetRect.height / 2) - height / 2))
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                preventStealing: true
                cursorShape: handle.modelData === "n" || handle.modelData === "s" ? Qt.SizeVerCursor
                    : handle.modelData === "e" || handle.modelData === "w" ? Qt.SizeHorCursor
                    : handle.modelData === "nw" || handle.modelData === "se" ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                property point startPoint
                property rect startRect
                onPressed: mouse => {
                    startPoint = mapToItem(root, mouse.x, mouse.y);
                    startRect = root.targetRect;
                    root.resizeStarted();
                }
                onPositionChanged: mouse => {
                    if (!pressed) return;
                    const point = mapToItem(root, mouse.x, mouse.y);
                    const rect = Geometry.resize(startRect, handle.modelData,
                        point.x - startPoint.x, point.y - startPoint.y, root.limitRect, 12, root.cornersOnly);
                    root.resized(Qt.rect(rect.x, rect.y, rect.width, rect.height));
                }
                onReleased: root.resizeFinished()
                onCanceled: root.resizeFinished()
            }
        }
    }
}
