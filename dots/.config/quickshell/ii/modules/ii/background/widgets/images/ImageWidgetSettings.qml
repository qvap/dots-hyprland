import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Gear button + flipped settings face shared by the image widgets
Item {
    id: root
    required property var widget
    property bool showingSettings: false
    // Not a default property: it would also swallow this file's own children
    property alias settings: settingsColumn.data

    anchors.fill: parent
    z: 100

    onShowingSettingsChanged: GlobalStates.desktopWidgetKeyboardFocus = showingSettings
    Component.onCompleted: widget.transform = [flipScale]

    function toggle() { flipAnim.start() }

    Scale {
        id: flipScale
        origin.x: root.widget.width / 2
        origin.y: root.widget.height / 2
    }
    SequentialAnimation {
        id: flipAnim
        NumberAnimation { target: flipScale; property: "xScale"; to: 0; duration: 150; easing.type: Easing.InQuad }
        ScriptAction { script: root.showingSettings = !root.showingSettings }
        NumberAnimation { target: flipScale; property: "xScale"; to: 1; duration: 150; easing.type: Easing.OutQuad }
    }

    Rectangle {
        anchors { top: parent.top; right: parent.right; margins: 8 }
        visible: !root.showingSettings && root.widget.containsMouse && !DesktopWidgets.locked
        radius: Appearance.rounding.full
        color: gearArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
        implicitWidth: 28; implicitHeight: 28
        MaterialSymbol {
            anchors.centerIn: parent
            iconSize: Appearance.font.pixelSize.normal
            text: "settings"
            color: Appearance.colors.colOnLayer2
        }
        MouseArea {
            id: gearArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle()
        }
    }

    // Image widgets are at least 252px (2x2), which fits the settings exactly
    Rectangle {
        visible: root.showingSettings
        width: Math.max(root.width, 252)
        height: Math.max(root.height, 252)
        radius: Appearance.rounding.verylarge
        color: Appearance.m3colors.m3surfaceContainer

        ColumnLayout {
            anchors { fill: parent; margins: 12 }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                IconToolbarButton {
                    Layout.fillHeight: false
                    implicitHeight: 32
                    text: "arrow_back"
                    onClicked: root.toggle()
                }
                Item { Layout.fillWidth: true }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "image"
                mainText: Translation.tr("Choose image")
                onClicked: DesktopWidgets.pickImage(path => root.widget.setEntry({ path: path }))
            }

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: settingsColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                TouchpadScrollArea { flickable: flick }

                ColumnLayout {
                    id: settingsColumn
                    width: flick.width
                    spacing: 6
                }
            }
        }
    }
}
