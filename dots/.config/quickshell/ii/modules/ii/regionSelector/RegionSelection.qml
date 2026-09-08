pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    visible: false
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    // Modes
    // TODO: Ask: sidebar AI
    enum SnipAction { Copy, Edit, Search, CharRecognition, Record, RecordWithSound }
    enum SelectionMode { RectCorners, Circle }
    enum Phase { Select, Annotate, Post }
    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    property var phase: RegionSelection.Phase.Select
    signal dismiss()

    // Annotation editor (in-shell, ported from quickshot)
    signal annotateStarted()
    property bool otherAnnotating: false // another monitor owns the annotation session
    property string editMode: "" // "copy" | "save" for a pending grab

    // Styles
    property string screenshotDir: Directories.screenshotTemp
    property color overlayColor: ColorUtils.transparentize("#000000", 0.4)
    property color brightText: Appearance.m3colors.darkmode ? Appearance.colors.colOnLayer0 : Appearance.colors.colLayer0
    property color brightSecondary: Appearance.m3colors.darkmode ? Appearance.colors.colSecondary : Appearance.colors.colOnSecondary
    property color brightTertiary: Appearance.m3colors.darkmode ? Appearance.colors.colTertiary : Qt.lighter(Appearance.colors.colPrimary)
    property color selectionBorderColor: ColorUtils.mix(brightText, brightSecondary, 0.5)
    property color selectionFillColor: "#33ffffff"
    property color windowBorderColor: brightSecondary
    property color windowFillColor: ColorUtils.transparentize(windowBorderColor, 0.85)
    property color imageBorderColor: brightTertiary
    property color imageFillColor: ColorUtils.transparentize(imageBorderColor, 0.85)
    property color onBorderColor: "#ff000000"
    property real targetRegionOpacity: Config.options.regionSelector.targetRegions.opacity
    property bool contentRegionOpacity: Config.options.regionSelector.targetRegions.contentRegionOpacity

    // Vars for indicators
    readonly property var windows: [...HyprlandData.windowList].sort((a, b) => {
        // Sort floating=true windows before others
        if (a.floating === b.floating) return 0;
        return a.floating ? -1 : 1;
    })
    readonly property var layers: HyprlandData.layers
    readonly property real falsePositivePreventionRatio: 0.5

    // Screen & interaction vars
    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)
    readonly property real monitorScale: hyprlandMonitor.scale
    readonly property real monitorOffsetX: hyprlandMonitor.x
    readonly property real monitorOffsetY: hyprlandMonitor.y
    property int activeWorkspaceId: hyprlandMonitor.activeWorkspace?.id ?? 0
    property string screenshotPath: `${root.screenshotDir}/image-${screen.name}`
    property real dragStartX: 0
    property real dragStartY: 0
    property real draggingX: 0
    property real draggingY: 0
    property real dragDiffX: 0
    property real dragDiffY: 0
    property bool draggedAway: (dragDiffX !== 0 || dragDiffY !== 0)
    property bool dragging: false
    property list<point> points: []
    property var mouseButton: null
    property var imageRegions: []
    readonly property list<var> windowRegions: RegionFunctions.filterWindowRegionsByLayers(
        root.windows.filter(w => w.workspace.id === root.activeWorkspaceId),
        root.layerRegions
    ).map(window => {
        return {
            at: [window.at[0] - root.monitorOffsetX, window.at[1] - root.monitorOffsetY],
            size: [window.size[0], window.size[1]],
            class: window.class,
            title: window.title,
        }
    })
    readonly property list<var> layerRegions: {
        const layersOfThisMonitor = root.layers[root.hyprlandMonitor.name]
        const topLayers = layersOfThisMonitor?.levels["2"]
        if (!topLayers) return [];
        const nonBarTopLayers = topLayers
            .filter(layer => !(layer.namespace.includes(":bar") || layer.namespace.includes(":verticalBar") || layer.namespace.includes(":dock")))
            .map(layer => {
            return {
                at: [layer.x, layer.y],
                size: [layer.w, layer.h],
                namespace: layer.namespace,
            }
        })
        const offsetAdjustedLayers = nonBarTopLayers.map(layer => {
            return {
                at: [layer.at[0] - root.monitorOffsetX, layer.at[1] - root.monitorOffsetY],
                size: layer.size,
                namespace: layer.namespace,
            }
        });
        return offsetAdjustedLayers;
    }

    // Config
    property bool isCircleSelection: (root.selectionMode === RegionSelection.SelectionMode.Circle)
    property bool enableWindowRegions: Config.options.regionSelector.targetRegions.windows && !isCircleSelection
    property bool enableLayerRegions: Config.options.regionSelector.targetRegions.layers && !isCircleSelection
    property bool enableContentRegions: Config.options.regionSelector.targetRegions.content

    // Target
    property real targetedRegionX: -1
    property real targetedRegionY: -1
    property real targetedRegionWidth: 0
    property real targetedRegionHeight: 0
    function targetedRegionValid() {
        return (root.targetedRegionX >= 0 && root.targetedRegionY >= 0)
    }
    function setRegionToTargeted() {
        const padding = Config.options.regionSelector.targetRegions.selectionPadding; // Make borders not cut off n stuff
        root.regionX = root.targetedRegionX - padding;
        root.regionY = root.targetedRegionY - padding;
        root.regionWidth = root.targetedRegionWidth + padding * 2;
        root.regionHeight = root.targetedRegionHeight + padding * 2;
    }

    function updateTargetedRegion(x, y) {
        // Image regions
        const clickedRegion = root.imageRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedRegion) {
            root.targetedRegionX = clickedRegion.at[0];
            root.targetedRegionY = clickedRegion.at[1];
            root.targetedRegionWidth = clickedRegion.size[0];
            root.targetedRegionHeight = clickedRegion.size[1];
            return;
        }

        // Layer regions
        const clickedLayer = root.layerRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedLayer) {
            root.targetedRegionX = clickedLayer.at[0];
            root.targetedRegionY = clickedLayer.at[1];
            root.targetedRegionWidth = clickedLayer.size[0];
            root.targetedRegionHeight = clickedLayer.size[1];
            return;
        }

        // Window regions
        const clickedWindow = root.windowRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedWindow) {
            root.targetedRegionX = clickedWindow.at[0];
            root.targetedRegionY = clickedWindow.at[1];
            root.targetedRegionWidth = clickedWindow.size[0];
            root.targetedRegionHeight = clickedWindow.size[1];
            return;
        }

        root.targetedRegionX = -1;
        root.targetedRegionY = -1;
        root.targetedRegionWidth = 0;
        root.targetedRegionHeight = 0;
    }

    property real regionWidth: Math.abs(draggingX - dragStartX)
    property real regionHeight: Math.abs(draggingY - dragStartY)
    property real regionX: Math.min(dragStartX, draggingX)
    property real regionY: Math.min(dragStartY, draggingY)

    // Screenshot stuff
    TempScreenshotProcess {
        id: screenshotProc
        running: true
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        onExited: (exitCode, exitStatus) => {
            if (root.enableContentRegions) imageDetectionProcess.running = true;
            root.preparationDone = !checkRecordingProc.running;
        }
    }
    property bool isRecording: root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound
    property bool recordingShouldStop: false
    Process {
        id: checkRecordingProc
        running: isRecording
        command: ["pidof", "wf-recorder"]
        onExited: (exitCode, exitStatus) => {
            root.preparationDone = !screenshotProc.running
            root.recordingShouldStop = (exitCode === 0);
        }
    }
    property bool preparationDone: false
    onPreparationDoneChanged: {
        if (!preparationDone) return;
        if (root.isRecording && root.recordingShouldStop) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            root.dismiss();
            return;
        }
        root.visible = true;
    }

    Process {
        id: imageDetectionProcess
        command: ["bash", "-c", `${Directories.scriptPath}/images/find-regions-venv.sh ` 
            + `--hyprctl ` 
            + `--image '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' ` 
            + `--max-width ${Math.round(root.screen.width * root.falsePositivePreventionRatio)} ` 
            + `--max-height ${Math.round(root.screen.height * root.falsePositivePreventionRatio)} `]
        stdout: StdioCollector {
            id: imageDimensionCollector
            onStreamFinished: {
                imageRegions = RegionFunctions.filterImageRegions(
                    JSON.parse(imageDimensionCollector.text),
                    root.windowRegions
                );
            }
        }
    }

    function getScreenshotAction() {
        switch(root.action) {
            case RegionSelection.SnipAction.Copy:
                return ScreenshotAction.Action.Copy;
            case RegionSelection.SnipAction.Edit:
                return ScreenshotAction.Action.Edit;
            case RegionSelection.SnipAction.Search:
                return ScreenshotAction.Action.Search;
            case RegionSelection.SnipAction.CharRecognition:
                return ScreenshotAction.Action.CharRecognition;
            case RegionSelection.SnipAction.Record:
                return ScreenshotAction.Action.Record;
            case RegionSelection.SnipAction.RecordWithSound:
                return ScreenshotAction.Action.RecordWithSound;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                root.dismiss();
                return;
        }
    }

    // Execution after selection
    function snip() {
        // Validity check
        if (root.regionWidth <= 0 || root.regionHeight <= 0) {
            console.warn("[Region Selector] Invalid region size, skipping snip.");
            root.dismiss();
            return;
        }

        // Clamp region to screen bounds
        root.regionX = Math.max(0, Math.min(root.regionX, root.screen.width - root.regionWidth));
        root.regionY = Math.max(0, Math.min(root.regionY, root.screen.height - root.regionHeight));
        root.regionWidth = Math.max(0, Math.min(root.regionWidth, root.screen.width - root.regionX));
        root.regionHeight = Math.max(0, Math.min(root.regionHeight, root.screen.height - root.regionY));

        // Adjust action: default Copy launch upgrades to Edit on right-click.
        // An explicit Edit launch stays Edit regardless of button.
        if (root.action === RegionSelection.SnipAction.Copy) {
            root.action = root.mouseButton === Qt.RightButton ? RegionSelection.SnipAction.Edit : RegionSelection.SnipAction.Copy;
        }

        // Edit: annotate in-shell instead of shelling out to satty/swappy.
        if (root.action === RegionSelection.SnipAction.Edit) {
            AnnotationState.reset();
            root.phase = RegionSelection.Phase.Annotate;
            root.annotateStarted();
            keyHandler.forceActiveFocus();
            return;
        }

        const screenshotDir = Config.options.screenSnip.savePath !== "" ? //
            Config.options.screenSnip.savePath : "";
        var screenshotAction = root.getScreenshotAction();
        const command = ScreenshotAction.getCommand(
            root.regionX * root.monitorScale, //
            root.regionY * root.monitorScale, //
            root.regionWidth * root.monitorScale,// 
            root.regionHeight * root.monitorScale, //
            root.screenshotPath, //
            screenshotAction, //
            screenshotDir
        )
        Quickshell.execDetached(command);
        if (root.action == RegionSelection.SnipAction.Record || root.action == RegionSelection.SnipAction.RecordWithSound) {
            root.phase = RegionSelection.Phase.Post
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        } else {
            root.dismiss();
        }
    }

    // Clickable while selecting or annotating (unless another monitor annotates)
    mask: Region {
        item: (root.otherAnnotating || root.phase === RegionSelection.Phase.Post) ? null : mouseArea
    }

    // Exportable scene: frozen screenshot + annotations. Only this clipped
    // subtree is captured by grabToImage; selection chrome is a sibling below.
    // On export the clip is reframed to the region and the scene shifted up/left
    // so the region aligns to the clip origin (single-grab native-res crop).
    Item {
        id: exportClip
        clip: true
        x: 0
        y: 0
        width: root.width
        height: root.height
        visible: !root.otherAnnotating
            && (root.phase === RegionSelection.Phase.Select || root.phase === RegionSelection.Phase.Annotate)

        Item {
            id: captureRoot
            x: 0
            y: 0
            width: root.width
            height: root.height

            ScreencopyView { // For freezing
                id: screencopy
                anchors.fill: parent
                live: false
                captureSource: root.screen
            }

            AnnotationCanvas {
                id: canvas
                anchors.fill: parent
                backdrop: screencopy
                visible: root.phase === RegionSelection.Phase.Annotate
                onEditStarted: {
                    editor.text = "";
                    editor.forceActiveFocus();
                }
                onEditFinished: keyHandler.forceActiveFocus()
            }
        }
    }

    // Keyboard handling for both selection and annotation phases.
    Item {
        id: keyHandler
        anchors.fill: parent
        focus: root.visible && canvas.editing === null
        Keys.onPressed: (event) => root.handleKey(event)
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        visible: !root.otherAnnotating
        cursorShape: root.phase === RegionSelection.Phase.Select ? Qt.CrossCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true

        // Controls (selection phase only; annotation uses its own areas)
        onPressed: (mouse) => {
            if (root.phase !== RegionSelection.Phase.Select) return;
            root.dragStartX = mouse.x;
            root.dragStartY = mouse.y;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragging = true;
            root.mouseButton = mouse.button;
        }
        onReleased: (mouse) => {
            if (root.phase !== RegionSelection.Phase.Select) return;
            // Detect if it was a click -> Try to select targeted region
            if (root.draggingX === root.dragStartX && root.draggingY === root.dragStartY) {
                if (root.targetedRegionValid()) {
                    root.setRegionToTargeted();
                }
            }
            // Circle dragging?
            else if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                const padding = Config.options.regionSelector.circle.padding + Config.options.regionSelector.circle.strokeWidth / 2;
                const dragPoints = (root.points.length > 0) ? root.points : [{ x: mouseArea.mouseX, y: mouseArea.mouseY }];
                const maxX = Math.max(...dragPoints.map(p => p.x));
                const minX = Math.min(...dragPoints.map(p => p.x));
                const maxY = Math.max(...dragPoints.map(p => p.y));
                const minY = Math.min(...dragPoints.map(p => p.y));
                root.regionX = minX - padding;
                root.regionY = minY - padding;
                root.regionWidth = maxX - minX + padding * 2;
                root.regionHeight = maxY - minY + padding * 2;
            }
            root.snip();
        }
        onPositionChanged: (mouse) => {
            if (root.phase !== RegionSelection.Phase.Select) return;
            root.updateTargetedRegion(mouse.x, mouse.y);
            if (!root.dragging) return;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragDiffX = mouse.x - root.dragStartX;
            root.dragDiffY = mouse.y - root.dragStartY;
            root.points.push({ x: mouse.x, y: mouse.y });
        }
        
        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode === RegionSelection.SelectionMode.RectCorners
            sourceComponent: RectCornersSelectionDetails {
                regionX: root.regionX
                regionY: root.regionY
                regionWidth: root.regionWidth
                regionHeight: root.regionHeight
                mouseX: mouseArea.mouseX
                mouseY: mouseArea.mouseY
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                showAimLines: root.phase === RegionSelection.Phase.Select && Config.options.regionSelector.rect.showAimLines
                breathingBorderOnly: root.phase === RegionSelection.Phase.Post
            }
        }

        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode === RegionSelection.SelectionMode.Circle
            sourceComponent: CircleSelectionDetails {
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                points: root.points
            }
        }

        // The thing to the bottom-right with an icon
        CursorGuide {
            z: 9999
            visible: root.phase === RegionSelection.Phase.Select
            x: root.dragging ? root.regionX + root.regionWidth : mouseArea.mouseX
            y: root.dragging ? root.regionY + root.regionHeight : mouseArea.mouseY
            action: root.action
            selectionMode: root.selectionMode
        }

        // Window regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableWindowRegions) {
                        return root.windowRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 2
                required property var modelData
                clientDimensions: modelData
                showIcon: true
                targeted: !root.draggedAway && //
                    (root.targetedRegionX === modelData.at[0]  //
                    && root.targetedRegionY === modelData.at[1] //
                    && root.targetedRegionWidth === modelData.size[0] //
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                borderColor: root.windowBorderColor
                fillColor: targeted ? root.windowFillColor : "transparent"
                text: `${modelData.class}`
                radius: Appearance.rounding.windowRounding
            }
        }

        // Layer regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableLayerRegions) {
                        return root.layerRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 3
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway &&
                    (root.targetedRegionX === modelData.at[0] 
                    && root.targetedRegionY === modelData.at[1]
                    && root.targetedRegionWidth === modelData.size[0]
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                borderColor: root.windowBorderColor
                fillColor: targeted ? root.windowFillColor : "transparent"
                text: `${modelData.namespace}`
                radius: Appearance.rounding.windowRounding
            }
        }

        // Content regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableContentRegions) {
                        return root.imageRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 4
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway &&
                    (root.targetedRegionX === modelData.at[0] 
                    && root.targetedRegionY === modelData.at[1]
                    && root.targetedRegionWidth === modelData.size[0]
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.contentRegionOpacity
                borderColor: root.imageBorderColor
                fillColor: targeted ? root.imageFillColor : "transparent"
                text: Translation.tr("Content region")
            }
        }

        // Controls
        Row {
            id: regionSelectionControls
            z: 10
            visible: root.phase === RegionSelection.Phase.Select
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: -height
            }
            opacity: 0
            Connections {
                target: root
                function onVisibleChanged() {
                    if (!visible) return;
                    regionSelectionControls.anchors.bottomMargin = 8;
                    regionSelectionControls.opacity = 1;
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on anchors.bottomMargin {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            spacing: 6

            OptionsToolbar {
                Synchronizer on action {
                    property alias source: root.action
                }
                Synchronizer on selectionMode {
                    property alias source: root.selectionMode
                }
                onDismiss: root.dismiss();
            }
            ToolbarPairedFab {
                anchors.verticalCenter: parent.verticalCenter
                iconText: "close"
                onClicked: root.dismiss();
                StyledToolTip {
                    text: Translation.tr("Close")
                }
            }
        }

        // ---- Annotation phase ------------------------------------------------
        // Draw gestures, confined to the (now fixed) region.
        MouseArea {
            id: drawArea
            z: 5
            enabled: root.phase === RegionSelection.Phase.Annotate && AnnotationState.isDrawTool()
            visible: enabled
            x: root.regionX
            y: root.regionY
            width: root.regionWidth
            height: root.regionHeight
            acceptedButtons: Qt.LeftButton
            preventStealing: true
            cursorShape: Qt.CrossCursor
            onPressed: (mouse) => canvas.beginDraft(root.regionX + mouse.x, root.regionY + mouse.y)
            onPositionChanged: (mouse) => canvas.updateDraft(
                Math.max(root.regionX, Math.min(root.regionX + mouse.x, root.regionX + root.regionWidth)),
                Math.max(root.regionY, Math.min(root.regionY + mouse.y, root.regionY + root.regionHeight)))
            onReleased: (mouse) => canvas.endDraft()
        }

        // Inline text editor. Lives outside the captured subtree, so the live
        // editor is never part of the exported image (the committed Text is).
        TextInput {
            id: editor
            z: 6
            visible: canvas.editing !== null
            enabled: visible
            x: canvas.editing ? canvas.editing.x1 : 0
            y: canvas.editing ? canvas.editing.y1 : 0
            color: canvas.editing ? canvas.editing.color : "white"
            font.family: Appearance.font.family.main
            font.bold: true
            font.pixelSize: canvas.editing ? canvas.editing.fontSize : AnnotationState.fontSize
            selectByMouse: true
            cursorVisible: true
            onTextChanged: if (canvas.editing) canvas.editing.text = text
            onAccepted: canvas.finishEditing()
            onActiveFocusChanged: if (!activeFocus && canvas.editing) canvas.finishEditing()
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape) {
                    canvas.cancelEditing();
                    event.accepted = true;
                }
            }
        }

        AnnotationToolbar {
            id: annotationToolbar
            z: 10000
            visible: root.phase === RegionSelection.Phase.Annotate
            x: Math.max(8, Math.min(root.regionX, root.width - width - 8))
            y: {
                const below = root.regionY + root.regionHeight + 8;
                const above = root.regionY - height - 8;
                if (below + height <= root.height) return below;
                if (above >= 0) return above;
                return Math.max(8, Math.min(root.regionY + 8, root.height - height - 8));
            }
            onUndo: canvas.undo()
            onClearAll: canvas.clearAll()
            onCopy: root.exportEdit("copy")
            onSave: root.exportEdit("save")
            onClose: root.dismiss()
        }
    }

    // ---- Annotation export (grab -> save/copy) -------------------------------
    Timer {
        id: grabTimer
        interval: 24
        onTriggered: {
            const grab = exportClip.grabToImage((result) => root.deliverEdit(result));
            if (!grab) {
                root.abortExport();
                return;
            }
            grabWatchdog.start();
        }
    }
    Timer { // Recover instead of hanging if the grab callback never fires.
        id: grabWatchdog
        interval: 2500
        onTriggered: root.abortExport()
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            root.dismiss();
            event.accepted = true;
            return;
        }
        if (root.phase !== RegionSelection.Phase.Annotate) return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.exportEdit("copy");
            event.accepted = true;
            return;
        }
        if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_S) { root.exportEdit("save"); event.accepted = true; }
            else if (event.key === Qt.Key_C) { root.exportEdit("copy"); event.accepted = true; }
            else if (event.key === Qt.Key_Z) { canvas.undo(); event.accepted = true; }
            return;
        }
        const map = {};
        map[Qt.Key_R] = "rect";
        map[Qt.Key_O] = "ellipse";
        map[Qt.Key_A] = "arrow";
        map[Qt.Key_L] = "line";
        map[Qt.Key_P] = "pen";
        map[Qt.Key_H] = "highlight";
        map[Qt.Key_T] = "text";
        map[Qt.Key_N] = "counter";
        map[Qt.Key_X] = "pixelate";
        if (map[event.key] !== undefined) {
            AnnotationState.tool = map[event.key];
            event.accepted = true;
        }
    }

    function exportEdit(mode) {
        if (root.phase !== RegionSelection.Phase.Annotate || grabWatchdog.running) return;
        canvas.commitDraft();
        root.editMode = mode;
        const rx = Math.round(root.regionX);
        const ry = Math.round(root.regionY);
        const rw = Math.max(1, Math.round(root.regionWidth));
        const rh = Math.max(1, Math.round(root.regionHeight));
        // Reframe the clip to the region and shift the scene to its origin.
        exportClip.x = rx;
        exportClip.y = ry;
        exportClip.width = rw;
        exportClip.height = rh;
        captureRoot.x = -rx;
        captureRoot.y = -ry;
        grabTimer.start();
    }

    function abortExport() {
        grabWatchdog.stop();
        exportClip.x = 0;
        exportClip.y = 0;
        exportClip.width = Qt.binding(() => root.width);
        exportClip.height = Qt.binding(() => root.height);
        captureRoot.x = 0;
        captureRoot.y = 0;
        Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "image-x-generic",
            Translation.tr("Screenshot"), Translation.tr("Export failed, try again")]);
    }

    function deliverEdit(result) {
        grabWatchdog.stop();
        if (!result) {
            root.abortExport();
            return;
        }
        const outPath = `${root.screenshotDir}/edit-${root.screen.name}.png`;
        if (!result.saveToFile(outPath)) {
            root.abortExport();
            return;
        }
        Quickshell.execDetached(root.deliverCommand(root.editMode, outPath));
        root.dismiss();
    }

    function deliverCommand(mode, outPath) {
        const q = (s) => `'${StringUtils.shellSingleQuoteEscape(s)}'`;
        const configuredDir = Config.options.screenSnip.savePath;
        // Save always writes a file; copy only writes one if a dir is configured.
        const saveDir = (mode === "save")
            ? (configuredDir !== "" ? configuredDir : `${FileUtils.trimFileProtocol(Directories.pictures)}/Screenshots`)
            : configuredDir;
        const saved = (saveDir && saveDir !== "");
        let parts = [];
        if (saved) {
            parts.push(`mkdir -p ${q(saveDir)}`);
            parts.push(`cp ${q(outPath)} ${q(saveDir)}/"screenshot-$(date '+%Y-%m-%d_%H.%M.%S').png"`);
        }
        parts.push(`wl-copy --type image/png < ${q(outPath)}`);
        parts.push(`notify-send -a Quickshell -i ${q(outPath)} `
            + `'${Translation.tr("Screenshot")}' `
            + `'${saved ? Translation.tr("Saved and copied to clipboard") : Translation.tr("Copied to clipboard")}'`);
        return ["bash", "-c", parts.join(" && ")];
    }
}
