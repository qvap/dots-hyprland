import qs
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/*
kind of like clipboard manager but for files
*/

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: basketWindow

            required property var modelData
            readonly property int basketSize: Math.min(320, Math.max(220, Math.min(screen.width, screen.height) - 32))
            readonly property int edgeWidth: 8
            property var files: []
            property bool dragAtEdge: false
            property bool dragOverBasket: false
            readonly property bool expanded: files.length > 0 || dragAtEdge || dragOverBasket

            function isFileDrag(event) {
                if (event.source?.basketDragSource || !(event.supportedActions & Qt.CopyAction) || !event.urls)
                    return false;
                for (const url of event.urls) {
                    if (String(url).startsWith("file://"))
                        return true;
                }
                return false;
            }

            function addFiles(event) {
                if (!isFileDrag(event))
                    return;

                const next = files.slice();
                for (const url of event.urls) {
                    const value = String(url);
                    if (!value.startsWith("file://") || next.some(file => file.url === value))
                        continue;
                    next.push({
                        url: value,
                        name: decodeURIComponent(FileUtils.fileNameForPath(value))
                    });
                }

                if (next.length === files.length) {
                    event.accepted = false;
                    return;
                }

                files = next;
                event.accept(Qt.CopyAction);
                dragAtEdge = false;
                dragOverBasket = false;
            }

            function removeFile(url) {
                files = files.filter(file => file.url !== url);
                dragAtEdge = false;
                dragOverBasket = false;
            }

            function clearFiles() {
                files = [];
                dragAtEdge = false;
                dragOverBasket = false;
            }

            function startFileDrag(tile, preview) {
                if (dragProxy.Drag.active)
                    return;
                const position = tile.mapToItem(null, 0, 0);
                dragProxy.x = position.x;
                dragProxy.y = position.y;
                dragProxy.width = tile.width;
                dragProxy.height = tile.height;
                dragProxy.dragUrl = tile.modelData.url;
                dragProxy.sourcePath = tile.sourcePath;
                dragProxy.dragPreview = preview;
                dragProxy.Drag.imageSource = preview?.url ?? Quickshell.iconPath("text-x-generic");
                dragProxy.Drag.active = true;
            }

            screen: modelData
            visible: !GlobalStates.screenLocked
            color: "transparent"
            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:fileBasket"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            implicitWidth: basketSize + 12

            anchors {
                top: true
                right: true
                bottom: true
            }

            Item {
                id: dragProxy
                property bool basketDragSource: true
                property string dragUrl: ""
                property string sourcePath: ""
                property var dragPreview: null
                Drag.dragType: Drag.Automatic
                Drag.hotSpot: Qt.point(width / 2, height / 2)
                Drag.mimeData: {
                    "text/uri-list": dragUrl + "\r\n"
                }
                Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                Drag.proposedAction: Qt.MoveAction
                Drag.onDragStarted: basketWindow.removeFile(dragUrl)
                Drag.onDragFinished: action => {
                    basketWindow.removeFile(dragProxy.dragUrl);
                    if (action === Qt.MoveAction)
                        Quickshell.execDetached(["gio", "trash", "--force", dragProxy.sourcePath]);
                    dragProxy.dragPreview = null;
                    dragProxy.dragUrl = "";
                    dragProxy.sourcePath = "";
                }
            }

            DropArea {
                id: edgeDropArea

                width: basketWindow.edgeWidth
                onEntered: drag => {
                    if (!basketWindow.isFileDrag(drag))
                        return;

                    drag.accept(Qt.CopyAction);
                    basketWindow.dragAtEdge = true;
                    hideTimer.stop();
                }
                onExited: {
                    basketWindow.dragAtEdge = false;
                    hideTimer.restart();
                }
                onDropped: drop => {
                    return basketWindow.addFiles(drop);
                }

                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    right: parent.right
                }
            }

            Timer {
                id: hideTimer

                interval: 350
                onTriggered: {
                    if (basketWindow.files.length === 0 && !basketWindow.dragOverBasket)
                        basketWindow.dragAtEdge = false;
                }
            }

            Rectangle {
                id: basketBackground

                width: basketWindow.basketSize
                height: width
                visible: basketWindow.expanded || anchors.rightMargin > -width
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1Base
                border.width: 1
                border.color: basketDropArea.containsDrag ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                clip: true

                anchors {
                    right: parent.right
                    rightMargin: basketWindow.expanded ? 12 : -basketWindow.basketSize
                    verticalCenter: parent.verticalCenter
                }

                DropArea {
                    id: basketDropArea

                    anchors.fill: parent
                    onEntered: drag => {
                        if (!basketWindow.isFileDrag(drag))
                            return;

                        drag.accept(Qt.CopyAction);
                        basketWindow.dragOverBasket = true;
                        hideTimer.stop();
                    }
                    onExited: {
                        basketWindow.dragOverBasket = false;
                        hideTimer.restart();
                    }
                    onDropped: drop => {
                        return basketWindow.addFiles(drop);
                    }
                }

                ColumnLayout {
                    spacing: 10

                    anchors {
                        fill: parent
                        margins: 16
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "inventory_2"
                            iconSize: 24
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            text: Translation.tr("File basket")
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 28
                            height: 28
                            radius: width / 2
                            color: clearMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                            visible: basketWindow.files.length > 0

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 19
                                color: Appearance.colors.colOnLayer1
                            }

                            MouseArea {
                                id: clearMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: basketWindow.clearFiles()
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: basketWindow.files.length === 0
                        text: Translation.tr("Drop files here")
                        color: Appearance.colors.colOnLayer1Inactive
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: fileColumn.implicitHeight
                        clip: true

                        Column {
                            id: fileColumn

                            width: parent.width
                            spacing: 5

                            Repeater {
                                model: basketWindow.files

                                delegate: Rectangle {
                                    id: fileTile

                                    required property var modelData

                                    width: fileColumn.width
                                    height: 40
                                    radius: Appearance.rounding.normal
                                    readonly property string sourcePath: decodeURIComponent(FileUtils.trimFileProtocol(modelData.url))
                                    color: fileHover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer2

                                    RowLayout {
                                        spacing: 8

                                        anchors {
                                            fill: parent
                                            leftMargin: 8
                                            rightMargin: 8
                                        }

                                        Item {
                                            width: 24
                                            height: 24
                                            Layout.preferredWidth: width
                                            Layout.preferredHeight: height

                                            Image {
                                                id: fileImage
                                                anchors.fill: parent
                                                source: Images.isValidImageByName(fileTile.modelData.name.toLowerCase()) ? fileTile.modelData.url : ""
                                                sourceSize: Qt.size(48, 48)
                                                fillMode: Image.PreserveAspectCrop
                                                visible: status === Image.Ready
                                                asynchronous: true
                                                clip: true
                                            }

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                visible: fileImage.status !== Image.Ready
                                                text: "draft"
                                                iconSize: 20
                                                color: Appearance.colors.colPrimary
                                            }
                                        }

                                        StyledText {
                                            text: fileTile.modelData.name
                                            elide: Text.ElideMiddle
                                            color: Appearance.colors.colOnLayer1
                                            Layout.fillWidth: true
                                        }

                                        MaterialSymbol {
                                            text: "drag_indicator"
                                            iconSize: 18
                                            color: Appearance.colors.colOnLayer1Inactive
                                        }
                                    }

                                    HoverHandler {
                                        id: fileHover
                                        cursorShape: Qt.OpenHandCursor
                                    }

                                    DragHandler {
                                        id: fileDrag
                                        target: null
                                        onActiveChanged: {
                                            if (!active)
                                                return;
                                            const grabbing = fileTile.grabToImage(result => {
                                                if (fileDrag.active)
                                                    basketWindow.startFileDrag(fileTile, result);
                                            });
                                            if (!grabbing)
                                                basketWindow.startFileDrag(fileTile, null);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Behavior on anchors.rightMargin {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutCubic
                    }
                }
            }

            mask: Region {
                regions: [
                    Region {
                        item: edgeDropArea
                    },
                    Region {
                        item: basketBackground
                        intersection: Intersection.Combine
                    }
                ]
            }
        }
    }
}
