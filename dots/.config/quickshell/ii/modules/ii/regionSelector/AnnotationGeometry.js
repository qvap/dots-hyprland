function bounds(annotation, textWidth, textHeight) {
    if (!annotation) return {x: 0, y: 0, width: 0, height: 0};
    if (annotation.type === "text") return {x: annotation.x1, y: annotation.y1, width: textWidth, height: textHeight};
    if (annotation.type === "counter") {
        const size = Math.max(24, annotation.fontSize * 1.25);
        return {x: annotation.x1 - size / 2, y: annotation.y1 - size / 2, width: size, height: size};
    }
    if (annotation.type === "pen" && annotation.points.length) {
        const xs = annotation.points.map(p => p.x), ys = annotation.points.map(p => p.y);
        return {x: Math.min(...xs), y: Math.min(...ys),
            width: Math.max(1, Math.max(...xs) - Math.min(...xs)), height: Math.max(1, Math.max(...ys) - Math.min(...ys))};
    }
    if (annotation.x2 !== undefined && annotation.y2 !== undefined)
        return {x: Math.min(annotation.x1, annotation.x2), y: Math.min(annotation.y1, annotation.y2),
            width: Math.max(1, Math.abs(annotation.x2 - annotation.x1)), height: Math.max(1, Math.abs(annotation.y2 - annotation.y1))};
    return {x: 0, y: 0, width: 0, height: 0};
}

function resize(rect, handle, dx, dy, limit, minimum, proportional) {
    if (proportional) {
        const sx = (rect.width + (handle.includes("w") ? -dx : dx)) / rect.width;
        const sy = (rect.height + (handle.includes("n") ? -dy : dy)) / rect.height;
        const requested = Math.abs(sx - 1) > Math.abs(sy - 1) ? sx : sy;
        const anchorX = rect.x + (handle.includes("w") ? rect.width : 0);
        const anchorY = rect.y + (handle.includes("n") ? rect.height : 0);
        const availableWidth = handle.includes("w") ? anchorX - limit.x : limit.x + limit.width - anchorX;
        const availableHeight = handle.includes("n") ? anchorY - limit.y : limit.y + limit.height - anchorY;
        const scale = Math.min(availableWidth / rect.width, availableHeight / rect.height,
            Math.max(minimum / rect.width, minimum / rect.height, requested));
        const width = rect.width * scale, height = rect.height * scale;
        return {x: anchorX - (handle.includes("w") ? width : 0),
            y: anchorY - (handle.includes("n") ? height : 0), width: width, height: height};
    }
    let left = rect.x, top = rect.y;
    let right = left + rect.width, bottom = top + rect.height;
    if (handle.includes("w")) left = Math.max(limit.x, Math.min(left + dx, right - minimum));
    if (handle.includes("e")) right = Math.min(limit.x + limit.width, Math.max(right + dx, left + minimum));
    if (handle.includes("n")) top = Math.max(limit.y, Math.min(top + dy, bottom - minimum));
    if (handle.includes("s")) bottom = Math.min(limit.y + limit.height, Math.max(bottom + dy, top + minimum));
    return {x: left, y: top, width: right - left, height: bottom - top};
}

function resizeAnnotation(annotation, original, rect) {
    const result = Object.assign({}, annotation, {x1: rect.x, y1: rect.y});
    if (annotation.type === "text") {
        const sx = rect.width / original.width, sy = rect.height / original.height;
        const scale = Math.abs(sx - 1) > Math.abs(sy - 1) ? sx : sy;
        result.fontSize = Math.max(8, Math.round(annotation.fontSize * scale));
        const actualScale = result.fontSize / annotation.fontSize;
        if (rect.x !== original.x) result.x1 = rect.x + rect.width - original.width * actualScale;
        if (rect.y !== original.y) result.y1 = rect.y + rect.height - original.height * actualScale;
    } else {
        result.x2 = rect.x + rect.width;
        result.y2 = rect.y + rect.height;
    }
    return result;
}

function move(rect, dx, dy, limit) {
    return {x: Math.max(limit.x, Math.min(rect.x + dx, limit.x + limit.width - rect.width)),
        y: Math.max(limit.y, Math.min(rect.y + dy, limit.y + limit.height - rect.height)),
        width: rect.width, height: rect.height};
}

function moveAnnotation(annotation, dx, dy) {
    const result = Object.assign({}, annotation);
    if (annotation.type === "pen") result.points = annotation.points.map(p => ({x: p.x + dx, y: p.y + dy}));
    else {
        result.x1 += dx;
        result.y1 += dy;
        if (result.x2 !== undefined) result.x2 += dx;
        if (result.y2 !== undefined) result.y2 += dy;
    }
    return result;
}
