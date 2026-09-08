import qs.modules.common
import QtQuick
import QtQuick.Shapes

// Renders a single annotation object. The same component is used for committed
// annotations (inside a Repeater) and for the in-progress "draft". All geometry
// is expressed in the canvas coordinate system, which equals the overlay/screen
// coordinate system, so the shapes line up with the frozen screenshot beneath.
// Ported from quickshot; Style.fontFamily -> Appearance.font.family.main.
Item {
    id: shape

    // The annotation record. Shape varies by `type`:
    //   rect/ellipse/highlight/pixelate : x1,y1,x2,y2 (opposite corners)
    //   arrow/line                      : x1,y1 -> x2,y2 (endpoints)
    //   pen                             : points[] of {x,y}
    //   text                            : x1,y1 anchor + text
    //   counter                         : x1,y1 centre + number
    property var ann
    // The frozen ScreencopyView, sampled by the pixelate tool.
    property Item backdrop: null

    anchors.fill: parent

    Loader {
        anchors.fill: parent
        active: shape.ann !== null && shape.ann !== undefined
        sourceComponent: {
            if (!shape.ann)
                return null;
            switch (shape.ann.type) {
            case "rect": return rectComp;
            case "ellipse": return ellipseComp;
            case "arrow": return arrowComp;
            case "line": return lineComp;
            case "pen": return penComp;
            case "highlight": return highlightComp;
            case "text": return textComp;
            case "counter": return counterComp;
            case "pixelate": return pixelateComp;
            }
            return null;
        }
    }

    // NOTE: a Loader resizes its loaded item to fill the Loader (which is
    // canvas-sized here). Components whose ROOT item carries the visible geometry
    // must therefore be wrapped in `Item { anchors.fill: parent }` so the Loader
    // resizes the harmless wrapper, not the shape. Shape-based components already
    // use `anchors.fill: parent`, so they are immune.

    // ---- Rectangle -----------------------------------------------------------
    Component {
        id: rectComp
        Item {
            anchors.fill: parent
            Rectangle {
                x: Math.min(shape.ann.x1, shape.ann.x2)
                y: Math.min(shape.ann.y1, shape.ann.y2)
                width: Math.abs(shape.ann.x2 - shape.ann.x1)
                height: Math.abs(shape.ann.y2 - shape.ann.y1)
                radius: 2
                color: "transparent"
                border.color: shape.ann.color
                border.width: shape.ann.width
            }
        }
    }

    // ---- Highlighter (translucent fill) --------------------------------------
    Component {
        id: highlightComp
        Item {
            anchors.fill: parent
            Rectangle {
                property color base: shape.ann.color
                x: Math.min(shape.ann.x1, shape.ann.x2)
                y: Math.min(shape.ann.y1, shape.ann.y2)
                width: Math.abs(shape.ann.x2 - shape.ann.x1)
                height: Math.abs(shape.ann.y2 - shape.ann.y1)
                color: Qt.rgba(base.r, base.g, base.b, 0.35)
            }
        }
    }

    // ---- Ellipse -------------------------------------------------------------
    Component {
        id: ellipseComp
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: shape.ann.color
                strokeWidth: shape.ann.width
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                // Start at the arc's 0° point so no connecting line is drawn.
                startX: (shape.ann.x1 + shape.ann.x2) / 2 + Math.abs(shape.ann.x2 - shape.ann.x1) / 2
                startY: (shape.ann.y1 + shape.ann.y2) / 2
                PathAngleArc {
                    centerX: (shape.ann.x1 + shape.ann.x2) / 2
                    centerY: (shape.ann.y1 + shape.ann.y2) / 2
                    radiusX: Math.abs(shape.ann.x2 - shape.ann.x1) / 2
                    radiusY: Math.abs(shape.ann.y2 - shape.ann.y1) / 2
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }
    }

    // ---- Line ----------------------------------------------------------------
    Component {
        id: lineComp
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: shape.ann.color
                strokeWidth: shape.ann.width
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: shape.ann.x1
                startY: shape.ann.y1
                PathLine { x: shape.ann.x2; y: shape.ann.y2 }
            }
        }
    }

    // ---- Arrow ---------------------------------------------------------------
    Component {
        id: arrowComp
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            readonly property real x1: shape.ann.x1
            readonly property real y1: shape.ann.y1
            readonly property real x2: shape.ann.x2
            readonly property real y2: shape.ann.y2
            readonly property real ang: Math.atan2(y2 - y1, x2 - x1)
            readonly property real hl: Math.max(14, shape.ann.width * 4)
            readonly property real spread: 0.45

            // Shaft, stopping just short of the tip so the head reads as solid.
            ShapePath {
                strokeColor: shape.ann.color
                strokeWidth: shape.ann.width
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: x1
                startY: y1
                PathLine {
                    x: x2 - hl * 0.6 * Math.cos(ang)
                    y: y2 - hl * 0.6 * Math.sin(ang)
                }
            }
            // Filled arrowhead triangle.
            ShapePath {
                strokeColor: "transparent"
                fillColor: shape.ann.color
                startX: x2
                startY: y2
                PathLine {
                    x: x2 - hl * Math.cos(ang - spread)
                    y: y2 - hl * Math.sin(ang - spread)
                }
                PathLine {
                    x: x2 - hl * Math.cos(ang + spread)
                    y: y2 - hl * Math.sin(ang + spread)
                }
                PathLine { x: x2; y: y2 }
            }
        }
    }

    // ---- Freehand pen --------------------------------------------------------
    Component {
        id: penComp
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: shape.ann.color
                strokeWidth: shape.ann.width
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: shape.ann.points.length > 0 ? shape.ann.points[0].x : 0
                startY: shape.ann.points.length > 0 ? shape.ann.points[0].y : 0
                PathPolyline { path: shape.polyline(shape.ann.points) }
            }
        }
    }

    // ---- Text ----------------------------------------------------------------
    Component {
        id: textComp
        Item {
            anchors.fill: parent
            Text {
                x: shape.ann.x1
                y: shape.ann.y1
                text: shape.ann.text
                color: shape.ann.color
                font.family: Appearance.font.family.main
                font.pixelSize: shape.ann.fontSize
                font.bold: true
                textFormat: Text.PlainText
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.45)
            }
        }
    }

    // ---- Numbered step counter ----------------------------------------------
    Component {
        id: counterComp
        Item {
            anchors.fill: parent
            Item {
                id: badge
                readonly property real d: Math.max(24, shape.ann.fontSize * 1.25)
                x: shape.ann.x1 - d / 2
                y: shape.ann.y1 - d / 2
                width: d
                height: d
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: shape.ann.color
                    border.color: "#ffffff"
                    border.width: 2
                }
                Text {
                    anchors.centerIn: parent
                    text: shape.ann.number
                    color: "#ffffff"
                    font.family: Appearance.font.family.main
                    font.bold: true
                    font.pixelSize: badge.d * 0.5
                }
            }
        }
    }

    // ---- Pixelate / redact ---------------------------------------------------
    Component {
        id: pixelateComp
        Item {
            anchors.fill: parent
            readonly property real nx: Math.min(shape.ann.x1, shape.ann.x2)
            readonly property real ny: Math.min(shape.ann.y1, shape.ann.y2)
            readonly property real nw: Math.abs(shape.ann.x2 - shape.ann.x1)
            readonly property real nh: Math.abs(shape.ann.y2 - shape.ann.y1)

            ShaderEffectSource {
                x: parent.nx
                y: parent.ny
                width: Math.max(1, parent.nw)
                height: Math.max(1, parent.nh)
                visible: shape.backdrop !== null
                sourceItem: shape.backdrop
                sourceRect: Qt.rect(parent.nx, parent.ny, Math.max(1, parent.nw), Math.max(1, parent.nh))
                // Force a tiny intermediate texture, then upscale with nearest
                // filtering to produce blocky pixelation.
                textureSize: Qt.size(Math.max(1, Math.round(parent.nw / 14)),
                                     Math.max(1, Math.round(parent.nh / 14)))
                smooth: false
            }
        }
    }

    // Convert an array of {x,y} into the list<point> PathPolyline expects.
    function polyline(points) {
        var out = [];
        if (!points)
            return out;
        for (var i = 0; i < points.length; ++i)
            out.push(Qt.point(points[i].x, points[i].y));
        return out;
    }
}
