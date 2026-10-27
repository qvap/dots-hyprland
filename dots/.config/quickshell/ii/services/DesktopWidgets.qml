pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

Singleton {
    id: root

    readonly property var catalog: [
        { key: "clock",       icon: "schedule",          name: Translation.tr("Clock") },
        { key: "weather",     icon: "partly_cloudy_day", name: Translation.tr("Weather") },
        { key: "calendar",    icon: "calendar_month",    name: Translation.tr("Calendar") },
        { key: "worldClock",  icon: "public",            name: Translation.tr("World Clock") },
        { key: "sun",         icon: "wb_twilight",       name: Translation.tr("Sunrise & Sunset") },
        { key: "media",       icon: "music_note",        name: Translation.tr("Media") },
        { key: "visualizer",  icon: "graphic_eq",        name: Translation.tr("Visualizer") },
        { key: "resources",   icon: "monitor_heart",     name: Translation.tr("Resources") },
        { key: "userCard",    icon: "person",            name: Translation.tr("User Card") },
        { key: "todo",        icon: "add_task",          name: Translation.tr("To-Do") },
        { key: "notes",       icon: "note_stack_add",    name: Translation.tr("Notes") },
        { key: "timers",      icon: "timer",             name: Translation.tr("Timers") },
        { key: "images",      icon: "photo_library",     name: Translation.tr("Image Converter") }
    ]

    // Image widgets aren't toggled: each button adds another copy (see addImageWidget)
    readonly property var imageCatalog: [
        { key: "customImage", icon: "image",             name: Translation.tr("Custom Image") },
        { key: "imageCard",   icon: "photo_size_select_large", name: Translation.tr("Image Card") },
        { key: "sticker",     icon: "sticker",           name: Translation.tr("Sticker") }
    ]

    // The widget editor unlocks moving and resizing without touching the saved lock
    readonly property bool locked: Config.options.background.widgetsLocked && !GlobalStates.widgetEditorOpen

    readonly property var hidden: Array.from(Config.options.background.widgets.menuHidden)
    readonly property var menuItems: catalog.filter(w => !hidden.includes(w.key))

    function isEnabled(key) {
        return Config.options.background.widgets[key].enable;
    }

    function setEnabled(key, value) {
        Config.options.background.widgets[key].enable = value;
    }

    function isStarred(key) {
        return !hidden.includes(key);
    }

    function setStarred(key, starred) {
        const next = hidden.filter(k => k !== key);
        if (!starred) next.push(key);
        Config.options.background.widgets.menuHidden = next;
    }

    function toggleStar(key) {
        setStarred(key, !isStarred(key));
    }

    function addImageWidget(type) {
        const list = Array.from(Config.options.background.widgets.imageInstances);
        const offset = (list.length % 8) * 36;
        list.push({ type: type, placementStrategy: "free", x: 400 + offset, y: 100 + offset, z: 0, path: "" });
        Config.options.background.widgets.imageInstances = list;
    }

    property var pickCallback: null
    function pickImage(callback) {
        root.pickCallback = callback;
        imagePicker.running = true;
    }

    Process {
        id: imagePicker
        command: ["kdialog", "--getopenfilename", Quickshell.env("HOME") + "/Pictures", "image/png image/jpeg image/webp image/gif image/avif image/bmp image/tiff image/svg+xml"]
        stdout: StdioCollector { id: imagePickerOutput }
        onExited: code => {
            const path = imagePickerOutput.text.trim();
            if (code === 0 && path !== "") root.pickCallback?.(path);
        }
    }
}
