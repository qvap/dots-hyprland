import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    property real padding: 6
    implicitWidth: mainLayout.implicitWidth + padding * 2
    implicitHeight: mainLayout.implicitHeight + padding * 2
    color: Appearance.colors.colLayer2

    signal openDownloads()
    signal openLogin()

    RowLayout {
        id: mainLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 8

        RippleButton {
            downAction: () => WallpaperEngine.refresh()
            contentItem: MaterialSymbol {
                text: "refresh"
                iconSize: Appearance.font.pixelSize.larger
            }
            StyledToolTip {
                text: Translation.tr("Reload")
            }
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.normal
            text: Translation.tr("Wallpaper Engine Workshop")
        }

        StyledText {
            visible: text.length > 0
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: {
                const queued = WallpaperEngine.queue.length;
                const queuedText = queued > 0 ? " · " + Translation.tr("%1 queued").arg(queued) : "";
                if (WallpaperEngine.currentDownload.length === 0) return "";
                if (WallpaperEngine.downloadStatus === "login") return Translation.tr("Logging in to Steam...") + queuedText;
                if (WallpaperEngine.downloadStatus === "confirm") return Translation.tr("Confirm the sign-in in the Steam app") + queuedText;
                return Translation.tr("Downloading %1%").arg(Math.round(WallpaperEngine.downloadProgress * 100)) + queuedText;
            }
        }

        MaterialSymbol {
            text: WallpaperEngine.usingApi ? "key" : "public"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colSubtext
            MouseArea {
                id: sourceHover
                anchors.fill: parent
                hoverEnabled: true
            }
            StyledToolTip {
                extraVisibleCondition: sourceHover.containsMouse
                text: WallpaperEngine.usingApi ? Translation.tr("Using the Steam Web API") : Translation.tr("Reading the public Workshop page\nSet an API key in settings for the official API")
            }
        }

        RippleButton {
            toggled: WallpaperEngine.loginRequired
            downAction: () => root.openLogin()
            contentItem: MaterialSymbol {
                text: "account_circle"
                iconSize: Appearance.font.pixelSize.larger
                color: WallpaperEngine.loginRequired ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
            StyledToolTip {
                text: WallpaperEngine.options.steamUser.length > 0
                    ? Translation.tr("Steam account: %1\nClick to sign in again").arg(WallpaperEngine.options.steamUser)
                    : Translation.tr("Sign in to Steam")
            }
        }

        RippleButton {
            downAction: () => root.openDownloads()
            contentItem: MaterialSymbol {
                text: "folder_open"
                iconSize: Appearance.font.pixelSize.larger
            }
            StyledToolTip {
                text: Translation.tr("Show downloaded wallpapers")
            }
        }
    }
}
