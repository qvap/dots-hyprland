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

                property list<var> shapes: [MaterialShape.Shape.SoftBurst, MaterialShape.Shape.Cookie9Sided, MaterialShape.Shape.Pentagon, MaterialShape.Shape.Pill, MaterialShape.Shape.Sunny, MaterialShape.Shape.Cookie4Sided, MaterialShape.Shape.Oval,]
                property int shapeIndex: 1
                property double continuousRotation: 0
                property double leapRotation: 0

                onLoadingChanged: {
                    if (!loading) {
                        leapAnimation.stop();
                        leapRotation = 0;
                        leapZoomProgress = 0;
                        shapeIndex = 1; // Возвращаем к Cookie9Sided
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

    // Profiles (Nodes) list
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
            id: profileDelegate
            width: profileSelector.width
            highlighted: profileSelector.highlightedIndex === index
            required property var modelData
            property string profileType: modelData?.type ?? ""
            property string profileName: modelData?.name ?? ""
            property bool isActive: highlighted || hovered
            property color colText: isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3

            contentItem: RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 18 // could be a better solution to cropping ig, but for now it works

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

        currentIndex: Vpn.profiles.findIndex(item => item.isActive)
        onActivated: index => {
            const profile = Vpn.profiles[index];
            if (profile && !profile.isActive) {
                const profileIndex = profile.index !== undefined ? profile.index : index;
                Vpn.selectProfile(profileIndex);
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
