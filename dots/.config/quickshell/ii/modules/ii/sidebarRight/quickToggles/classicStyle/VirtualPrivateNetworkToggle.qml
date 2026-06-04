import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarRight.quickToggles
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

QuickToggleButton {
    toggled: Vpn.status === "active"
    buttonIcon: "vpn_key"
    onClicked: Vpn.toggle()
    altAction: () => {
    // Will open the VPN Dialog (handled by ClassicQuickPanel)
    }
    StyledToolTip {
        text: Translation.tr("VPN | Right-click to configure")
    }
}
