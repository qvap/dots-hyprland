import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("VPN")
    statusText: {
        if (Vpn.status === "active") return Translation.tr("Connected");
        if (Vpn.status === "connecting") return Translation.tr("Connecting");
        return Translation.tr("Disconnected");
    }
    tooltipText: Translation.tr("VPN | Right-click to configure")
    icon: "vpn_key"

    toggled: Vpn.status === "active" || Vpn.status === "connecting"
    mainAction: () => Vpn.toggle()
    hasMenu: true
}
