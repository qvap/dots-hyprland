import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell.Hyprland

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "sync_alt"
        title: Translation.tr("Parallax")

        ConfigSwitch {
            buttonIcon: "unfold_more_double"
            text: Translation.tr("Vertical")
            checked: Config.options.background.parallax.vertical
            onCheckedChanged: {
                Config.options.background.parallax.vertical = checked;
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "counter_1"
                text: Translation.tr("Depends on workspace")
                checked: Config.options.background.parallax.enableWorkspace
                onCheckedChanged: {
                    Config.options.background.parallax.enableWorkspace = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "side_navigation"
                text: Translation.tr("Depends on sidebars")
                checked: Config.options.background.parallax.enableSidebar
                onCheckedChanged: {
                    Config.options.background.parallax.enableSidebar = checked;
                }
            }
        }
        ConfigSpinBox {
            icon: "loupe"
            text: Translation.tr("Preferred wallpaper zoom (%)")
            value: Config.options.background.parallax.workspaceZoom * 100
            from: 10
            to: 200
            stepSize: 1
            onValueChanged: {
                Config.options.background.parallax.workspaceZoom = value / 100;
            }
        }
    }

    ContentSection {
        icon: "movie"
        title: Translation.tr("Video wallpaper")

        ContentSubsection {
            title: Translation.tr("Pause playback")
            ConfigSelectionArray {
                currentValue: Config.options.background.videoWallpaper.pauseMode
                onSelected: newValue => {
                    Config.options.background.videoWallpaper.pauseMode = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Never"),
                        icon: "play_circle",
                        value: "never"
                    },
                    {
                        displayName: Translation.tr("Fullscreen"),
                        icon: "fullscreen",
                        value: "fullscreen"
                    },
                    {
                        displayName: Translation.tr("Covered by windows"),
                        icon: "select_window",
                        value: "tiled"
                    },
                ]
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "blur_linear"
                text: Translation.tr("Crossfade on change")
                checked: Config.options.background.videoWallpaper.crossfade
                onCheckedChanged: {
                    Config.options.background.videoWallpaper.crossfade = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("Play audio")
                checked: Config.options.background.videoWallpaper.audio
                onCheckedChanged: {
                    Config.options.background.videoWallpaper.audio = checked;
                }
            }
        }

        ConfigSpinBox {
            visible: Config.options.background.videoWallpaper.audio
            icon: "volume_down"
            text: Translation.tr("Volume (%)")
            value: Config.options.background.videoWallpaper.volume
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.background.videoWallpaper.volume = value;
            }
        }

        ConfigSpinBox {
            icon: "speed"
            text: Translation.tr("Playback speed (%)")
            value: Config.options.background.videoWallpaper.speed * 100
            from: 10
            to: 400
            stepSize: 5
            onValueChanged: {
                Config.options.background.videoWallpaper.speed = value / 100;
            }
        }
    }

    ContentSection {
        id: settingsClock
        icon: "clock_loader_40"
        title: Translation.tr("Widget: Clock")

        function stylePresent(styleName) {
            if (!Config.options.background.widgets.clock.showOnlyWhenLocked && Config.options.background.widgets.clock.style === styleName) {
                return true;
            }
            if (Config.options.background.widgets.clock.styleLocked === styleName) {
                return true;
            }
            return false;
        }

        readonly property bool digitalPresent: stylePresent("digital")
        readonly property bool cookiePresent: stylePresent("cookie")
        readonly property bool dailyPresent: stylePresent("daily")
        readonly property bool pixelPresent: stylePresent("pixel")

        ConfigRow {
            Layout.fillWidth: true

            ConfigSwitch {
                Layout.fillWidth: false
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.background.widgets.clock.enable
                onCheckedChanged: {
                    Config.options.background.widgets.clock.enable = checked;
                }
            }
            Item {
                Layout.fillWidth: true
            }
            ConfigSelectionArray {
                Layout.fillWidth: false
                currentValue: Config.options.background.widgets.clock.placementStrategy
                onSelected: newValue => {
                    Config.options.background.widgets.clock.placementStrategy = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Draggable"),
                        icon: "drag_pan",
                        value: "free"
                    },
                    {
                        displayName: Translation.tr("Least busy"),
                        icon: "category",
                        value: "leastBusy"
                    },
                    {
                        displayName: Translation.tr("Most busy"),
                        icon: "shapes",
                        value: "mostBusy"
                    },
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "lock_clock"
            text: Translation.tr("Show only when locked")
            checked: Config.options.background.widgets.clock.showOnlyWhenLocked
            onCheckedChanged: {
                Config.options.background.widgets.clock.showOnlyWhenLocked = checked;
            }
        }

        ConfigRow {
            ContentSubsection {
                visible: !Config.options.background.widgets.clock.showOnlyWhenLocked
                title: Translation.tr("Clock style")
                Layout.fillWidth: true
                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock.style
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.style = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Digital"),
                            icon: "timer_10",
                            value: "digital"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Daily"),
                            icon: "today",
                            value: "daily"
                        },
                        {
                            displayName: Translation.tr("Pixel"),
                            icon: "grid_on",
                            value: "pixel"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Clock style (locked)")
                Layout.fillWidth: false
                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock.styleLocked
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.styleLocked = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Digital"),
                            icon: "timer_10",
                            value: "digital"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Daily"),
                            icon: "today",
                            value: "daily"
                        },
                        {
                            displayName: Translation.tr("Pixel"),
                            icon: "grid_on",
                            value: "pixel"
                        }
                    ]
                }
            }
        }

        ConfigComboBox {
            Layout.fillWidth: true
            buttonIcon: "palette"
            text: Translation.tr("Clock color")
            model: [
                { displayName: Translation.tr("Automatic"), value: "" },
                { displayName: Translation.tr("Primary"), value: "primary" },
                { displayName: Translation.tr("Secondary"), value: "secondary" },
                { displayName: Translation.tr("Tertiary"), value: "tertiary" },
                { displayName: Translation.tr("Primary container"), value: "primaryContainer" },
                { displayName: Translation.tr("Secondary container"), value: "secondaryContainer" },
                { displayName: Translation.tr("Tertiary container"), value: "tertiaryContainer" },
                { displayName: Translation.tr("Layer 1"), value: "layer1" },
                { displayName: Translation.tr("Layer 0"), value: "layer0" }
            ]
            currentValue: Config.options.background.widgets.clock.color
            onSelected: newValue => Config.options.background.widgets.clock.color = newValue
        }

        ContentSubsection {
            visible: settingsClock.dailyPresent
            title: Translation.tr("Daily clock variant")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.daily.variant
                onSelected: newValue => Config.options.background.widgets.clock.daily.variant = newValue
                options: [
                    { displayName: Translation.tr("Badge"), icon: "cookie", value: "badge" },
                    { displayName: Translation.tr("Morning"), icon: "wb_twilight", value: "morning" },
                    { displayName: Translation.tr("Script"), icon: "draw", value: "script" },
                    { displayName: Translation.tr("Bold"), icon: "format_bold", value: "bold" }
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.pixelPresent
            title: Translation.tr("Pixel clock orientation")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.pixel.orientation
                onSelected: newValue => Config.options.background.widgets.clock.pixel.orientation = newValue
                options: [
                    { displayName: Translation.tr("Vertical"), icon: "stay_current_portrait", value: "vertical" },
                    { displayName: Translation.tr("Horizontal"), icon: "stay_current_landscape", value: "horizontal" }
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.digitalPresent
            title: Translation.tr("Digital clock settings")
            tooltip: Translation.tr("Font width and roundness settings are only available for some fonts like Google Sans Flex")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "vertical_distribute"
                    text: Translation.tr("Vertical")
                    checked: Config.options.background.widgets.clock.digital.vertical
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.vertical = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "animation"
                    text: Translation.tr("Animate time change")
                    checked: Config.options.background.widgets.clock.digital.animateChange
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.animateChange = checked;
                    }
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "date_range"
                    text: Translation.tr("Show date")
                    checked: Config.options.background.widgets.clock.digital.showDate
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.showDate = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "activity_zone"
                    text: Translation.tr("Use adaptive alignment")
                    checked: Config.options.background.widgets.clock.digital.adaptiveAlignment
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.adaptiveAlignment = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Aligns the date and quote to left, center or right depending on its position on the screen.")
                    }
                }
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family")
                text: Config.options.background.widgets.clock.digital.font.family
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.background.widgets.clock.digital.font.family = text;
                }
            }

            ConfigSlider {
                text: Translation.tr("Font weight")
                value: Config.options.background.widgets.clock.digital.font.weight
                usePercentTooltip: false
                buttonIcon: "format_bold"
                from: 1
                to: 1000
                stopIndicatorValues: [350]
                onValueChanged: {
                    Config.options.background.widgets.clock.digital.font.weight = value;
                }
            }

            ConfigSlider {
                text: Translation.tr("Font size")
                value: Config.options.background.widgets.clock.digital.font.size
                usePercentTooltip: false
                buttonIcon: "format_size"
                from: 50
                to: 700
                stopIndicatorValues: [90]
                onValueChanged: {
                    Config.options.background.widgets.clock.digital.font.size = value;
                }
            }

            ConfigSlider {
                text: Translation.tr("Font width")
                value: Config.options.background.widgets.clock.digital.font.width
                usePercentTooltip: false
                buttonIcon: "fit_width"
                from: 25
                to: 125
                stopIndicatorValues: [100]
                onValueChanged: {
                    Config.options.background.widgets.clock.digital.font.width = value;
                }
            }
            ConfigSlider {
                text: Translation.tr("Font roundness")
                value: Config.options.background.widgets.clock.digital.font.roundness
                usePercentTooltip: false
                buttonIcon: "line_curve"
                from: 0
                to: 100
                onValueChanged: {
                    Config.options.background.widgets.clock.digital.font.roundness = value;
                }
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Cookie clock settings")

            ConfigSwitch {
                buttonIcon: "wand_stars"
                text: Translation.tr("Auto styling with Gemini")
                checked: Config.options.background.widgets.clock.cookie.aiStyling
                onCheckedChanged: {
                    Config.options.background.widgets.clock.cookie.aiStyling = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Uses Gemini to categorize the wallpaper then picks a preset based on it.\nYou'll need to set Gemini API key on the left sidebar first.\nImages are downscaled for performance, but just to be safe,\ndo not select wallpapers with sensitive information.")
                }
            }

            ConfigSwitch {
                buttonIcon: "airwave"
                text: Translation.tr("Use old sine wave cookie implementation")
                checked: Config.options.background.widgets.clock.cookie.useSineCookie
                onCheckedChanged: {
                    Config.options.background.widgets.clock.cookie.useSineCookie = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Looks a bit softer and more consistent with different number of sides,\nbut has less impressive morphing")
                }
            }

            ConfigSpinBox {
                icon: "add_triangle"
                text: Translation.tr("Sides")
                value: Config.options.background.widgets.clock.cookie.sides
                from: 0
                to: 40
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.clock.cookie.sides = value;
                }
            }

            ConfigSwitch {
                buttonIcon: "autoplay"
                text: Translation.tr("Constantly rotate")
                checked: Config.options.background.widgets.clock.cookie.constantlyRotate
                onCheckedChanged: {
                    Config.options.background.widgets.clock.cookie.constantlyRotate = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Makes the clock always rotate. This is extremely expensive\n(expect 50% usage on Intel UHD Graphics) and thus impractical.")
                }
            }

            ConfigRow {

                ConfigSwitch {
                    enabled: Config.options.background.widgets.clock.cookie.dialNumberStyle === "dots" || Config.options.background.widgets.clock.cookie.dialNumberStyle === "full"
                    buttonIcon: "brightness_7"
                    text: Translation.tr("Hour marks")
                    checked: Config.options.background.widgets.clock.cookie.hourMarks
                    onEnabledChanged: {
                        checked = Config.options.background.widgets.clock.cookie.hourMarks;
                    }
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.cookie.hourMarks = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Can only be turned on using the 'Dots' or 'Full' dial style for aesthetic reasons")
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.background.widgets.clock.cookie.dialNumberStyle !== "numbers"
                    buttonIcon: "timer_10"
                    text: Translation.tr("Digits in the middle")
                    checked: Config.options.background.widgets.clock.cookie.timeIndicators
                    onEnabledChanged: {
                        checked = Config.options.background.widgets.clock.cookie.timeIndicators;
                    }
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.cookie.timeIndicators = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Can't be turned on when using 'Numbers' dial style for aesthetic reasons")
                    }
                }
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Dial style")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.cookie.dialNumberStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock.cookie.dialNumberStyle = newValue;
                    if (newValue !== "dots" && newValue !== "full") {
                        Config.options.background.widgets.clock.cookie.hourMarks = false;
                    }
                    if (newValue === "numbers") {
                        Config.options.background.widgets.clock.cookie.timeIndicators = false;
                    }
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "none"
                    },
                    {
                        displayName: Translation.tr("Dots"),
                        icon: "graph_6",
                        value: "dots"
                    },
                    {
                        displayName: Translation.tr("Full"),
                        icon: "history_toggle_off",
                        value: "full"
                    },
                    {
                        displayName: Translation.tr("Numbers"),
                        icon: "counter_1",
                        value: "numbers"
                    }
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Hour hand")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.cookie.hourHandStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock.cookie.hourHandStyle = newValue;
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "hide"
                    },
                    {
                        displayName: Translation.tr("Classic"),
                        icon: "radio",
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Hollow"),
                        icon: "circle",
                        value: "hollow"
                    },
                    {
                        displayName: Translation.tr("Fill"),
                        icon: "eraser_size_5",
                        value: "fill"
                    },
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Minute hand")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.cookie.minuteHandStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock.cookie.minuteHandStyle = newValue;
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "hide"
                    },
                    {
                        displayName: Translation.tr("Classic"),
                        icon: "radio",
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Thin"),
                        icon: "line_end",
                        value: "thin"
                    },
                    {
                        displayName: Translation.tr("Medium"),
                        icon: "eraser_size_2",
                        value: "medium"
                    },
                    {
                        displayName: Translation.tr("Bold"),
                        icon: "eraser_size_4",
                        value: "bold"
                    },
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Second hand")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.cookie.secondHandStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock.cookie.secondHandStyle = newValue;
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "hide"
                    },
                    {
                        displayName: Translation.tr("Classic"),
                        icon: "radio",
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Line"),
                        icon: "line_end",
                        value: "line"
                    },
                    {
                        displayName: Translation.tr("Dot"),
                        icon: "adjust",
                        value: "dot"
                    },
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Date style")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.cookie.dateStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock.cookie.dateStyle = newValue;
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "hide"
                    },
                    {
                        displayName: Translation.tr("Bubble"),
                        icon: "bubble_chart",
                        value: "bubble"
                    },
                    {
                        displayName: Translation.tr("Border"),
                        icon: "rotate_right",
                        value: "border"
                    },
                    {
                        displayName: Translation.tr("Rect"),
                        icon: "rectangle",
                        value: "rect"
                    }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Quote")

            ConfigSwitch {
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.background.widgets.clock.quote.enable
                onCheckedChanged: {
                    Config.options.background.widgets.clock.quote.enable = checked;
                }
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Quote")
                text: Config.options.background.widgets.clock.quote.text
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.background.widgets.clock.quote.text = text;
                }
            }
        }
    }

    ContentSection {
        icon: "weather_mix"
        title: Translation.tr("Widget: Weather")

        ConfigRow {
            Layout.fillWidth: true

            ConfigSwitch {
                Layout.fillWidth: false
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.background.widgets.weather.enable
                onCheckedChanged: {
                    Config.options.background.widgets.weather.enable = checked;
                }
            }
            Item {
                Layout.fillWidth: true
            }
            ConfigSelectionArray {
                Layout.fillWidth: false
                currentValue: Config.options.background.widgets.weather.placementStrategy
                onSelected: newValue => {
                    Config.options.background.widgets.weather.placementStrategy = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Draggable"),
                        icon: "drag_pan",
                        value: "free"
                    },
                    {
                        displayName: Translation.tr("Least busy"),
                        icon: "category",
                        value: "leastBusy"
                    },
                    {
                        displayName: Translation.tr("Most busy"),
                        icon: "shapes",
                        value: "mostBusy"
                    },
                ]
            }
        }
    }

    ContentSection {
        icon: "graphic_eq"
        title: Translation.tr("Widget: Visualizer")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: Config.options.background.widgets.visualizer.enable
            onCheckedChanged: Config.options.background.widgets.visualizer.enable = checked
        }

        ContentSubsection {
            title: Translation.tr("Style")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.visualizer.style
                onSelected: newValue => Config.options.background.widgets.visualizer.style = newValue
                options: [
                    { displayName: Translation.tr("Classic"), icon: "equalizer", value: "bars" },
                    { displayName: Translation.tr("Mirror"), icon: "flip", value: "mirror" },
                    { displayName: Translation.tr("Aurora"), icon: "auto_awesome", value: "aurora" },
                    { displayName: Translation.tr("Ring"), icon: "radio_button_unchecked", value: "ring" },
                    { displayName: Translation.tr("Dots"), icon: "more_horiz", value: "dots" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Colors")
            visible: Config.options.background.widgets.visualizer.style !== "bars"
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.visualizer.colorSource
                onSelected: newValue => Config.options.background.widgets.visualizer.colorSource = newValue
                options: [
                    { displayName: Translation.tr("Theme"), icon: "palette", value: "theme" },
                    { displayName: Translation.tr("Album cover"), icon: "album", value: "cover" }
                ]
            }
        }

        ConfigSlider {
            Layout.fillWidth: true
            buttonIcon: "speed"
            text: Translation.tr("Sensitivity (%)")
            usePercentTooltip: false
            from: 50
            to: 300
            value: Config.options.background.widgets.visualizer.sensitivity * 100
            onValueChanged: Config.options.background.widgets.visualizer.sensitivity = Math.round(value) / 100
        }
        ConfigSlider {
            Layout.fillWidth: true
            visible: ["aurora", "dots", "mirror"].includes(Config.options.background.widgets.visualizer.style)
            buttonIcon: "height"
            text: Translation.tr("Height")
            usePercentTooltip: false
            from: 120
            to: 600
            value: Config.options.background.widgets.visualizer.height
            onValueChanged: Config.options.background.widgets.visualizer.height = Math.round(value)
        }
        ConfigSlider {
            Layout.fillWidth: true
            visible: Config.options.background.widgets.visualizer.style === "ring"
            buttonIcon: "radio_button_unchecked"
            text: Translation.tr("Ring size")
            usePercentTooltip: false
            from: 200
            to: 900
            value: Config.options.background.widgets.visualizer.ringSize
            onValueChanged: Config.options.background.widgets.visualizer.ringSize = Math.round(value)
        }
    }

    ContentSection {
        icon: "text_fields"
        title: Translation.tr("Widget: Text")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.background.widgets.customText.enable
                onCheckedChanged: Config.options.background.widgets.customText.enable = checked
            }
            ConfigSwitch {
                buttonIcon: "shadow"
                text: Translation.tr("Shadow")
                checked: Config.options.background.widgets.customText.shadow
                onCheckedChanged: Config.options.background.widgets.customText.shadow = checked
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Text to display")
            text: Config.options.background.widgets.customText.content
            wrapMode: TextEdit.Wrap
            onTextChanged: Config.options.background.widgets.customText.content = text
        }

        ConfigComboBox {
            Layout.fillWidth: true
            buttonIcon: "font_download"
            text: Translation.tr("Font family")
            model: Fonts.handwritingFamilies.map(family => ({ displayName: family, value: family }))
            currentValue: Config.options.background.widgets.customText.fontFamily
            onSelected: newValue => Config.options.background.widgets.customText.fontFamily = newValue
        }

        ConfigSlider {
            Layout.fillWidth: true
            buttonIcon: "format_size"
            text: Translation.tr("Font size")
            usePercentTooltip: false
            from: 12
            to: 400
            value: Config.options.background.widgets.customText.fontSize
            onValueChanged: Config.options.background.widgets.customText.fontSize = Math.round(value)
        }

        ContentSubsection {
            title: Translation.tr("Alignment")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.customText.alignment
                onSelected: newValue => Config.options.background.widgets.customText.alignment = newValue
                options: [
                    { displayName: Translation.tr("Left"), icon: "format_align_left", value: "left" },
                    { displayName: Translation.tr("Center"), icon: "format_align_center", value: "center" },
                    { displayName: Translation.tr("Right"), icon: "format_align_right", value: "right" }
                ]
            }
        }

        ConfigComboBox {
            Layout.fillWidth: true
            buttonIcon: "palette"
            text: Translation.tr("Color")
            model: [
                { displayName: Translation.tr("Automatic"), value: "" },
                { displayName: Translation.tr("Primary"), value: "primary" },
                { displayName: Translation.tr("Secondary"), value: "secondary" },
                { displayName: Translation.tr("Tertiary"), value: "tertiary" },
                { displayName: Translation.tr("Primary container"), value: "primaryContainer" },
                { displayName: Translation.tr("Secondary container"), value: "secondaryContainer" },
                { displayName: Translation.tr("Tertiary container"), value: "tertiaryContainer" },
                { displayName: Translation.tr("Layer 1"), value: "layer1" },
                { displayName: Translation.tr("Layer 0"), value: "layer0" }
            ]
            currentValue: Config.options.background.widgets.customText.color
            onSelected: newValue => Config.options.background.widgets.customText.color = newValue
        }
    }

    ContentSection {
        icon: "imagesmode"
        title: Translation.tr("Widget: Images")

        ConfigComboBox {
            Layout.fillWidth: true
            buttonIcon: "interests"
            text: Translation.tr("Custom image shape")
            searchable: true
            model: ["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"].map(shape => ({ displayName: shape, value: shape }))
            currentValue: Config.options.background.widgets.customImage.shape
            onSelected: newValue => Config.options.background.widgets.customImage.shape = newValue
        }

        ContentSubsection {
            title: Translation.tr("Image card layout")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.imageCard.sizeMode
                onSelected: newValue => Config.options.background.widgets.imageCard.sizeMode = newValue
                options: [
                    { displayName: "1x1", icon: "crop_square", value: "1x1" },
                    { displayName: "1x2", icon: "crop_landscape", value: "1x2" },
                    { displayName: "1x3", icon: "crop_16_9", value: "1x3" },
                    { displayName: "2x2", icon: "grid_view", value: "2x2" },
                    { displayName: "2x3", icon: "view_module", value: "2x3" }
                ]
            }
        }
    }

    ContentSection {
        icon: "lock"
        title: Translation.tr("Lock screen wallpaper")

        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Path to an image or video (empty = same as desktop)")
            text: Config.options.background.lockWall
            onTextChanged: Config.options.background.lockWall = text
        }
    }

    ContentSection {
        icon: "widgets"
        shape: MaterialShape.Shape.Pill
        title: Translation.tr("Desktop widgets")

        ContentSubsection {
            title: Translation.tr("Show widgets on")
            visible: Hyprland.monitors.values.length > 1
            WidgetsMonitorSelector {
                configEntry: Config.options.background
            }
        }

        ContentSubsection {
            title: Translation.tr("Widgets")
            tooltip: Translation.tr("Starred widgets can also be toggled from the desktop menu (right-click the desktop)")
            GroupedList {
                ColumnLayout {
                    spacing: 0
                    Repeater {
                        model: DesktopWidgets.catalog
                        delegate: RowLayout {
                            id: widgetRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4
                            ConfigSwitch {
                                Layout.fillWidth: true
                                buttonIcon: widgetRow.modelData.icon
                                text: widgetRow.modelData.name
                                checked: DesktopWidgets.isEnabled(widgetRow.modelData.key)
                                onCheckedChanged: {
                                    if (checked !== DesktopWidgets.isEnabled(widgetRow.modelData.key))
                                        DesktopWidgets.setEnabled(widgetRow.modelData.key, checked);
                                }
                            }
                            RippleButton {
                                implicitWidth: 34
                                implicitHeight: 34
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                onClicked: DesktopWidgets.toggleStar(widgetRow.modelData.key)
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "star"
                                    fill: DesktopWidgets.isStarred(widgetRow.modelData.key) ? 1 : 0
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: DesktopWidgets.isStarred(widgetRow.modelData.key) ? Appearance.colors.colTertiary : Appearance.colors.colSubtext
                                }
                                StyledToolTip {
                                    text: DesktopWidgets.isStarred(widgetRow.modelData.key) ? Translation.tr("Shown in the desktop menu") : Translation.tr("Hidden from the desktop menu")
                                }
                            }
                        }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Canvas")
            GroupedList {
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "lock"
                    text: Translation.tr("Lock widget positions")
                    checked: Config.options.background.widgetsLocked
                    onCheckedChanged: Config.options.background.widgetsLocked = checked
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "lock_clock"
                    text: Translation.tr("Show widgets on the lock screen")
                    checked: Config.options.lock.showWidgets
                    onCheckedChanged: Config.options.lock.showWidgets = checked
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "grid_4x4"
                    text: Translation.tr("Show alignment grid while dragging")
                    checked: Config.options.background.showGrid
                    onCheckedChanged: Config.options.background.showGrid = checked
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "align_horizontal_center"
                    text: Translation.tr("Show snap lines when dropping")
                    checked: Config.options.background.showSnapLines
                    onCheckedChanged: Config.options.background.showSnapLines = checked
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
                    text: Translation.tr("Blur widget backgrounds")
                    checked: Config.options.background.widgets.blurWidgets
                    onCheckedChanged: Config.options.background.widgets.blurWidgets = checked
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "frame_source"
                    text: Translation.tr("Frosted glass")
                    checked: Config.options.background.widgets.glass.enable
                    onCheckedChanged: Config.options.background.widgets.glass.enable = checked
                }
            }
            ConfigSlider {
                Layout.fillWidth: true
                visible: Config.options.background.widgets.blurWidgets
                buttonIcon: "blur_medium"
                text: Translation.tr("Blur radius")
                usePercentTooltip: false
                from: 1
                to: 64
                value: Config.options.background.widgets.blurRadius
                onValueChanged: Config.options.background.widgets.blurRadius = value
            }
        }
    }
}
