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
        icon: "palette"
        shape: MaterialShape.Shape.Pentagon
        title: Translation.tr("System Appearance")

        GroupedList {
            ConfigComboBox {
                Layout.fillWidth: true
                buttonIcon: "category"
                text: Translation.tr("Icon theme")
                fieldWidth: 260
                fixedWidth: true
                searchable: true
                model: SystemAppearance.toOptions(SystemAppearance.iconThemes)
                currentValue: Config.options.appearance.icons.theme || SystemAppearance.iconTheme
                onSelected: newValue => {
                    if (Config.options.appearance.icons.theme === newValue) return
                    Config.options.appearance.icons.theme = newValue
                    SystemAppearance.applyIconScheme()
                }
            }
            ConfigSwitch {
                buttonIcon: "brightness_6"
                text: Translation.tr("Follow color scheme")
                checked: Config.options.appearance.icons.followScheme
                onCheckedChanged: {
                    if (Config.options.appearance.icons.followScheme === checked) return
                    Config.options.appearance.icons.followScheme = checked
                    SystemAppearance.applyIconScheme()
                }
            }
            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Dynamic accent colors")
                checked: Config.options.appearance.icons.dynamicColor
                enabled: SystemAppearance.iconCapability() !== "none"
                onCheckedChanged: {
                    if (Config.options.appearance.icons.dynamicColor === checked) return
                    Config.options.appearance.icons.dynamicColor = checked
                    SystemAppearance.applyIconScheme()
                }
            }
            ConfigSwitch {
                buttonIcon: "shield"
                text: Translation.tr("Prevent Breeze override")
                checked: Config.options.appearance.icons.preventBreezeOverride
                onCheckedChanged: {
                    if (Config.options.appearance.icons.preventBreezeOverride === checked) return
                    Config.options.appearance.icons.preventBreezeOverride = checked
                    SystemAppearance.applyIconScheme()
                }
            }
            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "restart_alt"
                mainText: Translation.tr("Restore KDE icon settings")
                onClicked: {
                    // Stop re-syncing the wrapper before restoring its
                    // original values, otherwise the next apply would
                    // immediately overwrite them again.
                    Config.options.appearance.icons.preventBreezeOverride = false
                    SystemAppearance.restoreKdeIcons()
                }
            }
            ConfigComboBox {
                Layout.fillWidth: true
                buttonIcon: "mouse"
                text: Translation.tr("Cursor theme")
                fieldWidth: 260
                fixedWidth: true
                searchable: true
                model: SystemAppearance.toOptions(SystemAppearance.cursorThemes)
                currentValue: SystemAppearance.cursorTheme
                onSelected: newValue => SystemAppearance.setCursor(newValue, SystemAppearance.cursorSize)
            }
            ConfigSpinBox {
                icon: "ads_click"
                text: Translation.tr("Cursor size")
                value: SystemAppearance.cursorSize
                from: 16
                to: 64
                stepSize: 2
                onValueChanged: {
                    if (value !== SystemAppearance.cursorSize) SystemAppearance.setCursor(SystemAppearance.cursorTheme, value)
                }
            }
            ConfigComboBox {
                Layout.fillWidth: true
                buttonIcon: "text_fields"
                text: Translation.tr("System font")
                fieldWidth: 260
                fixedWidth: true
                searchable: true
                model: SystemAppearance.toOptions(SystemAppearance.fonts)
                currentValue: SystemAppearance.fontFamily
                onSelected: newValue => SystemAppearance.setFont("ui", newValue, SystemAppearance.fontSize)
            }
            ConfigSpinBox {
                icon: "format_size"
                text: Translation.tr("System font size")
                value: SystemAppearance.fontSize
                from: 8
                to: 20
                stepSize: 1
                onValueChanged: {
                    if (value !== SystemAppearance.fontSize) SystemAppearance.setFont("ui", SystemAppearance.fontFamily, value)
                }
            }
            ConfigComboBox {
                Layout.fillWidth: true
                buttonIcon: "terminal"
                text: Translation.tr("Monospace font")
                fieldWidth: 260
                fixedWidth: true
                searchable: true
                model: SystemAppearance.toOptions(SystemAppearance.fonts)
                currentValue: SystemAppearance.monoFamily
                onSelected: newValue => SystemAppearance.setFont("mono", newValue, SystemAppearance.monoSize)
            }
            ConfigSpinBox {
                icon: "format_size"
                text: Translation.tr("Monospace font size")
                value: SystemAppearance.monoSize
                from: 8
                to: 20
                stepSize: 1
                onValueChanged: {
                    if (value !== SystemAppearance.monoSize) SystemAppearance.setFont("mono", SystemAppearance.monoFamily, value)
                }
            }
        }
    }

    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Audio")

        ConfigSwitch {
            buttonIcon: "hearing"
            text: Translation.tr("Earbang protection")
            checked: Config.options.audio.protection.enable
            onCheckedChanged: {
                Config.options.audio.protection.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Prevents abrupt increments and restricts volume limit")
            }
        }
        ConfigRow {
            enabled: Config.options.audio.protection.enable
            ConfigSpinBox {
                icon: "arrow_warm_up"
                text: Translation.tr("Max allowed increase")
                value: Config.options.audio.protection.maxAllowedIncrease
                from: 0
                to: 100
                stepSize: 2
                onValueChanged: {
                    Config.options.audio.protection.maxAllowedIncrease = value;
                }
            }
            ConfigSpinBox {
                icon: "vertical_align_top"
                text: Translation.tr("Volume limit")
                value: Config.options.audio.protection.maxAllowed
                from: 0
                to: 154 // pavucontrol allows up to 153%
                stepSize: 2
                onValueChanged: {
                    Config.options.audio.protection.maxAllowed = value;
                }
            }
        }
    }

    ContentSection {
        icon: "battery_android_full"
        title: Translation.tr("Battery")

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "warning"
                text: Translation.tr("Low warning")
                value: Config.options.battery.low
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.low = value;
                }
            }
            ConfigSpinBox {
                icon: "dangerous"
                text: Translation.tr("Critical warning")
                value: Config.options.battery.critical
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.critical = value;
                }
            }
        }
        ConfigRow {
            uniform: false
            Layout.fillWidth: false
            ConfigSwitch {
                buttonIcon: "pause"
                text: Translation.tr("Automatic suspend")
                checked: Config.options.battery.automaticSuspend
                onCheckedChanged: {
                    Config.options.battery.automaticSuspend = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Automatically suspends the system when battery is low")
                }
            }
            ConfigSpinBox {
                enabled: Config.options.battery.automaticSuspend
                text: Translation.tr("at")
                value: Config.options.battery.suspend
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.suspend = value;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "charger"
                text: Translation.tr("Full warning")
                value: Config.options.battery.full
                from: 0
                to: 101
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.full = value;
                }
            }
        }
    }

    ContentSection {
        icon: "language"
        title: Translation.tr("Language")

        ContentSubsection {
            title: Translation.tr("Interface Language")
            tooltip: Translation.tr("Select the language for the user interface.\n\"Auto\" will use your system's locale.")

            StyledComboBox {
                id: languageSelector
                buttonIcon: "language"
                textRole: "displayName"

                model: [
                    {
                        displayName: Translation.tr("Auto (System)"),
                        value: "auto"
                    },
                    ...Translation.allAvailableLanguages.map(lang => {
                        return {
                            displayName: lang,
                            value: lang
                        };
                    })]

                currentIndex: {
                    const index = model.findIndex(item => item.value === Config.options.language.ui);
                    return index !== -1 ? index : 0;
                }

                onActivated: index => {
                    Config.options.language.ui = model[index].value;
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Generate translation with Gemini")
            tooltip: Translation.tr("You'll need to enter your Gemini API key first.\nType /key on the sidebar for instructions.")

            ConfigRow {
                MaterialTextArea {
                    id: localeInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Locale code, e.g. fr_FR, de_DE, zh_CN...")
                    text: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
                }
                RippleButtonWithIcon {
                    id: generateTranslationBtn
                    Layout.fillHeight: true
                    nerdIcon: ""
                    enabled: !translationProc.running || (translationProc.locale !== localeInput.text.trim())
                    mainText: enabled ? Translation.tr("Generate\nTypically takes 2 minutes") : Translation.tr("Generating...\nDon't close this window!")
                    onClicked: {
                        translationProc.locale = localeInput.text.trim();
                        translationProc.running = false;
                        translationProc.running = true;
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "rule"
        title: Translation.tr("Policies")

        ConfigRow {

            // AI policy
            ColumnLayout {
                ContentSubsectionLabel {
                    text: Translation.tr("AI")
                }

                ConfigSelectionArray {
                    currentValue: Config.options.policies.ai
                    onSelected: newValue => {
                        Config.options.policies.ai = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Local only"),
                            icon: "sync_saved_locally",
                            value: 2
                        }
                    ]
                }
            }

            // Weeb policy
            ColumnLayout {

                ContentSubsectionLabel {
                    text: Translation.tr("Weeb")
                }

                ConfigSelectionArray {
                    currentValue: Config.options.policies.weeb
                    onSelected: newValue => {
                        Config.options.policies.weeb = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Closet"),
                            icon: "ev_shadow",
                            value: 2
                        }
                    ]
                }
            }
        }
    }

    ContentSection {
        icon: "notification_sound"
        title: Translation.tr("Sounds")
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "battery_android_full"
                text: Translation.tr("Battery")
                checked: Config.options.sounds.battery
                onCheckedChanged: {
                    Config.options.sounds.battery = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "av_timer"
                text: Translation.tr("Pomodoro")
                checked: Config.options.sounds.pomodoro
                onCheckedChanged: {
                    Config.options.sounds.pomodoro = checked;
                }
            }
        }
    }

    ContentSection {
        icon: "nest_clock_farsight_analog"
        title: Translation.tr("Time")

        ConfigSwitch {
            buttonIcon: "pace"
            text: Translation.tr("Second precision")
            checked: Config.options.time.secondPrecision
            onCheckedChanged: {
                Config.options.time.secondPrecision = checked;
            }
            StyledToolTip {
                text: Translation.tr("Enable if you want clocks to show seconds accurately")
            }
        }

        ContentSubsection {
            title: Translation.tr("Format")
            tooltip: ""

            ConfigSelectionArray {
                currentValue: Config.options.time.format
                onSelected: newValue => {
                    if (newValue === "hh:mm") {
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME12\\b/TIME/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                    } else {
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME\\b/TIME12/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                    }

                    Config.options.time.format = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("24h"),
                        value: "hh:mm"
                    },
                    {
                        displayName: Translation.tr("12h am/pm"),
                        value: "h:mm ap"
                    },
                    {
                        displayName: Translation.tr("12h AM/PM"),
                        value: "h:mm AP"
                    },
                ]
            }
        }
    }

    ContentSection {
        icon: "calendar_month"
        title: Translation.tr("Calendar")

        ContentSubsection {
            title: Translation.tr("First day of week")

            ConfigSelectionArray {
                currentValue: Config.options.time.firstDayOfWeek

                onSelected: newValue => {
                    Config.options.time.firstDayOfWeek = newValue;
                }

                options: [
                    {
                        displayName: Translation.tr("Monday"),
                        value: 1
                    },
                    {
                        displayName: Translation.tr("Tuesday"),
                        value: 2
                    },
                    {
                        displayName: Translation.tr("Wednesday"),
                        value: 3
                    },
                    {
                        displayName: Translation.tr("Thursday"),
                        value: 4
                    },
                    {
                        displayName: Translation.tr("Friday"),
                        value: 5
                    },
                    {
                        displayName: Translation.tr("Saturday"),
                        value: 6
                    },
                    {
                        displayName: Translation.tr("Sunday"),
                        value: 0
                    },
                ]
            }
        }
    }

    ContentSection {
        icon: "work_alert"
        title: Translation.tr("Work safety")

        ConfigSwitch {
            buttonIcon: "assignment"
            text: Translation.tr("Hide clipboard images copied from sussy sources")
            checked: Config.options.workSafety.enable.clipboard
            onCheckedChanged: {
                Config.options.workSafety.enable.clipboard = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "wallpaper"
            text: Translation.tr("Hide sussy/anime wallpapers")
            checked: Config.options.workSafety.enable.wallpaper
            onCheckedChanged: {
                Config.options.workSafety.enable.wallpaper = checked;
            }
        }
    }
}
