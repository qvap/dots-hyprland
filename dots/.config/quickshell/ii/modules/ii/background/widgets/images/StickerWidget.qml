pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "sticker"
    hoverEnabled: true

    property string imagePath: root.configEntry.path ?? ""
    property bool dropHover: false

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
    property real widgetRotation: root.configEntry.rotation ?? 0
    property color outlineColor: root.configEntry.outlineColor || "#ffffff"
    property real outlineWidth: root.configEntry.outlineWidth ?? 8

    onDoubleClicked: (mouse) => {
        if (mouse.button !== Qt.LeftButton) return
        if (mouse.modifiers & Qt.ShiftModifier) {
            root.widgetRotation = 0
            root.setEntry({ rotation: 0 })
        } else {
            DesktopWidgets.pickImage(path => root.setEntry({ path: path }))
        }
    }

    implicitWidth: contentItem.implicitWidth
    implicitHeight: contentItem.implicitHeight

    Item {
        id: contentItem
        implicitWidth: root.modeWidth
        implicitHeight: root.modeHeight
        rotation: root.widgetRotation

        Behavior on implicitWidth {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        StyledImage {
            id: stickerImage
            anchors.fill: parent
            source: root.imagePath !== "" ? root.imagePath : ""
            fillMode: Image.PreserveAspectFit
            cache: false
            antialiasing: true
            sourceSize.width: parent.width * 2
            sourceSize.height: parent.height * 2
            visible: root.imagePath !== "" && status === Image.Ready

            layer.enabled: true
            layer.effect: DropShadow {
                horizontalOffset: 0
                verticalOffset: 0
                radius: 4
                spread: root.outlineWidth / 24 
                samples: 24
                color: root.outlineColor
                transparentBorder: true
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            iconSize: Math.min(contentItem.implicitWidth, contentItem.implicitHeight) / 3
            text: root.dropHover ? "download" : "sticker"
            fill: root.dropHover ? 1 : 0
            color: root.dropHover
                ? Appearance.colors.colPrimary
                : Appearance.colors.colOnPrimaryContainer
            visible: root.imagePath === "" || stickerImage.status !== Image.Ready
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
                    var accepted = ["png", "svg", "webp", "gif"] 
                    if (accepted.indexOf(ext) !== -1) {
                        root.setEntry({ path: cleanPath })
                    }
                }
                root.dropHover = false
            }
        }

        ResizeHandler {
            anchorItem: stickerImage
            hoverActive: root.containsMouse
            locked: Config.options.background.widgetsLocked
            currentWidth: root.modeWidth
            resizeMode: "diagonal"
            rotatable: true
            currentRotation: root.widgetRotation
            z: 1
            onResizedXY: (dx, dy, startWidth) => { root.dragMode = root.modeForDrag(dx, dy, startWidth) }
            onResizeFinished: {
                root.setEntry({ sizeMode: root.sizeMode })
                root.dragMode = ""
            }
            onRotated: (newAngle) => {
                root.widgetRotation = newAngle
            }
            onRotateFinished: {
                root.setEntry({ rotation: root.widgetRotation })
            }
        }
    }

    ImageWidgetSettings {
        widget: root
        settings: [
            ConfigSelectionArray {
                currentValue: root.sizeMode
                onSelected: newValue => root.setEntry({ sizeMode: newValue })
                options: [
                    { displayName: "2x2", icon: "grid_view", value: "2x2" },
                    { displayName: "2x3", icon: "view_module", value: "2x3" }
                ]
            },
            ConfigSpinBox {
                icon: "rotate_right"
                text: Translation.tr("Rotation")
                from: -180; to: 180; stepSize: 5
                value: Math.round(root.widgetRotation)
                onValueChanged: if (value !== Math.round(root.configEntry.rotation ?? 0)) { root.widgetRotation = value; root.setEntry({ rotation: value }) }
            },
            ConfigSpinBox {
                icon: "border_outer"
                text: Translation.tr("Outline width")
                from: 0; to: 48; stepSize: 1
                value: root.outlineWidth
                onValueChanged: if (value !== (root.configEntry.outlineWidth ?? 8)) root.setEntry({ outlineWidth: value })
            }
        ]
    }
}
