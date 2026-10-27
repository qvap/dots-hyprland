// Fill free sides clockwise, then add outer rows. Full-screen selections use inner rows.
function positions(selection, width, height, count, size, gap, margin) {
    const result = [];
    const step = size + gap;
    function add(x, y) {
        if (result.length >= count || x < margin || y < margin
            || x + size > width - margin || y + size > height - margin) return;
        if (result.some(p => Math.abs(p.x - x) < step && Math.abs(p.y - y) < step)) return;
        result.push({x: x, y: y});
    }
    const w = Math.max(size, selection.width);
    const h = Math.max(size, selection.height);
    const cx = selection.x + selection.width / 2;
    const cy = selection.y + selection.height / 2;
    for (let ring = 0; ring * step < Math.max(width, height) && result.length < count; ++ring) {
        const left = cx - w / 2 - ring * step;
        const top = cy - h / 2 - ring * step;
        const right = cx + w / 2 + ring * step;
        const bottom = cy + h / 2 + ring * step;
        const cols = Math.max(1, Math.floor((right - left + gap) / step));
        const rows = Math.max(1, Math.floor((bottom - top + gap) / step));
        const startX = cx - (cols * step - gap) / 2;
        const startY = cy - (rows * step - gap) / 2;
        for (let i = 0; i < cols; ++i) add(startX + i * step, bottom + gap);
        for (let i = 0; i < rows; ++i) add(right + gap, startY + i * step);
        for (let i = cols - 1; i >= 0; --i) add(startX + i * step, top - gap - size);
        for (let i = rows - 1; i >= 0; --i) add(left - gap - size, startY + i * step);
    }
    // Outside space is exhausted: keep remaining controls accessible inside the screen.
    for (let y = height - margin - size; y >= margin && result.length < count; y -= step) {
        for (let x = margin; x + size <= width - margin && result.length < count; x += step) add(x, y);
    }
    return result;
}
