import qs.modules.common
import QtQuick
import Quickshell

/* beautiful shader effect for ai ui boost */

Rectangle {
    id: flow
    color: "transparent"

    /* animation properties */

    property bool isAiTabActive
    property bool isAiChatEmpty

    property bool _isSplashing: false

    function splash() {
        _isSplashing = true;
    }

    state: {
        if (_isSplashing)
            return "splash";

        if (!isAiTabActive) {
            return "hidden";
        }

        if (isAiTabActive && isAiChatEmpty)
            return "visible";

        return "hidden";
    }

    states: [
        State {
            name: "visible"
            PropertyChanges {
                target: effect
                intensity: 1.0
            }
        },
        State {
            name: "hidden"
            PropertyChanges {
                target: effect
                intensity: 0.0
            }
        },
        State {
            name: "splash"
            PropertyChanges {
                target: effect
                intensity: 0.0
            }
        }
    ]

    transitions: [
        Transition {
            from: "hidden"
            to: "visible"
            NumberAnimation {
                target: effect
                property: "intensity"
                duration: 2000
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.standard
            }
        },
        Transition {
            from: "visible"
            to: "hidden"
            NumberAnimation {
                target: effect
                property: "intensity"
                duration: 2000
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.standard
            }
        },
        Transition {
            from: "visible"
            to: "splash"
            SequentialAnimation {
                NumberAnimation {
                    target: effect
                    property: "intensity"
                    to: 0.0
                    duration: 1000
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standard
                }

                ScriptAction {
                    script: {
                        effect.fadeStart = 0;
                        effect.fadeEnd = 0.6;
                    }
                }

                NumberAnimation {
                    target: effect
                    property: "intensity"
                    to: 3.0
                    duration: 4000
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standard
                }

                NumberAnimation {
                    target: effect
                    property: "intensity"
                    to: 0.0
                    duration: 2000
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standard
                }

                ScriptAction {
                    script: {
                        effect.fadeStart = 1;
                        effect.fadeEnd = 0.4;
                        flow._isSplashing = false;
                    }
                }
            }
        },
        Transition {
            from: "splash"
            to: "hidden"
            NumberAnimation {
                target: effect
                property: "intensity"
                duration: 2000
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.standard
            }
        },
        Transition {
            from: "splash"
            to: "visible"
            NumberAnimation {
                target: effect
                property: "intensity"
                duration: 2000
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.standard
            }
        }
    ]

    ShaderEffect {
        id: effect
        anchors.fill: parent
        fragmentShader: Quickshell.shellPath("services/flowShader/gemini.frag.qsb")
        //visible: root.aiChatEnabled && root.effectsEnabled
        opacity: Config.options.appearance.transparency.enable ? 1.0 : 0.6

        property real iTime: 0.0
        property size iResolution: Qt.size(effect.width, effect.height)

        property real intensity: 0.0

        property real fadeStart: 1
        property real fadeEnd: 0.4

        property real borderRadius: Appearance.rounding.normal

        property color color1: Appearance.colors.colAccentRed
        property color color2: Appearance.colors.colAccentYellow
        property color color3: Appearance.colors.colAccentGreen
        property color color4: Appearance.colors.colAccentBlue
        property color color5: Appearance.colors.colPrimary

        NumberAnimation on iTime {
            paused: !effect.visible || effect.intensity <= 0
            from: 0
            to: 100000
            duration: 100000000
            running: true
            loops: Animation.Infinite
        }
    }
}
