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
}
