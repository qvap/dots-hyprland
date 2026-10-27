.pragma library

function selectPlayer(players, fallback, preference) {
    const preferred = preference.trim().toLowerCase();
    if (!preferred) return fallback;
    return players.find(player => (player.identity ?? "").toLowerCase().includes(preferred)
        || (player.desktopEntry ?? "").toLowerCase().includes(preferred)) ?? fallback;
}

// Keep the popup inside the window for each bar orientation and edge.
function expandedBounds(compact, width, height, windowWidth, windowHeight, vertical, bottom, barWidth, barHeight) {
    const margin = 8;
    const cx = compact.x + compact.width / 2;
    const cy = compact.y + compact.height / 2;
    let x = cx - width / 2;
    let y = cy - height / 2;
    if (vertical)
        x = bottom ? cx - barWidth / 2 - margin - width : cx + barWidth / 2 + margin;
    else
        y = bottom ? cy - barHeight / 2 - margin - height : cy + barHeight / 2 + margin;
    return Qt.rect(Math.max(margin, Math.min(windowWidth - width - margin, x)),
        Math.max(margin, Math.min(windowHeight - height - margin, y)), width, height);
}
