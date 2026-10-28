pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Desktop widget editor: unlocks moving/resizing (DesktopWidgets.locked), keeps the grid on
// (WidgetCanvas.gridVisible) and shows the widget picker plus common widget settings
Scope {
    id: root

    // Set before the editor flag drops so the window outlives the hide animation
    property bool loaded: false
    Timer {
        id: closeDelay
        interval: 300
        onTriggered: root.loaded = GlobalStates.widgetEditorOpen
    }
    Connections {
        target: GlobalStates
        function onWidgetEditorOpenChanged() {
            if (GlobalStates.widgetEditorOpen) root.loaded = true
            else closeDelay.restart()
        }
    }

    Loader {
        active: root.loaded
        sourceComponent: PanelWindow {
            id: editorWindow
            property bool shown: false
            Component.onCompleted: shown = Qt.binding(() => GlobalStates.widgetEditorOpen)
            screen: GlobalStates.desktopMenuScreen ?? Quickshell.screens[0]
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:widgetEditor"
            property list<Item> blurItems: [] // filled by BlurSource children
            BackgroundEffect.blurRegion: BlurRegion { items: editorWindow.blurItems }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors {
                left: true
                right: true
                bottom: true
            }
            implicitHeight: screen.height / 2

            // Only the cards take input; the desktop widgets behind stay editable
            mask: Region {
                item: pickerBar
                Region { item: settingsCard }
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: GlobalStates.widgetEditorOpen = false
            }

            // Settings card, left of and above the picker
            Rectangle {
                id: settingsCard
                BlurSource {}
                width: 284
                implicitHeight: settingsCol.implicitHeight + 16
                x: pickerBar.x
                anchors {
                    bottom: pickerBar.top
                    bottomMargin: 8
                }
                radius: Appearance.rounding.verylarge
                color: Appearance.colors.colUiBackground
                opacity: editorWindow.shown ? 1 : 0
                scale: editorWindow.shown ? 1 : 0.9
                transformOrigin: Item.BottomLeft
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }

                WindowGlass {
                    anchors.fill: parent
                    cardRadius: parent.radius
                    tint: parent.color
                }

                ColumnLayout {
                    id: settingsCol
                    anchors { fill: parent; margins: 8 }
                    spacing: 2

                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "lock"
                        text: Translation.tr("Lock widget positions")
                        checked: Config.options.background.widgetsLocked
                        onCheckedChanged: Config.options.background.widgetsLocked = checked
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "shadow"
                        text: Translation.tr("Shadow")
                        checked: Config.options.background.widgets.shadow
                        onCheckedChanged: Config.options.background.widgets.shadow = checked
                    }
                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: "blur_on"
                        text: Translation.tr("Blur widgets")
                        checked: Config.options.background.widgets.blurWidgets
                        onCheckedChanged: Config.options.background.widgets.blurWidgets = checked
                    }
                }
            }

            // Widget picker
            Rectangle {
                id: pickerBar
                BlurSource {}
                readonly property real maxWidth: editorWindow.width - 32
                width: Math.min(tilesRow.width + doneButton.width + 8 + 16, maxWidth)
                height: 72
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: editorWindow.shown ? 16 : -height
                }
                opacity: editorWindow.shown ? 1 : 0
                Behavior on anchors.bottomMargin {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                radius: Appearance.rounding.verylarge
                color: Appearance.colors.colUiBackground

                WindowGlass {
                    anchors.fill: parent
                    cardRadius: parent.radius
                    tint: parent.color
                }

                RowLayout {
                    anchors { fill: parent; margins: 8 }
                    spacing: 8

                    Flickable {
                        id: pickerFlick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: tilesRow.width
                        flickableDirection: Flickable.HorizontalFlick
                        clip: true

                        Row {
                            id: tilesRow
                            height: parent.height
                            spacing: 4

                            Repeater {
                                model: DesktopWidgets.menuItems
                                delegate: PickerButton {
                                    required property var modelData
                                    symbol: modelData.icon
                                    name: modelData.name
                                    toggled: DesktopWidgets.isEnabled(modelData.key)
                                    onClicked: DesktopWidgets.setEnabled(modelData.key, !toggled)
                                }
                            }
                            Repeater {
                                model: DesktopWidgets.imageCatalog
                                delegate: PickerButton {
                                    required property var modelData
                                    symbol: modelData.icon
                                    name: modelData.name
                                    onClicked: DesktopWidgets.addImageWidget(modelData.key)
                                }
                            }
                        }
                    }

                    PickerButton {
                        id: doneButton
                        symbol: "check"
                        name: Translation.tr("Done")
                        toggled: true
                        onClicked: GlobalStates.widgetEditorOpen = false
                    }
                }

                // Flickable eats wheel events without scrolling sideways
                MouseArea {
                    x: pickerFlick.x + 8
                    y: pickerFlick.y + 8
                    width: pickerFlick.width
                    height: pickerFlick.height
                    acceptedButtons: Qt.NoButton
                    onWheel: event => {
                        const delta = event.angleDelta.y || -event.angleDelta.x
                        pickerFlick.contentX = Math.max(0, Math.min(pickerFlick.contentX - delta, pickerFlick.contentWidth - pickerFlick.width))
                    }
                }

            }
        }
    }

    component PickerButton: RippleButton {
        id: btn
        property string symbol
        property string name
        implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
        implicitHeight: 56
        buttonRadius: Appearance.rounding.normal
        colBackground: Appearance.colors.colLayer2
        contentItem: RowLayout {
            spacing: 8
            MaterialSymbol {
                Layout.leftMargin: 10
                text: btn.symbol
                iconSize: Appearance.font.pixelSize.larger
                color: btn.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                Layout.rightMargin: 14
                text: btn.name
                font.pixelSize: Appearance.font.pixelSize.small
                color: btn.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            }
        }
        StyledToolTip { text: btn.name }
    }
}
