#!/usr/bin/env bash

WALLPAPER_CMD="phonto"

get_wallpaper_pid() { pgrep -x "$WALLPAPER_CMD" | head -1; }

pause_wallpaper() {
    local pid; pid=$(get_wallpaper_pid)
    [ -n "$pid" ] && kill -STOP "$pid"
}

resume_wallpaper() {
    local pid; pid=$(get_wallpaper_pid)
    [ -n "$pid" ] && kill -CONT "$pid"
}

is_paused() {
    local pid; pid=$(get_wallpaper_pid)
    [ -z "$pid" ] && return 1
    local state
    state=$(awk '/^State:/ {print $2}' /proc/"$pid"/status 2>/dev/null)
    [ "$state" = "T" ]
}

is_fullscreen() {
    local workspace_info workspace_id window_count has_fullscreen is_floating
    workspace_info=$(hyprctl activeworkspace -j 2>/dev/null)
    workspace_id=$(echo "$workspace_info" | jq '.id')
    window_count=$(echo "$workspace_info" | jq '.windows // 0')

    if [ "$window_count" -eq 1 ]; then
        is_floating=$(hyprctl clients -j 2>/dev/null | \
            jq --argjson wid "$workspace_id" \
            '[.[] | select(.workspace.id == $wid)] | .[0].floating')
        [ "$is_floating" = "true" ] && return 1
    fi

    has_fullscreen=$(hyprctl clients -j 2>/dev/null | \
        jq --argjson wid "$workspace_id" \
        '[.[] | select(.workspace.id == $wid)] | any(.fullscreen > 0)')

    [ "$window_count" -eq 1 ] || [ "$has_fullscreen" = "true" ]
}

check_and_update() {
    [ -z "$(get_wallpaper_pid)" ] && return
    if is_fullscreen; then
        is_paused || pause_wallpaper
    else
        is_paused && resume_wallpaper
    fi
}

handle_event() {
    local event="$1"
    if echo "$event" | grep -qE '^(fullscreen|activewindow|openwindow|closewindow|movewindow|workspace|changefloatingmode)>>'; then
        check_and_update
    fi
}

check_and_update

HYPR_SOCKET="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"

socat -U - "UNIX-CONNECT:${HYPR_SOCKET}" | while read -r line; do
    handle_event "$line"
done
