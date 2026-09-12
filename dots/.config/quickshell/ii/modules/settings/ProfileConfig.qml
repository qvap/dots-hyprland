import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: page
    property string hostnameInput: SystemInfo.hostname

    FolderListModel {
        id: avatarFolderModel
        folder: Config.options.profile.avatarPath !== ""
            ? Qt.resolvedUrl(Config.options.profile.avatarPath)
            : ""
        showDirs: false
        nameFilters: ["*.png", "*.svg", "*.jpg", "*.jpeg", "*.webp"]
    }

    Process {
        id: hostnameSetProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                SystemInfo.refreshHostname()
        }
    }

    Process {
        id: avatarFolderChooser
        command: ["kdialog", "--getexistingdirectory", Quickshell.env("HOME")]
        stdout: StdioCollector {
            id: avatarFolderChooserOutput
        }
        onExited: code => {
            if (code === 0 && avatarFolderChooserOutput.text.trim() !== "") {
                Config.options.profile.avatarPath = avatarFolderChooserOutput.text.trim()
                Config.options.profile.avatarPicture = ""
            }
        }
    }

    function applyHostname() {
        const newName = page.hostnameInput.trim()
        if (newName.length === 0 || newName === SystemInfo.hostname)
            return
        hostnameSetProc.command = ["hostnamectl", "set-hostname", newName]
        hostnameSetProc.running = true
    }

    Connections {
        target: SystemInfo
        function onHostnameChanged() {
            page.hostnameInput = SystemInfo.hostname
        }
    }

    ContentSection {
        icon: "person"
        shape: MaterialShape.Shape.Circle
        title: Translation.tr("Avatar")

        GroupedList {
            ConfigTextArea {
                id: avatarField
                Layout.fillWidth: true
                buttonIcon: "folder_open"
                text: Translation.tr("Avatar Folder Path")
                placeholderText: Translation.tr("Leave empty to use ~/.face, e.g. /home/youruser/Pictures/avatar")
                value: Config.options.profile.avatarPath
                onValueChanged: avatarDebounceTimer.restart()
                confirmButtonVisible: true
                confirmButtonIcon: "folder_open"
                onConfirmClicked: avatarFolderChooser.running = true

                Timer {
                    id: avatarDebounceTimer
                    interval: 800
                    repeat: false
                    onTriggered: Config.options.profile.avatarPath = avatarField.value
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8
                visible: Config.options.profile.avatarPath !== ""

                Repeater {
                    model: avatarFolderModel
                    delegate: Rectangle {
                        required property string filePath
                        width: 64
                        height: 64
                        radius: width / 2
                        color: Appearance.colors.colLayer2
                        property bool isSelected: FileUtils.trimFileProtocol(filePath.toString())
                            === Config.options.profile.avatarPicture

                        Image {
                            anchors.fill: parent
                            source: filePath
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: width * 2
                            sourceSize.height: height * 2
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: 64
                                    height: 64
                                    radius: 32
                                }
                            }
                        }

                        Rectangle {
                            visible: parent.isSelected
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            width: 20
                            height: 20
                            radius: 10
                            color: Appearance.colors.colPrimary

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "check"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnPrimary
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.options.profile.avatarPicture =
                                FileUtils.trimFileProtocol(filePath.toString())
                        }
                    }
                }
            }

            StyledText {
                visible: Config.options.profile.avatarPath === ""
                text: Translation.tr("Leave the path empty to use ~/.face")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    ContentSection {
        icon: "badge"
        shape: MaterialShape.Shape.Slanted
        title: Translation.tr("Identity")

        GroupedList {
            ConfigTextArea {
                id: displayNameField
                buttonIcon: "badge"
                text: Translation.tr("Display name")
                placeholderText: SystemInfo.username
                value: Config.options.profile.displayName
                onValueChanged: displayNameDebounce.restart()

                Timer {
                    id: displayNameDebounce
                    interval: 800
                    repeat: false
                    onTriggered: Config.options.profile.displayName = displayNameField.value
                }
            }

            ConfigTextArea {
                id: hostnameField
                buttonIcon: "dns"
                text: Translation.tr("Hostname")
                description: Translation.tr("Requires authentication to change")
                placeholderText: SystemInfo.hostname
                value: page.hostnameInput
                onValueChanged: page.hostnameInput = value
                confirmButtonVisible: page.hostnameInput.trim() !== ""
                    && page.hostnameInput.trim() !== SystemInfo.hostname
                onConfirmClicked: page.applyHostname()
            }
        }
    }
}
