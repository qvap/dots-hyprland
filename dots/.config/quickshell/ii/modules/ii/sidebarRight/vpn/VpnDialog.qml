import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

WindowDialog {
    id: root

    backgroundHeight: 600

    WindowDialogTitle {
        text: Translation.tr("VPN Connections")
    }

    WindowDialogSeparator {
        visible: !Vpn.isScanning && !Vpn.isSpeedtesting
    }

    StyledIndeterminateProgressBar {
        visible: Vpn.isScanning || Vpn.isSpeedtesting
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }

    Item {
        Layout.fillHeight: true
    }

    // Status header
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 16

        Item {
            Layout.fillWidth: true
            implicitHeight: vpnCookie.implicitHeight

            MaterialCookie {
                id: vpnCookie
                anchors.centerIn: parent
                implicitSize: 120
                sides: 7
                transformOrigin: Item.Center
                rotation: 0

                color: (Vpn.status === "active" || Vpn.status === "connecting") ? (vpnMouseArea.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer) : (vpnMouseArea.containsMouse ? Appearance.colors.colLayer3Hover : ColorUtils.transparentize(Appearance.colors.colLayer3))

                RotationAnimation on rotation {
                    running: Vpn.status === "active" || Vpn.status === "connecting"
                    duration: 14000
                    loops: Animation.Infinite
                    easing.type: Easing.Linear
                    from: 0
                    to: 360
                }

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
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
                onClicked: {
                    Vpn.toggle();
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: {
                if (Vpn.status === "active")
                    return Translation.tr("Connected");
                if (Vpn.status === "connecting")
                    return Translation.tr("Connecting");
                return Translation.tr("Disconnected");
            }
            font.pixelSize: Appearance.font.pixelSize.huge
            font.weight: 600
            color: Appearance.colors.colOnLayer0
        }
    }

    // Profiles list
    StyledComboBox {
        id: profileSelector
        Layout.fillHeight: false
        Layout.fillWidth: true
        Layout.bottomMargin: 6
        model: ScriptModel {
            values: Vpn.profiles
        }

        displayText: currentIndex >= 0 && Vpn.profiles[currentIndex] ? Vpn.profiles[currentIndex].name : ""
        delegate: ItemDelegate {
            width: profileSelector.width
            text: typeof modelData !== "undefined" ? modelData.name : ""
            highlighted: profileSelector.highlightedIndex === index
        }

        currentIndex: Vpn.profiles.findIndex(item => item.isActive)
        onActivated: index => {
            const profile = Vpn.profiles[index];
            if (profile && !profile.isActive) {
                const profileIndex = profile.index !== undefined ? profile.index : index;
                Vpn.selectProfile(profileIndex);
                root.dismiss();
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 6
        spacing: 8

        StyledButton {
            Layout.fillWidth: true
            text: Vpn.isPinging ? Translation.tr("Pinging...") : (Vpn.pingResult !== "" ? Translation.tr("Ping") + ": " + Vpn.pingResult : Translation.tr("Check Ping"))
            onClicked: Vpn.testPing()
        }

        StyledButton {
            Layout.fillWidth: true
            text: Vpn.isSpeedtesting ? Translation.tr("Testing...") : (Vpn.speedResult !== "" ? Vpn.speedResult : Translation.tr("Speedtest"))
            onClicked: Vpn.testSpeed()
        }
    }

    Item {
        Layout.fillHeight: true
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        DialogButton {
            buttonText: Translation.tr("Update subscription")
            onClicked: {
                Vpn.updateSubscription();
                root.dismiss();
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
