import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    configEntryName: "sun"
    hoverEnabled: true

    readonly property real cardSpacing: 12
    readonly property real cardHeight: 120
    property string sizeMode: root.configEntry.sizeMode ?? "2x2"
    readonly property bool compact: sizeMode === "1x2"

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    readonly property real dayMs: 86400000
    // DateTime.time ticks every minute; re-evaluate "now" with it
    readonly property date now: { DateTime.time; return new Date() }
    readonly property date sunrise: new Date((Weather.data?.sunriseTs ?? 0) * 1000)
    readonly property date sunset: new Date((Weather.data?.sunsetTs ?? 0) * 1000)
    readonly property bool hasData: (Weather.data?.sunriseTs ?? 0) > 0
    // shortcut: uses today's times for tomorrow's sunrise, off by ~2 min at most
    readonly property bool nextIsSunset: now >= sunrise && now < sunset

    function msOfDay(d) { return d.getHours() * 3600000 + d.getMinutes() * 60000 + d.getSeconds() * 1000 }
    function fmt(d) { return root.hasData ? Qt.locale().toString(d, Config.options?.time.format ?? "hh:mm") : "--:--" }

    WidgetCard {
        id: card
        implicitWidth: 132 * 2 + root.cardSpacing
        implicitHeight: root.compact ? root.cardHeight : root.cardHeight * 2 + root.cardSpacing
        widget: root

        ColumnLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 2

            RowLayout {
                spacing: 6
                MaterialSymbol {
                    iconSize: Appearance.font.pixelSize.large
                    text: root.nextIsSunset ? "wb_twilight" : "wb_sunny"
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.7
                }
                StyledText {
                    text: root.nextIsSunset ? Translation.tr("Sunset") : Translation.tr("Sunrise")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    visible: root.compact
                    text: root.fmt(root.nextIsSunset ? root.sunset : root.sunrise)
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnLayer0
                }
            }

            StyledText {
                visible: !root.compact
                text: root.fmt(root.nextIsSunset ? root.sunset : root.sunrise)
                font.pixelSize: 52
                font.features: { "tnum": 1 }
                color: Appearance.colors.colOnLayer0
            }

            Canvas {
                id: curve
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: -14
                Layout.rightMargin: -14
                property color fg: Appearance.colors.colOnLayer0
                onFgChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Connections {
                    target: root
                    function onNowChanged() { curve.requestPaint() }
                    function onSunriseChanged() { curve.requestPaint() }
                }

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    if (!root.hasData) return
                    const rise = root.msOfDay(root.sunrise), set = root.msOfDay(root.sunset)
                    const noon = (rise + set) / 2
                    const c = Math.cos(Math.PI * (set - rise) / root.dayMs)
                    const pad = 8, h = height - pad * 2
                    // cosine shifted so it crosses zero exactly at sunrise/sunset
                    const yAt = t => pad + (1 - (Math.cos(2 * Math.PI * (t - noon) / root.dayMs) + 1) / 2) * h
                    const horizon = yAt(rise)
                    const xAt = t => t / root.dayMs * width

                    ctx.lineWidth = 5
                    ctx.lineCap = "round"
                    for (const above of [false, true]) {
                        ctx.save()
                        ctx.beginPath()
                        ctx.rect(0, above ? 0 : horizon, width, above ? horizon : height)
                        ctx.clip()
                        ctx.strokeStyle = Qt.alpha(fg, above ? 0.45 : 0.15)
                        ctx.beginPath()
                        for (let x = 0; x <= width; x += 2) {
                            const y = yAt(x / width * root.dayMs)
                            x === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
                        }
                        ctx.stroke()
                        ctx.restore()
                    }

                    ctx.strokeStyle = Qt.alpha(fg, 0.5)
                    ctx.lineWidth = 1.5
                    ctx.beginPath(); ctx.moveTo(0, horizon); ctx.lineTo(width, horizon); ctx.stroke()

                    const t = root.msOfDay(root.now)
                    ctx.fillStyle = Qt.alpha(fg, 0.25)
                    ctx.beginPath(); ctx.arc(xAt(t), yAt(t), 13, 0, 2 * Math.PI); ctx.fill()
                    ctx.fillStyle = fg
                    ctx.beginPath(); ctx.arc(xAt(t), yAt(t), 8, 0, 2 * Math.PI); ctx.fill()
                }
            }

            StyledText {
                visible: !root.compact
                text: (root.nextIsSunset ? Translation.tr("Sunrise") : Translation.tr("Sunset")) + ": "
                    + root.fmt(root.nextIsSunset ? root.sunrise : root.sunset)
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer0
            }
        }

        ResizeHandler {
            anchorItem: card
            hoverActive: root.containsMouse
            locked: DesktopWidgets.locked
            currentWidth: card.implicitWidth
            resizeMode: "diagonal"
            onResizedXY: (dx, dy, startWidth) => {
                if (dy > root.cardHeight * 0.3) root.sizeMode = "2x2"
                else if (dy < -root.cardHeight * 0.3) root.sizeMode = "1x2"
            }
            onResizeFinished: root.configEntry.sizeMode = root.sizeMode
        }
    }
}
