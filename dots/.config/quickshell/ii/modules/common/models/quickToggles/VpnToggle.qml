import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("VPN")
    statusText: Vpn.statusText
    tooltipText: Translation.tr("VPN | Right-click to configure")
    icon: "vpn_key"

    toggled: Vpn.on
    mainAction: () => Vpn.toggle()
    hasMenu: true
}
