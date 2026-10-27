import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

MaterialSymbol {
    id: root
    readonly property bool materialPill: Config.options.bar.cornerStyle === 3
        && !(GlobalStates.dynamicIslandEnabled && Config.options.bar.dynamicIsland.rightWidget === "systemIcons")
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
    readonly property bool showPing: !Notifications.silent && Notifications.unread > 0
    // Keeps the last count on the badge while it shrinks away
    property int displayedCount: Notifications.unread
    Connections {
        target: Notifications
        function onUnreadChanged() {
            if (Notifications.unread > 0) root.displayedCount = Notifications.unread;
        }
    }
    text: Notifications.silent ? "notifications_paused" : "notifications"
    iconSize: Appearance.font.pixelSize.larger
    color: root.materialPill ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1

    Rectangle {
        id: notifPing
        visible: scale > 0
        scale: root.showPing ? 1 : 0
        opacity: root.showPing ? 1 : 0
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: root.showUnreadCount ? 0 : 1
            topMargin: root.showUnreadCount ? 0 : 3
        }
        radius: Appearance.rounding.full
        color: root.materialPill ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
        z: 1

        implicitHeight: root.showUnreadCount ? Math.max(notificationCounterText.implicitWidth, notificationCounterText.implicitHeight) : 8
        implicitWidth: implicitHeight

        StyledText {
            id: notificationCounterText
            visible: root.showUnreadCount
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: root.materialPill ? Appearance.colors.colPrimary : Appearance.colors.colLayer0
            text: root.displayedCount
        }
    }
}
