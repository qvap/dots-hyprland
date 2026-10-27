import QtQuick
import qs.modules.common.widgets

IconToolbarButton {
    scale: visible ? 1 : 0.9
    Behavior on scale {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    Behavior on x {
        enabled: visible
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
    Behavior on y {
        enabled: visible
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
}
