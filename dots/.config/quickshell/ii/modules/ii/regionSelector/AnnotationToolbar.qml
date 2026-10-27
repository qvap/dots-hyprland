pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "AnnotationLayout.js" as AnnotationLayout

// MD3 toolbar for the screenshot annotation editor. Mutates AnnotationState for
// tool/colour/width; surfaces the actions as signals for the owning overlay.
Item {
    id: root

    signal undo()
    signal clearAll()
    signal copy()
    signal save()
    signal close()

    readonly property var tools: [
        { id: "select", icon: "arrow_selector_tool", tip: Translation.tr("Select (V)") },
        { id: "rect", icon: "check_box_outline_blank", tip: Translation.tr("Rectangle (R)") },
        { id: "ellipse", icon: "circle", tip: Translation.tr("Ellipse (O)") },
        { id: "arrow", icon: "north_east", tip: Translation.tr("Arrow (A)") },
        { id: "line", icon: "horizontal_rule", tip: Translation.tr("Line (L)") },
        { id: "pen", icon: "gesture", tip: Translation.tr("Pen (P)") },
        { id: "highlight", icon: "ink_highlighter", tip: Translation.tr("Highlighter (H)") },
        { id: "text", icon: "title", tip: Translation.tr("Text (T)") },
        { id: "counter", icon: "counter_1", tip: Translation.tr("Number (N)") },
        { id: "pixelate", icon: "blur_on", tip: Translation.tr("Pixelate (X)") }
    ]

    opacity: visible ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    onVisibleChanged: if (!visible) optionsPopup.close()

    property rect selection
    readonly property int buttonSize: 40

    function arrange() {
        if (root.width <= 0 || root.height <= 0) return;
        const buttons = Array.from(root.children).filter(child => child.width === root.buttonSize);
        const positions = AnnotationLayout.positions(root.selection, root.width, root.height,
            buttons.length, root.buttonSize, 6, 8);
        buttons.forEach((button, index) => {
            if (!positions[index]) return;
            button.x = positions[index].x;
            button.y = positions[index].y;
        });
    }
    onSelectionChanged: Qt.callLater(arrange)
    onWidthChanged: Qt.callLater(arrange)
    onHeightChanged: Qt.callLater(arrange)
    onChildrenChanged: Qt.callLater(arrange)
    Component.onCompleted: Qt.callLater(arrange)

    // ---- Tools ---------------------------------------------------------------
    Repeater {
        model: root.tools
        delegate: AnnotationButton {
            width: root.buttonSize
            height: root.buttonSize
            colBackground: Appearance.m3colors.m3surfaceContainer
            required property var modelData
            text: modelData.icon
            toggled: AnnotationState.tool === modelData.id
            onClicked: AnnotationState.tool = modelData.id
            StyledToolTip { text: modelData.tip }
        }
    }


    // ---- Colour and brush size -----------------------------------------------
    AnnotationButton {
        id: colorButton
        width: root.buttonSize
        height: root.buttonSize
        colBackground: Appearance.m3colors.m3surfaceContainer
        onClicked: root.openOptions(colorButton, true)
        Rectangle {
            anchors.centerIn: parent
            width: 20
            height: 20
            radius: width / 2
            color: AnnotationState.strokeColor
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
        }
        StyledToolTip { text: Translation.tr("Color") }
    }
    AnnotationButton {
        id: sizeButton
        width: root.buttonSize
        height: root.buttonSize
        colBackground: Appearance.m3colors.m3surfaceContainer
        onClicked: root.openOptions(sizeButton, false)
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(AnnotationState.strokeWidth + 8, 22)
            height: width
            radius: width / 2
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledToolTip { text: Translation.tr("Stroke width") }
    }

    function openOptions(button, colors) {
        if (optionsPopup.opened && optionsPopup.colors === colors) {
            optionsPopup.close();
            return;
        }
        optionsPopup.colors = colors;
        optionsPopup.targetButton = button;
        optionsPopup.open();
    }

    Popup {
        id: optionsPopup
        property bool colors: true
        property Item targetButton
        parent: root
        padding: 8
        x: Math.max(8, Math.min((targetButton?.x ?? 0) + (root.buttonSize - width) / 2, root.width - width - 8))
        y: {
            const below = (targetButton?.y ?? 0) + root.buttonSize + 6;
            return below + height <= root.height - 8 ? below
                : Math.max(8, (targetButton?.y ?? 0) - height - 6);
        }
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainer
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
        }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 }
            NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: 120; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100 }
        }
        contentItem: GridLayout {
            columns: 4
            rowSpacing: 4
            columnSpacing: 4
            Repeater {
                model: optionsPopup.colors ? AnnotationState.palette : AnnotationState.strokeWidths
                delegate: IconToolbarButton {
                    required property var modelData
                    implicitWidth: 40
                    implicitHeight: 40
                    toggled: optionsPopup.colors
                        ? Qt.colorEqual(AnnotationState.strokeColor, modelData)
                        : AnnotationState.strokeWidth === modelData
                    onClicked: {
                        if (optionsPopup.colors) AnnotationState.strokeColor = modelData;
                        else AnnotationState.strokeWidth = modelData;
                        optionsPopup.close();
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: optionsPopup.colors ? 20 : Math.min(modelData + 8, 22)
                        height: width
                        radius: width / 2
                        color: optionsPopup.colors ? modelData : Appearance.colors.colOnSurfaceVariant
                        border.width: optionsPopup.colors ? 1 : 0
                        border.color: Appearance.colors.colOutlineVariant
                    }
                    StyledToolTip { text: String(modelData) }
                }
            }
        }
    }

    // ---- Actions -------------------------------------------------------------
    AnnotationButton {
        width: root.buttonSize
        height: root.buttonSize
        colBackground: Appearance.m3colors.m3surfaceContainer
        text: "undo"
        onClicked: root.undo()
        StyledToolTip { text: Translation.tr("Undo (Ctrl+Z)") }
    }
    AnnotationButton {
        width: root.buttonSize
        height: root.buttonSize
        colBackground: Appearance.m3colors.m3surfaceContainer
        text: "ink_eraser"
        onClicked: root.clearAll()
        StyledToolTip { text: Translation.tr("Clear all") }
    }
    AnnotationButton {
        width: root.buttonSize
        height: root.buttonSize
        colBackground: Appearance.m3colors.m3surfaceContainer
        text: "content_copy"
        toggled: true
        onClicked: root.copy()
        StyledToolTip { text: Translation.tr("Copy (Enter)") }
    }
    AnnotationButton {
        width: root.buttonSize
        height: root.buttonSize
        colBackground: Appearance.m3colors.m3surfaceContainer
        text: "download"
        onClicked: root.save()
        StyledToolTip { text: Translation.tr("Save (Ctrl+S)") }
    }
    AnnotationButton {
        width: root.buttonSize
        height: root.buttonSize
        colBackground: Appearance.m3colors.m3surfaceContainer
        text: "close"
        onClicked: root.close()
        StyledToolTip { text: Translation.tr("Cancel (Esc)") }
    }
}
