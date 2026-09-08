import QtQuick

// Owns the annotation model and the in-progress draft, and renders both on top
// of the frozen screenshot. Drawing gestures are fed in from the overlay's
// drawing MouseArea via beginDraft / updateDraft / endDraft. Text is handled
// specially through an inline editor.
// Ported from quickshot (github: AnnotationCanvas), ShotState -> AnnotationState.
Item {
    id: canvas

    // Committed annotations (array of plain objects). Reassigned wholesale so
    // the Repeater re-evaluates.
    property var annotations: []
    // The shape currently being dragged out, or null.
    property var draft: null
    // The frozen ScreencopyView, handed to pixelate annotations for sampling.
    property Item backdrop: null
    // The text annotation currently being typed, or null.
    property var editing: null

    property var _penPoints: null

    // The inline text editor lives in the overlay (above the drawing MouseArea)
    // rather than here, so it can be clicked into. These signals drive it.
    signal editStarted()
    signal editFinished()

    // ---- Committed annotations ----------------------------------------------
    Repeater {
        model: canvas.annotations
        delegate: AnnotationShape {
            required property var modelData
            ann: modelData
            backdrop: canvas.backdrop
        }
    }

    // ---- Live draft ----------------------------------------------------------
    AnnotationShape {
        ann: canvas.draft
        backdrop: canvas.backdrop
        visible: canvas.draft !== null
    }

    // ---- Gesture API ---------------------------------------------------------
    function beginDraft(gx, gy) {
        // Always commit a pending text edit before starting a new gesture.
        if (canvas.editing)
            finishEditing();

        var t = AnnotationState.tool;
        if (t === "text") {
            startTextEdit(gx, gy);
            return;
        }
        if (t === "counter") {
            pushAnnotation({
                type: "counter",
                x1: gx, y1: gy,
                color: String(AnnotationState.strokeColor),
                number: AnnotationState.counterValue,
                fontSize: AnnotationState.fontSize
            });
            AnnotationState.counterValue += 1;
            return;
        }
        if (t === "pen") {
            canvas._penPoints = [{ x: gx, y: gy }];
            canvas.draft = { type: "pen", points: canvas._penPoints.slice(),
                             color: String(AnnotationState.strokeColor), width: AnnotationState.strokeWidth };
            return;
        }
        canvas.draft = makeDraft(t, gx, gy, gx, gy);
    }

    function updateDraft(gx, gy) {
        if (!canvas.draft)
            return;
        if (canvas.draft.type === "pen") {
            canvas._penPoints.push({ x: gx, y: gy });
            canvas.draft = { type: "pen", points: canvas._penPoints.slice(),
                             color: canvas.draft.color, width: canvas.draft.width };
        } else {
            var d = canvas.draft;
            canvas.draft = makeDraft(d.type, d.x1, d.y1, gx, gy);
        }
    }

    function endDraft() {
        if (!canvas.draft)
            return;
        var d = canvas.draft;
        canvas.draft = null;
        canvas._penPoints = null;
        if (d.type === "pen") {
            if (d.points.length >= 2)
                pushAnnotation(d);
        } else if (Math.abs(d.x2 - d.x1) >= 3 || Math.abs(d.y2 - d.y1) >= 3) {
            pushAnnotation(d);
        }
    }

    function makeDraft(t, x1, y1, x2, y2) {
        return {
            type: t,
            x1: x1, y1: y1, x2: x2, y2: y2,
            color: String(AnnotationState.strokeColor),
            width: AnnotationState.strokeWidth
        };
    }

    function pushAnnotation(a) {
        canvas.annotations = canvas.annotations.concat([a]);
    }

    // ---- Text editing --------------------------------------------------------
    function startTextEdit(gx, gy) {
        canvas.editing = {
            type: "text",
            x1: gx, y1: gy,
            text: "",
            color: String(AnnotationState.strokeColor),
            fontSize: AnnotationState.fontSize
        };
        canvas.editStarted();
    }

    function finishEditing() {
        var e = canvas.editing;
        canvas.editing = null;
        if (e && e.text && e.text.trim().length > 0)
            pushAnnotation(e);
        canvas.editFinished();
    }

    function cancelEditing() {
        canvas.editing = null;
        canvas.editFinished();
    }

    // ---- Edit operations -----------------------------------------------------
    function undo() {
        if (canvas.editing) {
            cancelEditing();
            return;
        }
        if (canvas.annotations.length > 0)
            canvas.annotations = canvas.annotations.slice(0, canvas.annotations.length - 1);
    }

    function clearAll() {
        cancelEditing();
        canvas.annotations = [];
        AnnotationState.counterValue = 1;
    }

    // Ensure no editor/draft is left dangling before a grab.
    function commitDraft() {
        if (canvas.editing)
            finishEditing();
        if (canvas.draft)
            endDraft();
    }
}
