import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: notificationPopup

    PanelWindow {
        id: root
        readonly property string popupPosition: Config.options.notifications.position
        readonly property bool popupAtBottom: popupPosition.startsWith("bottom_")
        readonly property bool popupAtLeft: popupPosition.endsWith("_left")
        readonly property bool popupAtRight: popupPosition.endsWith("_right")
        visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => Config.options.notifications.forceMonitor.enable ? s.name === Config.options.notifications.forceMonitor.name : s.name === Hyprland.focusedMonitor?.name) ?? null

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        anchors {
            top: true
            left: root.popupAtLeft
            right: root.popupAtRight
            bottom: true
        }

        mask: Region {
            item: listview.contentItem
        }

        color: "transparent"
        implicitWidth: Appearance.sizes.notificationPopupWidth

        NotificationListView {
            id: listview
            x: root.popupAtLeft ? 4 : root.popupAtRight ? parent.width - width - 4 : (parent.width - width) / 2
            y: root.popupAtBottom ? parent.height - height - 4 : 4
            height: Math.min(contentHeight, parent.height - 8)
            implicitWidth: parent.width - Appearance.sizes.elevationMargin * 2
            width: implicitWidth
            verticalLayoutDirection: root.popupAtBottom ? ListView.BottomToTop : ListView.TopToBottom
            popup: true
        }
    }
}
