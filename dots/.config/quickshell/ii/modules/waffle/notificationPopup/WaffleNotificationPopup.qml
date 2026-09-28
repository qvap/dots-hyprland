import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.notificationCenter

Scope {
    id: notificationPopup

    PanelWindow {
        id: root
        readonly property string popupPosition: Config.options.notifications.position
        readonly property bool popupAtBottom: popupPosition.startsWith("bottom_")
        readonly property bool popupAtLeft: popupPosition.endsWith("_left")
        readonly property bool popupAtRight: popupPosition.endsWith("_right")
        visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

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
        implicitWidth: listview.implicitWidth

        WListView {
            id: listview
            anchors {
                right: parent.right
                left: parent.left
            }
            y: root.popupAtBottom ? parent.height - height : 0
            leftMargin: 16
            rightMargin: 16
            topMargin: 16
            bottomMargin: 16

            height: Math.min(contentItem.height + topMargin + bottomMargin, parent.height)
            width: parent.width - Appearance.sizes.elevationMargin * 2
            
            implicitWidth: 396
            spacing:12

            model: ScriptModel {
                values: Notifications.popupList
            }
            delegate: WSingleNotification {
                required property var modelData
                notification: modelData
                width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
            }
        }
    }
}
