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

    function statusText() {
        if (Vpn.status === "active")
            return Translation.tr("Connected");
        if (Vpn.status === "connecting")
            return Translation.tr("Connecting");
        return Translation.tr("Disconnected");
    }

    function ruleTitle(rule) {
        if (!rule)
            return Translation.tr("Rule");
        if (rule.action === "reject")
            return Translation.tr("Block");
        return rule.outbound || Translation.tr("Rule");
    }

    function isRoutingError(message) {
        const normalized = message.toLowerCase();
        return normalized.includes("invalid") || normalized.includes("failed") || normalized.includes("unsupported") || normalized.includes("does not exist") || normalized.includes("unavailable") || normalized.includes("error");
    }

    function ruleSummary(rule) {
        if (!rule)
            return "";
        const keys = ["domain", "domain_suffix", "domain_keyword", "domain_regex", "geoip", "geosite", "ip_cidr"];
        let parts = [];
        for (let i = 0; i < keys.length; i++) {
            const key = keys[i];
            const values = rule[key];
            if (values && values.length !== undefined && values.length > 0)
                parts.push(key + ": " + values.join(", "));
        }
        return parts.length > 0 ? parts.join(" · ") : JSON.stringify(rule);
    }

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
        Vpn.refreshRules();
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

                            property bool loading: Vpn.status === "connecting"
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
                                color: (Vpn.status === "active" || Vpn.status === "connecting") ? (vpnMouseArea.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer) : (vpnMouseArea.containsMouse ? Appearance.colors.colLayer3Hover : ColorUtils.transparentize(Appearance.colors.colLayer3))

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(shape)
                                }

                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "power_settings_new"
                            iconSize: 42
                            color: (Vpn.status === "active" || Vpn.status === "connecting") ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
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
                            text: root.statusText()
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
                    }
                }
            }
        }

        ContentSection {
            icon: "hub"
            title: Translation.tr("Active node")

            ProfileSelector {}
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
                visible: Vpn.needsSubscription
                Layout.fillWidth: true
                placeholderText: Translation.tr("Subscription URL")
                text: Vpn.subscriptionUrl
                onAccepted: Vpn.subscribe(text)
            }

            ConfigRow {
                uniform: true
                ActionButton {
                    text: Vpn.isScanning ? Translation.tr("Loading...") : Translation.tr("Load subscription")
                    visible: Vpn.needsSubscription
                    enabled: !Vpn.isScanning
                    onClicked: Vpn.subscribe(detailsSubscriptionField.text)
                }
                ActionButton {
                    text: Vpn.isScanning ? Translation.tr("Updating...") : Translation.tr("Update subscription")
                    enabled: !Vpn.isScanning && !Vpn.needsSubscription
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
                    property string originalText: Vpn.isScanning ? Translation.tr("Loading...") : Translation.tr("Delete subscription")
                    text: deleteSubscriptionButton.oneClicked ? Translation.tr("Click again to confirm") : deleteSubscriptionButton.originalText
                    enabled: !Vpn.isScanning
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

            Repeater {
                model: Vpn.profiles
                delegate: Rectangle {
                    required property var modelData
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
                            text: modelData.isActive ? "radio_button_checked" : "radio_button_unchecked"
                            iconSize: 22
                            color: modelData.isActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.name
                                elide: Text.ElideRight
                                color: modelData.isActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: modelData.isActive ? Font.Medium : Font.Normal
                            }

                            StyledText {
                                text: modelData.type
                                color: modelData.isActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                opacity: modelData.isActive ? 0.72 : 1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }

                        ActionButton {
                            Layout.fillWidth: false
                            implicitWidth: 120
                            text: modelData.isActive ? Translation.tr("Connected") : Translation.tr("Select")
                            enabled: !modelData.isActive
                            onClicked: Vpn.selectProfile(modelData.index)
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

        property string outbound: "proxy"
        property string ruleType: "domain_suffix"

        function valuesFromText(text) {
            return text.split(/[\n,]+/).map(value => value.trim()).filter(value => value.length > 0);
        }

        ContentSection {
            icon: "dns"
            title: Translation.tr("DNS")

            ConfigSwitch {
                buttonIcon: "frame_inspect"
                text: Translation.tr("Enable FakeIP")
                enabled: !Vpn.isRoutingBusy
                checked: Vpn.fakeipEnabled
                onCheckedChanged: {
                    if (checked !== Vpn.fakeipEnabled)
                        Vpn.setFakeip(checked);
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                text: Translation.tr("FakeIP speeds up DNS resolution and prevents leaks, but may break some apps (Spotify, Discord, games). Disabled by default. Changing this rebuilds the config and restarts the VPN")
            }
        }

        ContentSection {
            icon: "alt_route"
            title: Translation.tr("Create routing rule")

            InfoCard {
                icon: "description"
                title: Translation.tr("Rules file")
                value: Vpn.routingRulesPath
            }

            NoticeBox {
                Layout.fillWidth: true
                text: Translation.tr("Rules are saved through VPN service and merged into sing-box config after each apply or subscription update")
            }

            ContentSubsectionLabel {
                text: Translation.tr("Outbound")
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: Math.max(outboundSelection.implicitHeight, outboundSelection.childrenRect.height)

                ConfigSelectionArray {
                    id: outboundSelection
                    width: parent.width
                    currentValue: routingRoot.outbound
                    onSelected: newValue => routingRoot.outbound = newValue
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
            }

            ContentSubsectionLabel {
                text: Translation.tr("Rule type")
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: Math.max(ruleTypeSelection.implicitHeight, ruleTypeSelection.childrenRect.height)

                ConfigSelectionArray {
                    id: ruleTypeSelection
                    width: parent.width
                    currentValue: routingRoot.ruleType
                    onSelected: newValue => routingRoot.ruleType = newValue
                    options: [
                        {
                            displayName: "Domain",
                            value: "domain"
                        },
                        {
                            displayName: "Suffix",
                            value: "domain_suffix"
                        },
                        {
                            displayName: "Keyword",
                            value: "domain_keyword"
                        },
                        {
                            displayName: "Regex",
                            value: "domain_regex"
                        },
                        {
                            displayName: "GeoIP",
                            value: "geoip"
                        },
                        {
                            displayName: "Geosite",
                            value: "geosite"
                        },
                        {
                            displayName: "IP CIDR",
                            value: "ip_cidr"
                        }
                    ]
                }
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
                    placeholderText: Translation.tr("Values, one per line or comma-separated") + "\nexample.com\nyoutube\nprivate"
                    wrapMode: TextArea.Wrap
                }
            }

            ConfigRow {
                uniform: true
                ActionButton {
                    text: Vpn.isRoutingBusy ? Translation.tr("Loading...") : Translation.tr("Add rule")
                    enabled: !Vpn.isRoutingBusy
                    onClicked: Vpn.addRoutingRule(routingRoot.outbound, routingRoot.ruleType, routingRoot.valuesFromText(ruleValuesField.text))
                }
            }

            StyledText {
                visible: Vpn.routingStatus.length > 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: root.isRoutingError(Vpn.routingStatus) ? Appearance.colors.colError : Appearance.colors.colSubtext
                text: Translation.tr(Vpn.routingStatus)
            }
        }

        ContentSection {
            icon: "rule"
            title: Translation.tr("Current rules")

            StyledText {
                visible: Vpn.routingRuleItems.length === 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("No custom routing rules yet.")
            }

            Repeater {
                model: Vpn.routingRuleItems
                delegate: Rectangle {
                    id: ruleDelegate
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: ruleRow.implicitHeight + 22
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    RowLayout {
                        id: ruleRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 14
                            rightMargin: 14
                        }
                        spacing: 12

                        MaterialSymbol {
                            text: ruleDelegate.modelData.action === "reject" || ruleDelegate.modelData.outbound === "block" ? "block" : ruleDelegate.modelData.outbound === "direct" ? "public" : "vpn_lock"
                            iconSize: 22
                            color: Appearance.colors.colOnLayer1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: (ruleDelegate.index + 1) + ". " + root.ruleTitle(ruleDelegate.modelData) + " · " + ruleDelegate.modelData.ruleType
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: ruleDelegate.modelData.value
                                elide: Text.ElideRight
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }

                        RippleButton {
                            Layout.fillWidth: false
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            enabled: !Vpn.isRoutingBusy
                            onClicked: Vpn.removeRoutingRuleItem(ruleDelegate.modelData)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "delete"
                                iconSize: 20
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }

            ConfigRow {
                uniform: true
                ActionButton {
                    text: Translation.tr("Refresh")
                    enabled: !Vpn.isRoutingBusy
                    onClicked: Vpn.refreshRules()
                }
                ActionButton {
                    text: Translation.tr("Apply")
                    enabled: !Vpn.isRoutingBusy
                    onClicked: Vpn.applyRoutingRules()
                }
                ActionButton {
                    text: Translation.tr("Clear")
                    enabled: !Vpn.isRoutingBusy && Vpn.routingRuleItems.length > 0
                    onClicked: Vpn.clearRoutingRules()
                }
            }
        }

        ContentSection {
            icon: "data_object"
            title: Translation.tr("Advanced JSON")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Edit the whole custom rules document when you need rule_sets or complex sing-box syntax")
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 260
                radius: Appearance.rounding.small
                color: Appearance.m3colors.m3surface
                border.width: 1
                border.color: rawRulesEditor.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
                clip: true

                ScrollView {
                    id: rawRulesScroll
                    anchors {
                        fill: parent
                        margins: 8
                    }
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                    StyledTextArea {
                        id: rawRulesEditor
                        width: rawRulesScroll.availableWidth
                        background: null
                        clip: true
                        text: Vpn.routingRulesRaw
                        font.family: Appearance.font.family.monospace
                        wrapMode: TextArea.Wrap

                        Connections {
                            target: Vpn
                            function onRoutingRulesRawChanged() {
                                if (!rawRulesEditor.activeFocus)
                                    rawRulesEditor.text = Vpn.routingRulesRaw;
                            }
                        }
                    }
                }
            }

            ConfigRow {
                uniform: true
                ActionButton {
                    text: Translation.tr("Reload")
                    enabled: !Vpn.isRoutingBusy
                    onClicked: Vpn.refreshRules()
                }
                ActionButton {
                    text: Translation.tr("Save JSON")
                    enabled: !Vpn.isRoutingBusy
                    onClicked: Vpn.setRoutingRules(rawRulesEditor.text)
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
            if (profile && !profile.isActive) {
                const profileIndex = profile.index !== undefined ? profile.index : index;
                Vpn.selectProfile(profileIndex);
            }
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
