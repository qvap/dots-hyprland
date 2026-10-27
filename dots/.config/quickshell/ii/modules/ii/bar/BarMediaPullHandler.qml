pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common

DragHandler {
    id: root
    required property Item host
    target: null
    enabled: root.host.activePlayer !== null && !root.host.expanded && (root.host.expansion === 0 || root.host.dragging)
    acceptedButtons: Qt.LeftButton
    grabPermissions: PointerHandler.CanTakeOverFromAnything
    xAxis.enabled: root.host.vertical
    yAxis.enabled: !root.host.vertical
    onActiveChanged: {
        if (active) root.beginPull();
        else if (root.host.dragging) root.cancelPull();
    }
    onTranslationChanged: {
        const distance = root.host.vertical ? activeTranslation.x : activeTranslation.y;
        if (active) root.updatePull(distance * (Config.options.bar.bottom ? -1 : 1));
    }
    onCanceled: if (root.host.dragging) root.cancelPull()


    function beginPull() {
        if (!host.activePlayer) return;
        host.captureBounds();
        host.dragging = true;
        host.pullDistance = 0;
        host.expansion = 0;
    }

    function updatePull(distance) {
        if (!host.dragging) return;
        host.pullDistance = Math.max(0, distance);
        if (host.pullDistance < host.pullThreshold) {
            host.expansion = host.pullDistance / host.pullThreshold * 0.12;
            return;
        }
        // Commit as soon as the pointer crosses the threshold.
        host.dragging = false;
        host.expanded = true;
    }

    function cancelPull() {
        host.dragging = false;
        host.pullDistance = 0;
        host.expansion = 0;
    }
}
