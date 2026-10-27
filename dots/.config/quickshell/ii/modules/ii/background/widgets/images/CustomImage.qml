pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "customImage"
    hoverEnabled: true

    property string imagePath: root.configEntry.path ?? ""
    property bool dropHover: false
    property string shapeName: root.configEntry.shape ?? "Cookie4Sided"
    property int shapeType: ShapeUtils.getShape(root.shapeName)
    // Shapes distort when stretched, so wide sizes fall back to a rounded rectangle
    readonly property bool useShape: root.sizeMode === "2x2"
    readonly property real rectRadius: Appearance.rounding.verylarge

    // Same grid sizes as ImageCardWidget
    readonly property real cardSpacing: 12
    readonly property real snapWidth2: 132 * 2 + root.cardSpacing
    readonly property real snapWidth3: 132 * 3 + root.cardSpacing * 2
    readonly property real cardHeight: 120
    readonly property real doubleHeight: root.cardHeight * 2 + root.cardSpacing
    property string dragMode: ""
    readonly property string sizeMode: root.dragMode !== "" ? root.dragMode : (root.configEntry.sizeMode === "2x3" ? "2x3" : "2x2")
    // 2x2 is square so shapes keep their proportions
    readonly property real modeWidth: root.sizeMode === "2x3" ? root.snapWidth3 : root.doubleHeight
    readonly property real modeHeight: root.doubleHeight

    // Smaller sizes are too small for an image; only 2x2 and 2x3 are offered
    function modeForDrag(dx, dy, startWidth) {
        var width = startWidth + dx
        return width < (root.snapWidth2 + root.snapWidth3) / 2 ? "2x2" : "2x3"
    }

    onDoubleClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton) DesktopWidgets.pickImage(path => root.setEntry({ path: path }))
    }
    onWheel: (wheel) => {
        if (DesktopWidgets.locked) return
        const names = ShapeUtils.names
        const step = wheel.angleDelta.y < 0 ? 1 : -1
        root.setEntry({ shape: names[(names.indexOf(root.shapeName) + step + names.length) % names.length] })
    }

    implicitWidth: contentItem.implicitWidth
    implicitHeight: contentItem.implicitHeight

    Item {
        id: contentItem
        implicitWidth: root.modeWidth
        implicitHeight: root.modeHeight

        Behavior on implicitWidth {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        MaterialShape {
            id: shadowShape
            anchors.fill: parent
            color: Appearance.colors.colPrimaryContainer
            shape: root.shapeType
            visible: false
        }
        Rectangle {
            id: shadowRect
            anchors.fill: parent
            radius: root.rectRadius
            color: Appearance.colors.colPrimaryContainer
            visible: false
        }

        StyledDropShadow {
            target: root.useShape ? shadowShape : shadowRect
            z: -1
            visible: Config.options.background.widgets.shadow
        }

        MaterialShape {
            id: imageShape
            anchors.fill: parent
            z: 0
            color: root.useShape ? Appearance.colors.colPrimaryContainer : "transparent"
            shape: root.shapeType

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Item {
                    width: imageShape.width
                    height: imageShape.height
                    MaterialShape {
                        anchors.fill: parent
                        shape: root.shapeType
                        visible: root.useShape
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: root.rectRadius
                        visible: !root.useShape
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: root.rectRadius
                color: Appearance.colors.colPrimaryContainer
                visible: !root.useShape
            }

            StyledImage {
                anchors.fill: parent
                source: root.imagePath !== "" ? root.imagePath : ""
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                sourceSize.width: parent.width
                sourceSize.height: parent.height
                visible: root.imagePath !== ""
            }

            // Placeholder + hover hint
            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Math.min(contentItem.implicitWidth, contentItem.implicitHeight) / 3
                text: root.dropHover ? "download" : "image"
                fill: root.dropHover ? 1 : 0
                color: root.dropHover
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnPrimaryContainer
                visible: root.imagePath === ""
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }

            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]
                onEntered: (drag) => {
                    drag.accept(Qt.CopyAction)
                    root.dropHover = true
                }
                onExited: {
                    root.dropHover = false
                }
                onDropped: (drop) => {
                    if (drop.hasUrls && drop.urls.length > 0) {
                        var cleanPath = drop.urls[0].toString().replace(/^file:\/\//, "")
                        var ext = cleanPath.split(".").pop().toLowerCase()
                        var accepted = ["png","jpg","jpeg","webp","avif","bmp","gif","tiff","tif"]
                        if (accepted.indexOf(ext) !== -1) {
                            root.setEntry({ path: cleanPath })
                        }
                    }
                    root.dropHover = false
                }
            }
        }

        ResizeHandler{
            anchorItem: imageShape
            hoverActive: root.containsMouse
            locked: DesktopWidgets.locked
            currentWidth: root.modeWidth
            resizeMode: "diagonal"
            z: 1
            onResizedXY: (dx, dy, startWidth) => { root.dragMode = root.modeForDrag(dx, dy, startWidth) }
            onResizeFinished: {
                root.setEntry({ sizeMode: root.sizeMode })
                root.dragMode = ""
            }
        }
    }

    ImageWidgetSettings {
        widget: root
        settings: [
            ConfigSelectionShapeArray {
                currentValue: root.shapeName
                options: ShapeUtils.names
                shapeColor: Appearance.colors.colOnSecondaryContainer
                enabled: root.useShape
                opacity: enabled ? 1 : 0.4
                onSelected: newValue => root.setEntry({ shape: newValue })
            },
            ConfigSelectionArray {
                currentValue: root.sizeMode
                onSelected: newValue => root.setEntry({ sizeMode: newValue })
                options: [
                    { displayName: "2x2", icon: "grid_view", value: "2x2" },
                    { displayName: "2x3", icon: "view_module", value: "2x3" }
                ]
            }
        ]
    }
}
