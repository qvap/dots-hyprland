pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.ii.mediaControls

Loader {
    id: root
    required property Item host
    anchors.centerIn: parent
    width: root.host.playerWidth
    height: root.host.playerHeight
    active: root.host.exposed && root.host.activePlayer !== null
    asynchronous: true
    onStatusChanged: if (status === Loader.Ready && root.host.expanded) root.host.expansion = 1
    visible: root.host.expansion > 0
    opacity: Math.max(0, (root.host.expansion - 0.25) / 0.75)
    enabled: root.host.expanded && root.host.expansion > 0.95
    z: 1
    sourceComponent: PlayerControl {
        player: root.host.activePlayer
        visualizerPoints: GlobalStates.visualizerPoints
        animateTrackChanges: false
        backgroundMargin: 0
        radius: 24
        // The morph surface already clips and shadows the whole card.
        clipBackground: false
        showShadow: false
    }
}
