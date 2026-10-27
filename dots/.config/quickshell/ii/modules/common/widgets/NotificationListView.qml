pragma ComponentBehavior: Bound

import qs.modules.common.widgets
import qs.modules.common
import qs.services
import QtQuick
import Quickshell

StyledListView { // Scrollable window
    id: root
    property bool popup: false
    // While false the list stays empty, so items added later play their add transition
    property bool showItems: true

    spacing: 3

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    model: ScriptModel {
        values: !root.showItems ? [] : root.popup ? Notifications.popupAppNameList : Notifications.appNameList
    }
    delegate: NotificationGroup {
        required property int index
        required property var modelData
        popup: root.popup
        width: ListView.view.width // https://doc.qt.io/qt-6/qml-qtquick-listview.html
        // The group leaves the model before its remove transition ends; keep showing the last one
        readonly property var liveGroup: popup ? Notifications.popupGroupsByAppName[modelData] : Notifications.groupsByAppName[modelData]
        property var lastGroup: liveGroup
        onLiveGroupChanged: if (liveGroup) lastGroup = liveGroup
        notificationGroup: liveGroup ?? lastGroup
    }
}
