import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool effectsEnabled: Config.options.effects.enabled
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool animeCloset: Config.options.policies.weeb === 2
    property var tabButtonList: [...(root.aiChatEnabled ? [
                {
                    "icon": "neurology",
                    "name": Translation.tr("Intelligence")
                }
            ] : []), ...(root.translatorEnabled ? [
                {
                    "icon": "translate",
                    "name": Translation.tr("Translator")
                }
            ] : []), ...((root.animeEnabled && !root.animeCloset) ? [
                {
                    "icon": "bookmark_heart",
                    "name": Translation.tr("Anime")
                }
            ] : [])]
    property int tabCount: swipeView.count

    function focusActiveItem() {
        swipeView.currentItem.forceActiveFocus();
    }

    Keys.onPressed: event => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex();
                event.accepted = true;
            }
        }
    }

    Rectangle {
        id: flow
        anchors.fill: parent
        color: "transparent"

        ShaderEffect {
            id: effect
            anchors.fill: parent
            fragmentShader: Quickshell.shellPath("services/flowShader/gemini.frag.qsb")
            visible: root.aiChatEnabled && root.effectsEnabled

            property real iTime: 0.0
            property size iResolution: Qt.size(effect.width, effect.height)

            property real intensity: 1.0

            property real fadeStart: 1
            property real fadeEnd: 0.4

            property real borderRadius: Appearance.rounding.normal

            property color color1: Appearance.colors.colAccentRed
            property color color2: Appearance.colors.colAccentYellow
            property color color3: Appearance.colors.colAccentGreen
            property color color4: Appearance.colors.colAccentBlue
            property color color5: Appearance.colors.colPrimary

            NumberAnimation on iTime {
                from: 0
                to: 100000
                duration: 100000000
                running: true
                loops: Animation.Infinite
            }

            function safePlay(animToPlay) {
                flowSplashAnimation.stop();
                flowReveal.stop();
                flowHide.stop();
                animToPlay.start();
            }

            SequentialAnimation {
                id: flowSplashAnimation
                running: false

                NumberAnimation {
                    target: effect
                    property: "intensity"
                    to: 1.8
                    duration: 2000
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standard
                }

                NumberAnimation {
                    target: effect
                    property: "intensity"
                    from: 1.5
                    to: 0.0
                    duration: 4000
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standard
                }
            }

            SequentialAnimation {
                id: flowReveal
                running: false

                NumberAnimation {
                    target: effect
                    property: "intensity"
                    to: 1.0
                    duration: 2000
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standard
                }
            }

            SequentialAnimation {
                id: flowHide
                running: false

                NumberAnimation {
                    target: effect
                    property: "intensity"
                    to: 0.0
                    duration: 2000
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standard
                }
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: sidebarPadding

        Toolbar {
            visible: tabButtonList.length > 0
            Layout.alignment: Qt.AlignHCenter
            enableShadow: false
            ToolbarTabBar {
                id: tabBar
                Layout.alignment: Qt.AlignHCenter
                tabButtonList: root.tabButtonList
                currentIndex: swipeView.currentIndex
                onFlowRevealRequested: {
                    effect.safePlay(flowReveal);
                }
                onFlowHideRequested: {
                    effect.safePlay(flowHide);
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: 10
                currentIndex: tabBar.currentIndex

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                contentChildren: [...(root.aiChatEnabled ? [aiChat.createObject()] : []), ...(root.translatorEnabled ? [translator.createObject()] : []), ...((root.tabButtonList.length === 0 || (!root.aiChatEnabled && !root.translatorEnabled && root.animeCloset)) ? [placeholder.createObject()] : []), ...(root.animeEnabled ? [anime.createObject()] : []),]
            }
        }

        Component {
            id: aiChat
            AiChat {
                onFlowSplashRequested: {
                    effect.safePlay(flowSplashAnimation);
                }
                onFlowRevealRequested: {
                    effect.safePlay(flowReveal);
                }
                onFlowHideRequested: {
                    effect.safePlay(flowHide);
                }
            }
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: anime
            Anime {}
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: root.animeCloset ? Translation.tr("Nothing") : Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
