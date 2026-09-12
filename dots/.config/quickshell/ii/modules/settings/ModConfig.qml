import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    Process {
        id: translationProc
        property string locale: ""
        command: [Directories.aiTranslationScriptPath, translationProc.locale]
    }

    Process {
        id: bannerChooser
        command: ["kdialog", "--getopenfilename", Quickshell.env("HOME") + "/Pictures", "image/png image/jpg image/jpeg image/webp"]
        stdout: StdioCollector {
            id: bannerChooserOutput
        }
        onExited: code => {
            if (code === 0 && bannerChooserOutput.text.trim() !== "")
                Config.options.sidebar.bannerImage = bannerChooserOutput.text.trim();
        }
    }

    ContentSection {
        icon: "blur_linear"
        title: Translation.tr("Effects")

        ConfigSwitch {
            buttonIcon: "mode_off_on"
            text: Translation.tr("Enable")
            checked: Config.options.effects.enabled
            onCheckedChanged: {
                Config.options.effects.enabled = checked;
            }
            StyledToolTip {
                text: Translation.tr("Enable effects (AI Flow, etc.)")
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            text: Translation.tr('Effects are utilized using GLSL shaders, which can affect performance on low-end devices.')
        }
    }

    ContentSection {
        icon: "airwave"
        title: Translation.tr("AI Flow")

        ConfigSwitch {
            buttonIcon: "mode_off_on"
            text: Translation.tr("AI Flow Enabled")
            checked: Config.options.effects.aiFlowEnabled
            enabled: Config.options.effects.enabled
            onCheckedChanged: {
                Config.options.effects.aiFlowEnabled = checked;
            }
            StyledToolTip {
                text: Translation.tr("Enable AI Chat waves flow effect")
            }
        }
    }

    ContentSection {
        icon: "splitscreen_right"
        title: Translation.tr("Right Sidebar")

        ConfigSwitch {
            buttonIcon: "planner_banner_ad_pt"
            text: Translation.tr("Banner")
            checked: Config.options.sidebar.banner
            onCheckedChanged: Config.options.sidebar.banner = checked
        }

        ConfigRow {
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "image"
                mainText: Translation.tr("Choose banner")
                onClicked: bannerChooser.running = true
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "restart_alt"
                mainText: Translation.tr("Use wallpaper")
                enabled: Config.options.sidebar.bannerImage !== ""
                onClicked: Config.options.sidebar.bannerImage = ""
            }
        }
    }
}
