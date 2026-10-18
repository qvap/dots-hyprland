//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ApplicationWindow {
    id: root

    property real contentPadding: 8
    property int currentPage: 0
    property var pages: [
        {
            name: Translation.tr("Overview"),
            icon: "vpn_key",
            component: overviewPage
        },
        {
            name: Translation.tr("Nodes"),
            icon: "account_tree",
            component: nodesPage
        },
        {
            name: Translation.tr("Routing"),
            icon: "alt_route",
            component: routingPage
        }
    ]

    visible: true
    onClosing: Qt.quit()
    title: "illogical-impulse VPN Details"

    minimumWidth: 750
    minimumHeight: 500
    width: 1000
    height: 680
    color: Appearance.m3colors.m3background

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Vpn.refresh();
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.contentPadding
        }

        Keys.onPressed: event => {
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown) {
                    root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    root.currentPage = Math.max(root.currentPage - 1, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab) {
                    root.currentPage = (root.currentPage + 1) % root.pages.length;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backtab) {
                    root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length;
                    event.accepted = true;
                }
            }
        }

        Item {
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)

            StyledText {
                id: titleText
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("VPN") + " " + Translation.tr("Details")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }

            RowLayout {
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Appearance.m3colors.m3surfaceContainerLow
            radius: Appearance.rounding.windowRounding - root.contentPadding

            Loader {
                id: pageLoader
                anchors.fill: parent
                opacity: 1.0

                Component.onCompleted: {
                    sourceComponent = root.pages[0].component;
                }

                Connections {
                    target: root
                    function onCurrentPageChanged() {
                        switchAnim.complete();
                        switchAnim.start();
                    }
                }

                SequentialAnimation {
                    id: switchAnim

                    NumberAnimation {
                        target: pageLoader
                        properties: "opacity"
                        from: 1
                        to: 0
                        duration: 100
                        easing.type: Appearance.animation.elementMoveExit.type
                        easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                    }
                    ParallelAnimation {
                        PropertyAction {
                            target: pageLoader
                            property: "sourceComponent"
                            value: root.pages[root.currentPage].component
                        }
                        PropertyAction {
                            target: pageLoader
                            property: "anchors.topMargin"
                            value: 20
                        }
                    }
                    ParallelAnimation {
                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 0
                            to: 1
                            duration: 200
                            easing.type: Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                        }
                        NumberAnimation {
                            target: pageLoader
                            properties: "anchors.topMargin"
                            to: 0
                            duration: 200
                            easing.type: Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                        }
                    }
                }
            }
        }

        Rectangle {
            id: bottomTabsPanel
            Layout.fillWidth: true
            Layout.margins: 5
            implicitHeight: 72
            color: Appearance.m3colors.m3surfaceContainerLow
            radius: Appearance.rounding.windowRounding - root.contentPadding

            RowLayout {
                anchors {
                    fill: parent
                    margins: 8
                }
                spacing: 8

                Repeater {
                    model: root.pages

                    TabButton {
                        required property int index
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        padding: 0
                        checked: root.currentPage === index
                        onClicked: root.currentPage = index
                        background: null
                        PointingHandInteraction {}

                        contentItem: Rectangle {
                            radius: Appearance.rounding.full
                            color: parent.checked ? (parent.down ? Appearance.colors.colSecondaryContainerActive : parent.hovered ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer) : (parent.down ? Appearance.colors.colLayer1Active : parent.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1))

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 2

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.icon
                                    iconSize: 24
                                    fill: root.currentPage === index ? 1 : 0
                                    font.weight: (root.currentPage === index || parent.parent.hovered) ? Font.DemiBold : Font.Normal
                                    color: root.currentPage === index ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1

                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.name
                                    font.pixelSize: 14
                                    color: root.currentPage === index ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1

                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component OverviewPage: ContentPage {
        forceWidth: true
        baseWidth: 620

        ContentSection {
            icon: "monitoring"
            title: Translation.tr("Status")

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.max(180, statusContent.implicitHeight + 28)
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                RowLayout {
                    id: statusContent
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 22
                        rightMargin: 22
                    }
                    spacing: 20

                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 140
                        implicitHeight: 140

                        Item {
                            id: vpnCookie
                            anchors.centerIn: parent
                            implicitWidth: 120
                            implicitHeight: 120
                            rotation: continuousRotation + leapRotation

                            property bool loading: Vpn.status === "connecting" || Vpn.status === "disconnecting"
                            property double baseShapeSize: 120
                            property double leapZoomSize: 120 * 1.2
                            property double leapZoomProgress: 0
                            property list<var> shapes: [MaterialShape.Shape.SoftBurst, MaterialShape.Shape.Cookie9Sided, MaterialShape.Shape.Pentagon, MaterialShape.Shape.Pill, MaterialShape.Shape.Sunny, MaterialShape.Shape.Cookie4Sided, MaterialShape.Shape.Oval]
                            property int shapeIndex: 1
                            property double continuousRotation: 0
                            property double leapRotation: 0

                            onLoadingChanged: {
                                if (!loading) {
                                    leapAnimation.stop();
                                    leapRotation = 0;
                                    leapZoomProgress = 0;
                                    shapeIndex = 1;
                                }
                            }

                            RotationAnimation on continuousRotation {
                                running: vpnCookie.loading || Vpn.status === "active"
                                duration: 12000
                                easing.type: Easing.Linear
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                            }
                            Timer {
                                interval: 800
                                running: vpnCookie.loading
                                repeat: true
                                onTriggered: leapAnimation.start()
                            }
                            ParallelAnimation {
                                id: leapAnimation
                                PropertyAction {
                                    target: vpnCookie
                                    property: "shapeIndex"
                                    value: (vpnCookie.shapeIndex + 1) % vpnCookie.shapes.length
                                }
                                RotationAnimation {
                                    target: vpnCookie
                                    direction: RotationAnimation.Shortest
                                    property: "leapRotation"
                                    to: (vpnCookie.leapRotation + 90) % 360
                                    duration: 350
                                    easing.type: Easing.InOutQuad
                                }
                                NumberAnimation {
                                    target: vpnCookie
                                    property: "leapZoomProgress"
                                    from: 0
                                    to: 1
                                    duration: 750
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Appearance.animationCurves.standard
                                }
                            }

                            MaterialShape {
                                id: shape
                                anchors.centerIn: parent
                                shape: vpnCookie.loading ? vpnCookie.shapes[vpnCookie.shapeIndex] : MaterialShape.Shape.Cookie9Sided
                                implicitSize: {
                                    if (!vpnCookie.loading)
                                        return vpnCookie.baseShapeSize;
                                    const leapZoomDiff = vpnCookie.leapZoomSize - vpnCookie.baseShapeSize;
                                    const progressFirstHalf = Math.min(vpnCookie.leapZoomProgress, 0.5) * 2;
                                    const progressSecondHalf = Math.max(vpnCookie.leapZoomProgress - 0.5, 0) * 2;
                                    return vpnCookie.baseShapeSize + leapZoomDiff * progressFirstHalf - leapZoomDiff * progressSecondHalf;
                                }
                                color: Vpn.blocking ? Appearance.colors.colErrorContainer : Vpn.on ? (vpnMouseArea.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer) : (vpnMouseArea.containsMouse ? Appearance.colors.colLayer3Hover : ColorUtils.transparentize(Appearance.colors.colLayer3))

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(shape)
                                }

                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: Vpn.blocking ? "gpp_bad" : "power_settings_new"
                            iconSize: 42
                            color: Vpn.blocking ? Appearance.colors.colOnErrorContainer : Vpn.on ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                        }

                        ButtonMouseArea {
                            id: vpnMouseArea
                            anchors.fill: parent
                            onClicked: Vpn.toggle()
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            text: Vpn.statusText
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.weight: 600
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Vpn.activeProfile.length > 0 ? Vpn.activeProfile : Translation.tr("No active profile")
                            elide: Text.ElideRight
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }

                        StyledText {
                            visible: Vpn.lastError.length > 0
                            Layout.fillWidth: true
                            text: Vpn.lastError
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colError
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
            }

            NoticeBox {
                visible: Vpn.blocking
                Layout.fillWidth: true
                materialIcon: "gpp_bad"
                text: Translation.tr("The VPN is down and the kill switch blocks all traffic. Turn the VPN on again, or release the block.")

                StyledButton {
                    text: Translation.tr("Release block")
                    enabled: Vpn.busy === ""
                    onClicked: Vpn.release()
                }
            }
        }

        ContentSection {
            icon: "hub"
            title: Translation.tr("Active node")

            ProfileSelector {}
        }

        ContentSection {
            icon: "shield_lock"
            title: Translation.tr("Connection")

            ConfigSwitch {
                id: autostartSwitch
                buttonIcon: "start"
                text: Vpn.busy === "autostart" ? Translation.tr("Applying...") : Translation.tr("Start at boot")
                enabled: Vpn.busy === ""
                checked: Vpn.enabled
                onCheckedChanged: {
                    if (checked !== Vpn.enabled)
                        Vpn.setAutostart(checked);
                }
                Connections {
                    target: Vpn
                    // A dismissed password prompt: back to the truth
                    function onBusyChanged() {
                        if (Vpn.busy === "")
                            autostartSwitch.checked = Qt.binding(() => Vpn.enabled);
                    }
                }
            }

            ConfigSwitch {
                id: killswitchSwitch
                buttonIcon: "gpp_maybe"
                text: Vpn.busy === "killswitch" ? Translation.tr("Applying...") : Translation.tr("Kill switch")
                enabled: Vpn.busy === ""
                checked: Vpn.killswitch
                onCheckedChanged: {
                    if (checked !== Vpn.killswitch)
                        Vpn.setKillswitch(checked);
                }
                Connections {
                    target: Vpn
                    function onBusyChanged() {
                        if (Vpn.busy === "")
                            killswitchSwitch.checked = Qt.binding(() => Vpn.killswitch);
                    }
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                text: Translation.tr("While the VPN is on, the kill switch lets traffic out only through the tunnel (and to the local network). If sing-box crashes, everything stays blocked until the VPN is back or you release the block; turning the VPN off lifts it. Needs nftables.")
            }

            ConfigRow {
                uniform: true
                ActionButton {
                    text: Vpn.busy === "restart" ? Translation.tr("Restarting...") : Translation.tr("Restart")
                    enabled: Vpn.busy === "" && Vpn.on
                    onClicked: Vpn.restart()
                }
                ActionButton {
                    text: Translation.tr("Logs")
                    onClicked: Vpn.openLogs()
                }
            }

            ConfigRow {
                visible: !Vpn.passwordless
                uniform: true
                ActionButton {
                    text: Translation.tr("Turn on/off without password")
                    enabled: Vpn.busy === ""
                    onClicked: Vpn.setupPasswordless()
                }
            }
        }

        ContentSection {
            icon: "speed"
            title: Translation.tr("Diagnostics")

            ConfigRow {
                uniform: true
                ActionButton {
                    text: Vpn.isPinging ? Translation.tr("Pinging...") : Vpn.pingResult !== "" ? Translation.tr("Ping") + ": " + Vpn.pingResult : Translation.tr("Check Ping")
                    enabled: !Vpn.isPinging
                    onClicked: Vpn.testPing()
                }
                ActionButton {
                    text: Vpn.isSpeedtesting ? Translation.tr("Testing...") : Vpn.speedResult !== "" ? Vpn.speedResult : Translation.tr("Speedtest")
                    enabled: !Vpn.isSpeedtesting
                    onClicked: Vpn.testSpeed()
                }
            }
        }

        ContentSection {
            icon: "settings_backup_restore"
            title: Translation.tr("Subscription")

            StyledText {
                visible: Vpn.needsSubscription || Vpn.subscriptionStatus.length > 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Vpn.subscriptionStatus.length > 0 ? Vpn.subscriptionStatus : Translation.tr("Enter subscription URL to continue.")
            }

            MaterialTextField {
                id: detailsSubscriptionField
                Layout.fillWidth: true
                placeholderText: Vpn.hasSubscription ? Translation.tr("New subscription URL") : Translation.tr("Subscription URL")
                text: Vpn.subscriptionUrl
                onAccepted: Vpn.subscribe(text)
            }

            ConfigRow {
                uniform: true
                ActionButton {
                    text: Vpn.busy === "subscribe" ? Translation.tr("Loading...") : Translation.tr("Load subscription")
                    enabled: Vpn.busy === "" && detailsSubscriptionField.text.trim().length > 0
                    onClicked: Vpn.subscribe(detailsSubscriptionField.text)
                }
                ActionButton {
                    text: Vpn.busy === "update" ? Translation.tr("Updating...") : Translation.tr("Update subscription")
                    enabled: Vpn.busy === "" && Vpn.hasSubscription
                    onClicked: Vpn.updateSubscription()
                }
            }
        }

        ContentSection {
            icon: "brightness_alert"
            title: Translation.tr("Danger Zone")
            color: Appearance.colors.colError
            iconColor: Appearance.colors.colError

            ConfigRow {
                uniform: true
                ActionButton {
                    id: deleteSubscriptionButton
                    property bool oneClicked: false
                    property string originalText: Vpn.busy === "unsubscribe" ? Translation.tr("Loading...") : Translation.tr("Delete subscription")
                    text: deleteSubscriptionButton.oneClicked ? Translation.tr("Click again to confirm") : deleteSubscriptionButton.originalText
                    enabled: Vpn.busy === "" && (Vpn.hasSubscription || Vpn.profiles.length > 0)
                    onClicked: {
                        if (deleteSubscriptionButton.oneClicked === false) {
                            deleteSubscriptionButton.oneClicked = true;
                        } else {
                            Vpn.deleteSubscription();
                            deleteSubscriptionButton.oneClicked = false;
                        }
                    }
                    colBackgroundUnchecked: Appearance.colors.colErrorContainer
                }
            }
        }
    }

    component NodesPage: ContentPage {
        forceWidth: true
        baseWidth: 620

        ContentSection {
            icon: "account_tree"
            title: Translation.tr("Nodes")

            StyledText {
                visible: Vpn.profiles.length === 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("No nodes yet: load a subscription on the Overview page.")
            }

            NoticeBox {
                visible: Vpn.profiles.some(p => p.xray)
                Layout.fillWidth: true
                text: Translation.tr("Nodes marked \"xray\" (gRPC, XHTTP) run through Xray (xray.service): sing-box cannot carry them itself.")
            }

            Repeater {
                model: Vpn.profiles
                delegate: Rectangle {
                    id: nodeDelegate
                    required property var modelData
                    readonly property bool switching: Vpn.busy === "select" && Vpn.selecting === modelData.tag
                    Layout.fillWidth: true
                    implicitHeight: nodeRow.implicitHeight + 22
                    radius: Appearance.rounding.normal
                    color: modelData.isActive ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1

                    RowLayout {
                        id: nodeRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 14
                            rightMargin: 14
                        }
                        spacing: 12

                        MaterialSymbol {
                            text: nodeDelegate.modelData.isActive ? "radio_button_checked" : "radio_button_unchecked"
                            iconSize: 22
                            color: nodeDelegate.modelData.isActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: nodeDelegate.modelData.name
                                elide: Text.ElideRight
                                color: nodeDelegate.modelData.isActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: nodeDelegate.modelData.isActive ? Font.Medium : Font.Normal
                            }

                            StyledText {
                                text: nodeDelegate.switching ? Translation.tr("Switching node...") : nodeDelegate.modelData.type
                                color: nodeDelegate.modelData.isActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                opacity: nodeDelegate.modelData.isActive ? 0.72 : 1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }

                        ActionButton {
                            Layout.fillWidth: false
                            implicitWidth: 120
                            text: nodeDelegate.modelData.isActive ? Translation.tr("Connected") : Translation.tr("Select")
                            enabled: !nodeDelegate.modelData.isActive && Vpn.busy === ""
                            onClicked: Vpn.selectProfile(nodeDelegate.modelData.tag)
                        }
                    }
                }
            }
        }
    }

    component RoutingPage: ContentPage {
        id: routingRoot
        forceWidth: true
        baseWidth: 620

        property string action: "direct"
        property string kind: "domain"
        property string overlayError: ""
        readonly property var kinds: [
            {
                displayName: Translation.tr("Domain"),
                value: "domain",
                hint: "example.com"
            },
            {
                displayName: Translation.tr("Exact domain"),
                value: "full",
                hint: "www.example.com"
            },
            {
                displayName: Translation.tr("Keyword"),
                value: "keyword",
                hint: "google"
            },
            {
                displayName: "Regex",
                value: "regexp",
                hint: "^.+\\.example\\.com$"
            },
            {
                displayName: "IP CIDR",
                value: "ip",
                hint: "10.0.0.0/8"
            },
            {
                displayName: "Geosite",
                value: "geosite",
                hint: "youtube\ncategory-ru\ndiscord@metacubex"
            },
            {
                displayName: "GeoIP",
                value: "geoip",
                hint: "ru\ntelegram"
            },
            {
                displayName: Translation.tr("App"),
                value: "process",
                hint: "telegram-desktop\nsteam"
            },
            {
                displayName: Translation.tr("App path"),
                value: "path",
                hint: "/usr/bin/firefox"
            },
            {
                displayName: Translation.tr("Protocol"),
                value: "protocol",
                hint: "bittorrent\nquic"
            }
        ]

        function valuesFromText(text) {
            return text.split(/[\n,]+/).map(value => value.trim()).filter(value => value.length > 0);
        }

        NoticeBox {
            visible: Vpn.pending
            Layout.fillWidth: true
            materialIcon: "alt_route"
            text: Translation.tr("Routing changes are not applied yet. Applying restarts the VPN; if sing-box cannot start with them, the previous config is restored.")

            StyledButton {
                text: Vpn.isRoutingBusy ? Translation.tr("Applying...") : Translation.tr("Apply")
                enabled: Vpn.busy === ""
                onClicked: Vpn.applyRouting(false)
            }
        }

        ContentSection {
            icon: "call_split"
            title: Translation.tr("Unmatched traffic")

            ConfigSelectionArray {
                currentValue: Config.options.vpn.routing.defaultRoute
                onSelected: newValue => Config.options.vpn.routing.defaultRoute = newValue
                options: [
                    {
                        displayName: Translation.tr("Through VPN"),
                        icon: "vpn_lock",
                        value: "proxy"
                    },
                    {
                        displayName: Translation.tr("Direct"),
                        icon: "public",
                        value: "direct"
                    }
                ]
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Where traffic no rule matches goes. The local network always goes direct; DNS follows the route (direct names resolve directly, so CDNs answer with nearby servers).")
            }
        }

        ContentSection {
            icon: "alt_route"
            title: Translation.tr("Create routing rule")

            ContentSubsectionLabel {
                text: Translation.tr("Action")
            }

            ConfigSelectionArray {
                currentValue: routingRoot.action
                onSelected: newValue => routingRoot.action = newValue
                options: [
                    {
                        displayName: Translation.tr("Proxy"),
                        icon: "vpn_lock",
                        value: "proxy"
                    },
                    {
                        displayName: Translation.tr("Direct"),
                        icon: "public",
                        value: "direct"
                    },
                    {
                        displayName: Translation.tr("Block"),
                        icon: "block",
                        value: "block"
                    }
                ]
            }

            ContentSubsectionLabel {
                text: Translation.tr("Match by")
            }

            ConfigSelectionArray {
                currentValue: routingRoot.kind
                onSelected: newValue => routingRoot.kind = newValue
                options: routingRoot.kinds
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3surface
                border.width: 1
                border.color: ruleValuesField.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
                clip: true

                StyledTextArea {
                    id: ruleValuesField
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    background: null
                    clip: true
                    placeholderText: Translation.tr("Values, one per line or comma-separated") + "\n" + (routingRoot.kinds.find(k => k.value === routingRoot.kind)?.hint ?? "")
                    wrapMode: TextArea.Wrap
                }
            }

            StyledText {
                visible: routingRoot.kind === "geosite" || routingRoot.kind === "geoip"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Lists come from runetfreedom/russia-v2ray-rules-dat, MetaCubeX/meta-rules-dat and SagerNet (the first that has the name). Pin one with @: youtube@metacubex, ru@sagernet.")
            }

            ConfigRow {
                uniform: true
                ActionButton {
                    text: Translation.tr("Add rule")
                    enabled: ruleValuesField.text.trim().length > 0
                    onClicked: {
                        if (Vpn.addRule(routingRoot.action, routingRoot.kind, routingRoot.valuesFromText(ruleValuesField.text)))
                            ruleValuesField.text = "";
                    }
                }
            }
        }

        ContentSection {
            icon: "rule"
            title: Translation.tr("Current rules")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Config.options.vpn.routing.rules.length === 0 ? Translation.tr("No custom routing rules yet.") : Translation.tr("Checked top to bottom, the first match wins.")
            }

            Repeater {
                model: Config.options.vpn.routing.rules
                delegate: Rectangle {
                    id: ruleDelegate
                    required property var modelData
                    required property int index
                    readonly property bool ruleEnabled: modelData.enabled !== false
                    Layout.fillWidth: true
                    implicitHeight: ruleRow.implicitHeight + 22
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    opacity: ruleEnabled ? 1 : 0.6

                    RowLayout {
                        id: ruleRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 14
                            rightMargin: 8
                        }
                        spacing: 8

                        MaterialSymbol {
                            text: ruleDelegate.modelData.action === "block" ? "block" : ruleDelegate.modelData.action === "direct" ? "public" : "vpn_lock"
                            iconSize: 22
                            color: Appearance.colors.colOnLayer1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: (ruleDelegate.index + 1) + ". " + (ruleDelegate.modelData.action === "block" ? Translation.tr("Block") : ruleDelegate.modelData.action === "direct" ? Translation.tr("Direct") : Translation.tr("Proxy"))
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: (ruleDelegate.modelData.match ?? []).join(", ")
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }

                        StyledSwitch {
                            checked: ruleDelegate.ruleEnabled
                            onClicked: Vpn.setRuleEnabled(ruleDelegate.index, checked)
                        }
                        RuleButton {
                            glyph: "arrow_upward"
                            enabled: ruleDelegate.index > 0
                            onClicked: Vpn.moveRule(ruleDelegate.index, -1)
                        }
                        RuleButton {
                            glyph: "arrow_downward"
                            enabled: ruleDelegate.index < Config.options.vpn.routing.rules.length - 1
                            onClicked: Vpn.moveRule(ruleDelegate.index, 1)
                        }
                        RuleButton {
                            glyph: "delete"
                            onClicked: Vpn.removeRule(ruleDelegate.index)
                        }
                    }
                }
            }

            ConfigRow {
                uniform: true
                ActionButton {
                    text: Vpn.isRoutingBusy ? Translation.tr("Applying...") : Translation.tr("Apply")
                    enabled: Vpn.busy === "" && Vpn.pending
                    onClicked: Vpn.applyRouting(false)
                }
                ActionButton {
                    text: Translation.tr("Update lists")
                    enabled: Vpn.busy === "" && Vpn.hasSubscription
                    onClicked: Vpn.applyRouting(true)
                }
                ActionButton {
                    text: Translation.tr("Clear")
                    enabled: Config.options.vpn.routing.rules.length > 0
                    onClicked: Vpn.clearRules()
                }
            }
        }

        ContentSection {
            icon: "dns"
            title: Translation.tr("DNS")

            ConfigSwitch {
                buttonIcon: "frame_inspect"
                text: Translation.tr("Enable FakeIP")
                checked: Config.options.vpn.routing.fakeip
                onCheckedChanged: Config.options.vpn.routing.fakeip = checked
            }

            NoticeBox {
                Layout.fillWidth: true
                text: Translation.tr("FakeIP speeds up DNS resolution and prevents leaks, but may break some apps (Spotify, Discord, games). Disabled by default.")
            }

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Remote DNS server (DoH, through the VPN)")
                text: Config.options.vpn.routing.remoteDns
                onEditingFinished: Config.options.vpn.routing.remoteDns = text.trim()
            }
        }

        ContentSection {
            icon: "speed"
            title: "Hysteria2"

            ConfigSpinBox {
                icon: "upload"
                text: Translation.tr("Upload, Mbps (0 = from the subscription)")
                from: 0
                to: 10000
                stepSize: 10
                value: Config.options.vpn.routing.hysteria2UpMbps
                onValueChanged: Config.options.vpn.routing.hysteria2UpMbps = value
            }

            ConfigSpinBox {
                icon: "download"
                text: Translation.tr("Download, Mbps (0 = from the subscription)")
                from: 0
                to: 10000
                stepSize: 10
                value: Config.options.vpn.routing.hysteria2DownMbps
                onValueChanged: Config.options.vpn.routing.hysteria2DownMbps = value
            }
        }

        ContentSection {
            icon: "data_object"
            title: Translation.tr("Advanced JSON")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Your own sing-box JSON, merged over the generated config: objects merge, null deletes a key, outbounds / DNS servers / rule sets with the same tag are replaced, route and DNS rules here go first. Takes effect on Apply.")
            }

            InfoCard {
                icon: "description"
                title: Translation.tr("File")
                value: Vpn.overlayPath
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 260
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3surface
                border.width: 1
                border.color: overlayEditor.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
                clip: true

                ScrollView {
                    id: overlayScroll
                    anchors {
                        fill: parent
                        margins: 8
                    }
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                    StyledTextArea {
                        id: overlayEditor
                        width: overlayScroll.availableWidth
                        background: null
                        clip: true
                        text: Vpn.overlayText
                        placeholderText: "{\n  \"route\": { \"rules\": [] }\n}"
                        font.family: Appearance.font.family.monospace
                        wrapMode: TextArea.Wrap

                        Connections {
                            target: Vpn
                            function onOverlayTextChanged() {
                                if (!overlayEditor.activeFocus)
                                    overlayEditor.text = Vpn.overlayText;
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: routingRoot.overlayError.length > 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colError
                text: routingRoot.overlayError
            }

            ConfigRow {
                uniform: true
                ActionButton {
                    text: Translation.tr("Reload")
                    onClicked: {
                        overlayEditor.text = Vpn.overlayText;
                        routingRoot.overlayError = "";
                    }
                }
                ActionButton {
                    text: Translation.tr("Save JSON")
                    enabled: overlayEditor.text !== Vpn.overlayText
                    onClicked: routingRoot.overlayError = Vpn.saveOverlay(overlayEditor.text)
                }
            }
        }
    }

    Component {
        id: overviewPage
        OverviewPage {}
    }

    Component {
        id: nodesPage
        NodesPage {}
    }

    Component {
        id: routingPage
        RoutingPage {}
    }

    component ProfileSelector: StyledComboBox {
        id: profileSelector
        Layout.fillWidth: true
        model: ScriptModel {
            values: Vpn.profiles
        }

        displayText: currentIndex >= 0 && Vpn.profiles[currentIndex] ? Vpn.profiles[currentIndex].name : Translation.tr("Select profile")
        currentIndex: Vpn.profiles.findIndex(item => item.isActive)
        onActivated: index => {
            const profile = Vpn.profiles[index];
            if (profile && !profile.isActive)
                Vpn.selectProfile(profile.tag);
        }

        delegate: ItemDelegate {
            id: profileDelegate
            width: profileSelector.width
            highlighted: profileSelector.highlightedIndex === profileDelegate.index
            required property int index
            required property var modelData
            property string profileType: modelData?.type ?? ""
            property string profileName: modelData?.name ?? ""
            property bool isActive: highlighted || hovered
            property color colText: isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3

            contentItem: RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 18

                StyledText {
                    Layout.fillWidth: true
                    color: profileDelegate.colText
                    text: profileDelegate.profileName
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    visible: profileDelegate.profileType.length > 0
                    implicitHeight: 22
                    implicitWidth: typeLabel.implicitWidth + 14
                    radius: 999
                    color: profileDelegate.isActive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3

                    StyledText {
                        id: typeLabel
                        anchors.centerIn: parent
                        text: profileDelegate.profileType
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: profileDelegate.isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                    }
                }
            }
        }
    }

    component ActionButton: StyledButton {
        Layout.fillWidth: true
        implicitHeight: 44
        radius: Appearance.rounding.full
        colBackgroundUnchecked: Appearance.colors.colLayer2
        colForegroundUnchecked: Appearance.colors.colOnLayer2
    }

    component RuleButton: RippleButton {
        required property string glyph
        Layout.fillWidth: false
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: parent.glyph
            iconSize: 20
            color: Appearance.colors.colOnLayer1
            opacity: parent.enabled ? 1 : 0.4
        }
    }

    component InfoCard: Rectangle {
        required property string icon
        required property string title
        required property string value

        Layout.fillWidth: true
        implicitHeight: infoRow.implicitHeight + 22
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        RowLayout {
            id: infoRow
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 14
                rightMargin: 14
            }
            spacing: 12

            MaterialSymbol {
                text: icon
                iconSize: 24
                color: Appearance.colors.colOnLayer1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: title
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                StyledText {
                    Layout.fillWidth: true
                    text: value
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                }
            }
        }
    }
}
