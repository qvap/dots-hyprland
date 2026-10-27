import QtQuick
import qs.services

ConfigSpinBox {
    id: root

    required property string optionKey
    property real factor: 1
    property real fallback: 0

    // StyledSpinBox rewrites its value from the text field, which drops bindings,
    // so live values are pushed in explicitly
    function sync() {
        root.value = Math.round(Number(HyprlandOptions.get(root.optionKey, root.fallback)) * root.factor)
    }
    Component.onCompleted: root.sync()
    Connections {
        target: HyprlandOptions
        function onValuesChanged() {
            root.sync()
        }
    }

    onValueModified: {
        const next = root.value / root.factor
        if (Math.abs(next - Number(HyprlandOptions.get(root.optionKey, root.fallback))) < 1e-6) return
        HyprlandOptions.apply(root.optionKey, next)
    }
}
