import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

MouseArea {
    id: root
    property int columns: 4
    property real previewCellAspectRatio: 4 / 3
    property bool useDarkMode: Appearance.m3colors.darkmode
    property bool workshopMode: false
    readonly property var activeGrid: root.workshopMode ? workshopGrid : grid

    onWorkshopModeChanged: {
        filterField.text = root.workshopMode ? WallpaperEngine.searchQuery : "";
        if (root.workshopMode) WallpaperEngine.ensureLoaded();
    }

    function updateThumbnails() {
        const totalImageMargin = (Appearance.sizes.wallpaperSelectorItemMargins + Appearance.sizes.wallpaperSelectorItemPadding) * 2;
        const thumbnailSizeName = Images.thumbnailSizeNameForDimensions(grid.cellWidth - totalImageMargin, grid.cellHeight - totalImageMargin);
        Wallpapers.generateThumbnail(thumbnailSizeName);
    }

    Connections {
        target: Wallpapers
        function onDirectoryChanged() {
            root.updateThumbnails();
        }
    }

    function handleFilePasting(event) {
        const currentClipboardEntry = Cliphist.entries[0];
        if (/^\d+\tfile:\/\/\S+/.test(currentClipboardEntry)) {
            const url = StringUtils.cleanCliphistEntry(currentClipboardEntry);
            Wallpapers.setDirectory(FileUtils.trimFileProtocol(decodeURIComponent(url)));
            event.accepted = true;
        } else {
            event.accepted = false; // No image, let text pasting proceed
        }
    }

    function selectWallpaperPath(filePath) {
        if (filePath && filePath.length > 0) {
            Wallpapers.select(filePath, root.useDarkMode);
            filterField.text = "";
        }
    }

    acceptedButtons: Qt.BackButton | Qt.ForwardButton
    onPressed: event => {
        if (event.button === Qt.BackButton) {
            Wallpapers.navigateBack();
        } else if (event.button === Qt.ForwardButton) {
            Wallpapers.navigateForward();
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            GlobalStates.wallpaperSelectorOpen = false;
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // Intercept Ctrl+V to handle "paste to go to" in pickers
            root.handleFilePasting(event);
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Up) {
            Wallpapers.navigateUp();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Left) {
            Wallpapers.navigateBack();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Right) {
            Wallpapers.navigateForward();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            root.activeGrid.moveSelection(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            root.activeGrid.moveSelection(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            root.activeGrid.moveSelection(-root.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            root.activeGrid.moveSelection(root.columns);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activeGrid.activateCurrent();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            if (filterField.text.length > 0) {
                filterField.text = filterField.text.substring(0, filterField.text.length - 1);
            }
            filterField.forceActiveFocus();
            event.accepted = true;
        } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_L) {
            addressBar.focusBreadcrumb();
            event.accepted = true;
        } else if (event.key === Qt.Key_Slash) {
            filterField.forceActiveFocus();
            event.accepted = true;
        } else {
            if (event.text.length > 0) {
                filterField.text += event.text;
                filterField.cursorPosition = filterField.text.length;
                filterField.forceActiveFocus();
            }
            event.accepted = true;
        }
    }

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: mainLayout.implicitWidth

    StyledRectangularShadow {
        target: wallpaperGridBackground
    }
    Rectangle {
        id: wallpaperGridBackground
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        focus: true
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        property int calculatedRows: Math.ceil(grid.count / grid.columns)

        implicitWidth: gridColumnLayout.implicitWidth
        implicitHeight: gridColumnLayout.implicitHeight

        RowLayout {
            id: mainLayout
            anchors.fill: parent
            spacing: -4

            Rectangle {
                Layout.fillHeight: true
                Layout.margins: 4
                implicitWidth: quickDirColumnLayout.implicitWidth
                implicitHeight: quickDirColumnLayout.implicitHeight
                color: Appearance.colors.colLayer1
                radius: wallpaperGridBackground.radius - Layout.margins

                ColumnLayout {
                    id: quickDirColumnLayout
                    anchors.fill: parent
                    spacing: 0

                    StyledText {
                        Layout.margins: 12
                        font {
                            pixelSize: Appearance.font.pixelSize.normal
                            weight: Font.Medium
                        }
                        text: Translation.tr("Pick a wallpaper")
                    }
                    ListView {
                        // Quick dirs
                        Layout.fillHeight: true
                        Layout.margins: 4
                        implicitWidth: 140
                        clip: true
                        model: [
                            {
                                icon: "home",
                                name: "Home",
                                path: Directories.home
                            },
                            {
                                icon: "docs",
                                name: "Documents",
                                path: Directories.documents
                            },
                            {
                                icon: "download",
                                name: "Downloads",
                                path: Directories.downloads
                            },
                            {
                                icon: "image",
                                name: "Pictures",
                                path: Directories.pictures
                            },
                            {
                                icon: "movie",
                                name: "Videos",
                                path: Directories.videos
                            },
                            {
                                icon: "",
                                name: "---",
                                path: "INTENTIONALLY_INVALID_DIR"
                            },
                            {
                                icon: "wallpaper",
                                name: "Wallpapers",
                                path: `${Directories.pictures}/Wallpapers`
                            },
                            ...(Config.options.policies.weeb === 1 ? [
                                    {
                                        icon: "favorite",
                                        name: "Homework",
                                        path: `${Directories.pictures}/homework`
                                    }
                                ] : []),
                            {
                                icon: "cloud_download",
                                name: "Workshop",
                                path: "",
                                workshop: true
                            },]
                        delegate: RippleButton {
                            id: quickDirButton
                            required property var modelData
                            anchors {
                                left: parent.left
                                right: parent.right
                            }
                            onClicked: {
                                root.workshopMode = quickDirButton.modelData.workshop ?? false;
                                if (!root.workshopMode) Wallpapers.setDirectory(quickDirButton.modelData.path);
                            }
                            enabled: modelData.icon.length > 0
                            toggled: (modelData.workshop ?? false) ? root.workshopMode : (!root.workshopMode && Wallpapers.directory === Qt.resolvedUrl(modelData.path))
                            StyledToolTip {
                                extraVisibleCondition: quickDirButton.modelData.workshop ?? false
                                text: Translation.tr("Wallpaper Engine video wallpapers from the Steam Workshop")
                            }
                            colBackgroundToggled: Appearance.colors.colSecondaryContainer
                            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                            colRippleToggled: Appearance.colors.colSecondaryContainerActive
                            buttonRadius: height / 2
                            implicitHeight: 38

                            contentItem: RowLayout {
                                MaterialSymbol {
                                    color: quickDirButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    iconSize: Appearance.font.pixelSize.larger
                                    text: quickDirButton.modelData.icon
                                    fill: quickDirButton.toggled ? 1 : 0
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignLeft
                                    color: quickDirButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    text: quickDirButton.modelData.name
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: gridColumnLayout
                Layout.fillWidth: true
                Layout.fillHeight: true

                AddressBar {
                    id: addressBar
                    visible: !root.workshopMode
                    Layout.margins: 4
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    directory: Wallpapers.effectiveDirectory
                    onNavigateToDirectory: path => {
                        Wallpapers.setDirectory(path.length == 0 ? "/" : path);
                    }
                    radius: wallpaperGridBackground.radius - Layout.margins
                }

                WallpaperEngineHeader {
                    visible: root.workshopMode
                    Layout.margins: 4
                    Layout.fillWidth: true
                    radius: wallpaperGridBackground.radius - Layout.margins
                    onOpenLogin: {
                        GlobalStates.wallpaperSelectorOpen = false;
                        WallpaperEngine.openLogin();
                    }
                    onOpenDownloads: {
                        root.workshopMode = false;
                        Wallpapers.setDirectory(WallpaperEngine.downloadDir);
                    }
                }

                Item {
                    id: gridDisplayRegion
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StyledIndeterminateProgressBar {
                        id: indeterminateProgressBar
                        visible: root.workshopMode ? WallpaperEngine.loading : (Wallpapers.thumbnailGenerationRunning && value == 0)
                        anchors {
                            bottom: parent.top
                            left: parent.left
                            right: parent.right
                            leftMargin: 4
                            rightMargin: 4
                        }
                    }

                    StyledProgressBar {
                        visible: !root.workshopMode && Wallpapers.thumbnailGenerationRunning && value > 0
                        value: Wallpapers.thumbnailGenerationProgress
                        anchors.fill: indeterminateProgressBar
                    }

                    GridView {
                        id: grid
                        visible: !root.workshopMode && Wallpapers.folderModel.count > 0

                        readonly property int columns: root.columns
                        readonly property int rows: Math.max(1, Math.ceil(count / columns))
                        property int currentIndex: 0

                        anchors.fill: parent
                        cellWidth: width / root.columns
                        cellHeight: cellWidth / root.previewCellAspectRatio
                        interactive: true
                        clip: true
                        keyNavigationWraps: true
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: extraOptions.implicitHeight
                        ScrollBar.vertical: StyledScrollBar {}

                        Component.onCompleted: {
                            root.updateThumbnails();
                        }

                        function moveSelection(delta) {
                            currentIndex = Math.max(0, Math.min(grid.model.count - 1, currentIndex + delta));
                            positionViewAtIndex(currentIndex, GridView.Contain);
                        }

                        function activateCurrent() {
                            const filePath = grid.model.get(currentIndex, "filePath");
                            root.selectWallpaperPath(filePath);
                        }

                        model: Wallpapers.folderModel
                        onModelChanged: currentIndex = 0
                        delegate: WallpaperDirectoryItem {
                            required property var modelData
                            required property int index
                            fileModelData: modelData
                            width: grid.cellWidth
                            height: grid.cellHeight
                            colBackground: (index === grid?.currentIndex || containsMouse) ? Appearance.colors.colPrimary : (fileModelData.filePath === Config.options.background.wallpaperPath) ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                            colText: (index === grid.currentIndex || containsMouse) ? Appearance.colors.colOnPrimary : (fileModelData.filePath === Config.options.background.wallpaperPath) ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0

                            onEntered: {
                                grid.currentIndex = index;
                            }

                            onActivated: {
                                root.selectWallpaperPath(fileModelData.filePath);
                            }
                        }

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: gridDisplayRegion.width
                                height: gridDisplayRegion.height
                                radius: wallpaperGridBackground.radius
                            }
                        }
                    }

                    GridView {
                        id: workshopGrid
                        visible: root.workshopMode

                        property int currentIndex: 0

                        anchors.fill: parent
                        cellWidth: width / root.columns
                        cellHeight: cellWidth / root.previewCellAspectRatio
                        interactive: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: extraOptions.implicitHeight
                        ScrollBar.vertical: StyledScrollBar {}

                        // Infinite scroll: also checked when a page lands, in case it doesn't fill the view.
                        // Height comes from count because contentHeight lags behind inserted rows
                        function loadMoreIfNearEnd() {
                            const rowsHeight = Math.ceil(count / root.columns) * cellHeight;
                            if (visible && count > 0 && contentY + height > rowsHeight - cellHeight * 2) WallpaperEngine.loadMore();
                        }
                        onContentYChanged: loadMoreIfNearEnd()
                        onCountChanged: {
                            if (currentIndex >= count) currentIndex = 0;
                            loadMoreIfNearEnd();
                        }

                        function moveSelection(delta) {
                            currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta));
                            positionViewAtIndex(currentIndex, GridView.Contain);
                        }

                        function activateCurrent() {
                            const item = WallpaperEngine.items[currentIndex];
                            if (item) WallpaperEngine.select(item.id, root.useDarkMode);
                        }

                        // ScriptModel diffs the array, so appending a page inserts rows instead of
                        // resetting the model (and the scroll position)
                        model: ScriptModel {
                            values: WallpaperEngine.items
                        }
                        delegate: WallpaperEngineItem {
                            required property var modelData
                            required property int index
                            itemData: modelData
                            width: workshopGrid.cellWidth
                            height: workshopGrid.cellHeight
                            readonly property bool isCurrentWallpaper: WallpaperEngine.downloadedFiles[modelData.id] === Config.options.background.wallpaperPath
                            colBackground: (index === workshopGrid.currentIndex || containsMouse) ? Appearance.colors.colPrimary : isCurrentWallpaper ? Appearance.colors.colSecondaryContainer : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                            colText: (index === workshopGrid.currentIndex || containsMouse) ? Appearance.colors.colOnPrimary : isCurrentWallpaper ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0

                            onEntered: workshopGrid.currentIndex = index
                            onActivated: WallpaperEngine.select(modelData.id, root.useDarkMode)
                            onCancelRequested: WallpaperEngine.cancel(modelData.id)
                        }

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: gridDisplayRegion.width
                                height: gridDisplayRegion.height
                                radius: wallpaperGridBackground.radius
                            }
                        }
                    }

                    PagePlaceholder {
                        shown: root.workshopMode && !WallpaperEngine.loading && WallpaperEngine.items.length === 0
                        icon: WallpaperEngine.errorMessage.length > 0 ? "cloud_off" : "search_off"
                        title: WallpaperEngine.errorMessage.length > 0 ? Translation.tr("Couldn't load the Workshop") : Translation.tr("Nothing found")
                        description: WallpaperEngine.errorMessage
                        shape: MaterialShape.Shape.Ghostish
                        descriptionHorizontalAlignment: Text.AlignHCenter
                    }

                    Row {
                        id: extraOptions
                        anchors {
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                            bottomMargin: 8
                        }
                        spacing: 6
                        Toolbar {

                            IconToolbarButton {
                                implicitWidth: height
                                onClicked: {
                                    Wallpapers.openFallbackPicker(root.useDarkMode);
                                    GlobalStates.wallpaperSelectorOpen = false;
                                }
                                altAction: () => {
                                    Wallpapers.openFallbackPicker(root.useDarkMode);
                                    GlobalStates.wallpaperSelectorOpen = false;
                                    Config.options.wallpaperSelector.useSystemFileDialog = true;
                                }
                                text: "open_in_new"
                                StyledToolTip {
                                    text: Translation.tr("Use the system file picker instead\nRight-click to make this the default behavior")
                                }
                            }

                            Repeater {
                                model: root.workshopMode ? [
                                    { sort: "trend", icon: "local_fire_department", tooltip: Translation.tr("Trending this week") },
                                    { sort: "top", icon: "star", tooltip: Translation.tr("Top rated") },
                                    { sort: "recent", icon: "schedule", tooltip: Translation.tr("Most recent") }
                                ] : []
                                delegate: IconToolbarButton {
                                    required property var modelData
                                    implicitWidth: height
                                    toggled: WallpaperEngine.sort === modelData.sort
                                    onClicked: WallpaperEngine.sort = modelData.sort
                                    text: modelData.icon
                                    StyledToolTip {
                                        text: parent.modelData.tooltip
                                    }
                                }
                            }

                            IconToolbarButton {
                                visible: !root.workshopMode
                                implicitWidth: height
                                onClicked: {
                                    Wallpapers.randomFromCurrentFolder();
                                }
                                text: "ifl"
                                StyledToolTip {
                                    text: Translation.tr("Pick random from this folder")
                                }
                            }

                            IconToolbarButton {
                                implicitWidth: height
                                onClicked: root.useDarkMode = !root.useDarkMode
                                text: root.useDarkMode ? "dark_mode" : "light_mode"
                                StyledToolTip {
                                    text: Translation.tr("Click to toggle light/dark mode\n(applied when wallpaper is chosen)")
                                }
                            }

                            ToolbarTextField {
                                id: filterField
                                placeholderText: focus ? (root.workshopMode ? Translation.tr("Search the Workshop") : Translation.tr("Search wallpapers")) : Translation.tr("Hit \"/\" to search")

                                // Style
                                clip: true
                                font.pixelSize: Appearance.font.pixelSize.small

                                // Search
                                onTextChanged: {
                                    if (root.workshopMode) WallpaperEngine.searchQuery = text;
                                    else Wallpapers.searchQuery = text;
                                }

                                Keys.onPressed: event => {
                                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // Intercept Ctrl+V to handle "paste to go to" in pickers
                                        root.handleFilePasting(event);
                                        return;
                                    } else if (text.length !== 0) {
                                        // No filtering, just navigate grid
                                        if (event.key === Qt.Key_Down) {
                                            root.activeGrid.moveSelection(root.columns);
                                            event.accepted = true;
                                            return;
                                        }
                                        if (event.key === Qt.Key_Up) {
                                            root.activeGrid.moveSelection(-root.columns);
                                            event.accepted = true;
                                            return;
                                        }
                                    }
                                    event.accepted = false;
                                }
                            }
                        }

                        ToolbarPairedFab {
                            iconText: "close"
                            onClicked: GlobalStates.wallpaperSelectorOpen = false;
                            StyledToolTip {
                                text: Translation.tr("Cancel wallpaper selection")
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onWallpaperSelectorOpenChanged() {
            if (GlobalStates.wallpaperSelectorOpen && monitorIsFocused) {
                filterField.forceActiveFocus();
            }
        }
    }

    Connections {
        target: Wallpapers
        function onChanged() {
            GlobalStates.wallpaperSelectorOpen = false;
        }
    }
}
