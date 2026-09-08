pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// MD3 toolbar for the screenshot annotation editor. Mutates AnnotationState for
// tool/colour/width; surfaces the actions as signals for the owning overlay.
Toolbar {
    id: root

    signal undo()
    signal clearAll()
    signal copy()
    signal save()
    signal close()

    readonly property var tools: [
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

    component Separator: Rectangle {
        Layout.fillHeight: true
        Layout.topMargin: 8
        Layout.bottomMargin: 8
        implicitWidth: 1
        color: Appearance.colors.colOutlineVariant
    }

    // ---- Tools ---------------------------------------------------------------
    Repeater {
        model: root.tools
        delegate: IconToolbarButton {
            required property var modelData
            text: modelData.icon
            toggled: AnnotationState.tool === modelData.id
            onClicked: AnnotationState.tool = modelData.id
            StyledToolTip { text: modelData.tip }
        }
    }

    Separator {}

    // ---- Colours -------------------------------------------------------------
    Repeater {
        model: AnnotationState.palette
        delegate: Item {
            id: swatch
            required property var modelData
            Layout.fillHeight: true
            implicitWidth: 28
            readonly property bool selected: Qt.colorEqual(AnnotationState.strokeColor, swatch.modelData)
            Rectangle {
                anchors.centerIn: parent
                width: 20
                height: 20
                radius: width / 2
                color: swatch.modelData
                border.width: swatch.selected ? 3 : 1
                border.color: swatch.selected ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: AnnotationState.strokeColor = swatch.modelData
            }
        }
    }

    Separator {}

    // ---- Stroke width --------------------------------------------------------
    Repeater {
        model: AnnotationState.strokeWidths
        delegate: Item {
            id: widthOption
            required property var modelData
            Layout.fillHeight: true
            implicitWidth: 28
            readonly property bool selected: AnnotationState.strokeWidth === widthOption.modelData
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(widthOption.modelData + 8, 22)
                height: width
                radius: width / 2
                color: widthOption.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: AnnotationState.strokeWidth = widthOption.modelData
            }
        }
    }

    Separator {}

    // ---- Actions -------------------------------------------------------------
    IconToolbarButton {
        text: "undo"
        onClicked: root.undo()
        StyledToolTip { text: Translation.tr("Undo (Ctrl+Z)") }
    }
    IconToolbarButton {
        text: "ink_eraser"
        onClicked: root.clearAll()
        StyledToolTip { text: Translation.tr("Clear all") }
    }
    IconToolbarButton {
        text: "content_copy"
        toggled: true
        onClicked: root.copy()
        StyledToolTip { text: Translation.tr("Copy (Enter)") }
    }
    IconToolbarButton {
        text: "download"
        onClicked: root.save()
        StyledToolTip { text: Translation.tr("Save (Ctrl+S)") }
    }
    IconToolbarButton {
        text: "close"
        onClicked: root.close()
        StyledToolTip { text: Translation.tr("Cancel (Esc)") }
    }
}
