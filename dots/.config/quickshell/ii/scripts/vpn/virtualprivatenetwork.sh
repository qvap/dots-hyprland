#!/usr/bin/env bash

# ENTIRELY baked in Opus 4.8 — use this script on your own risk

vpn() {
    local config_path="/etc/sing-box/config.json"

    _ok()   { echo "OK:$*"; }
    _err()  { echo "ERR:$*"; }
    _info() { echo "INFO:$*"; }
    _wait() { echo "WAIT:$*"; }

    local tool
    for tool in jq curl python3 awk; do
        if ! command -v "$tool" &>/dev/null; then
            _err "Can't find dependency: ${tool}"
            return 1
        fi
    done

    if [[ $# -eq 0 ]]; then
        vpn help
        return 0
    fi

    local cmd="$1"
    local needs_root=0
    case "$cmd" in
        start|stop|restart|kill|autostart|update|subscribe|update-sub|logs|check) needs_root=1 ;;
        select) [[ -n "$2" ]] && needs_root=1 ;;
    esac

    if [[ $needs_root -eq 1 && $EUID -ne 0 ]]; then
        exec pkexec "${BASH_SOURCE[0]}" "$@"
    fi

    if [[ $EUID -eq 0 ]]; then
        pkexec() { "$@"; }
    fi

    local node_filter='.type == "vless" or .type == "vmess" or .type == "trojan" or .type == "shadowsocks" or .type == "hysteria2" or .type == "hysteria" or .type == "tuic" or .type == "anytls" or .type == "socks" or .type == "http" or .type == "ssh"'

    case "$cmd" in
        start|stop|restart|kill)
            _wait "${cmd^}ing sing-box"
            pkexec systemctl "$cmd" sing-box && _ok "sing-box ${cmd}ed" || _err "Error ${cmd}ing"
            ;;

        autostart)
            case "$2" in
                on) pkexec systemctl enable sing-box && _ok "Autostart enabled" || _err "Error" ;;
                off) pkexec systemctl disable sing-box && _ok "Autostart disabled" || _err "Error" ;;
            esac
            ;;

        status)
            local state active_name main_selector
            state=$(systemctl is-active sing-box 2>/dev/null)

            if [[ -r "$config_path" ]]; then
                main_selector=$(jq -r '.outbounds[]? | select(.type == "selector") | .tag' "$config_path" 2>/dev/null | head -n 1)
                if [[ -n "$main_selector" && "$main_selector" != "null" ]]; then
                    active_name=$(jq -r --arg ms "$main_selector" '.outbounds[]? | select(.type == "selector" and .tag == $ms) | .default' "$config_path" 2>/dev/null)
                else
                    active_name=$(jq -r "(.outbounds[]?, .endpoints[]?) | select(${node_filter} or .type == \"wireguard\") | .tag" "$config_path" 2>/dev/null | head -n 1)
                fi

                if [[ "$state" == "active" ]]; then
                    if ! curl -s -o /dev/null --connect-timeout 1 -m 1 http://cp.cloudflare.com/generate_204; then
                        state="connecting"
                    fi
                fi

                echo "STATUS:${state}"
                if [[ -n "$active_name" && "$active_name" != "null" ]]; then
                    echo "PROFILE:${active_name}"
                else
                    echo "PROFILE:None"
                fi
            else
                echo "STATUS:${state}"
                echo "PROFILE:None"
            fi
            ;;

        logs)
            if [[ "$2" == "new" || "$2" == "-f" ]]; then
                pkexec journalctl -u sing-box --output cat -f
            else
                pkexec journalctl -u sing-box --output cat -e
            fi
            ;;

        check)
            _wait "Validating config.json..."
            if pkexec sing-box check -c "$config_path"; then
                _ok "Config is valid!"
            else
                _err "Config has errors! (Check the output above)"
            fi
            ;;

        ping)
            _wait "Checking connection latency..."
            local ping_res
            # Делаем запрос к Cloudflare, выводим полное время выполнения и переводим в миллисекунды через awk
            ping_res=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 5 http://cp.cloudflare.com/generate_204 | awk '{printf "%d", $1 * 1000}')
            if [[ -n "$ping_res" && "$ping_res" != "0" ]]; then
                _ok "${ping_res} ms"
            else
                _err "Timeout / No connection"
            fi
            ;;

        speedtest)
            if ! command -v speedtest-cli &>/dev/null; then
                echo "ERR_MISSING"
                return 0
            fi
            speedtest-cli --simple 2>/dev/null || echo "ERR_FAILED"
            ;;

        update-sub)
            local sub_url
            sub_url=$(pkexec cat /etc/sing-box/subscription_url 2>/dev/null)
            if [[ -z "$sub_url" ]]; then
                _err "URL подписки не найден."
                return 1
            fi
            vpn subscribe "$sub_url"
            ;;

        subscribe)
            if [[ $# -lt 2 ]]; then
                _err "Usage: vpn subscribe <url> [--ipv4]"
                return 1
            fi

            local sub_url="$2"

            mkdir -p /etc/sing-box
            rm -f /etc/sing-box/*.json
            echo -n "$sub_url" | tee /etc/sing-box/subscription_url >/dev/null

            local tmp_file="/tmp/vpn_sub_raw.txt"
            local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
            local parser_file="$script_dir/sub_parser.py"

            _wait "Downloading data..."
            if ! curl -sL -m 15 -A "sing-box" "$sub_url" -o "$tmp_file"; then
                _err "Failed to download subscription."
                return 1
            fi

            _wait "Parsing and building modern config..."

            # Launching parser as root: it overwrites config.json.
            pkexec python3 "$parser_file" "$config_path" "$tmp_file"
            local py_exit=$?

            rm -f "$tmp_file"

            if [[ $py_exit -ne 0 ]]; then
                _err "Failed to parse nodes from subscription."
                return 1
            fi

            pkexec chmod 644 "$config_path"

            _wait "Restarting sing-box service..."
            pkexec systemctl restart sing-box && _ok "Subscription applied successfully!" || _err "Error starting sing-box"
            ;;

        select)
            if [[ ! -r "$config_path" ]]; then
                _err "Config not readable. Run 'vpn update-sub'."
                return 1
            fi

            local main_selector
            main_selector=$(jq -r '.outbounds[]? | select(.type == "selector") | .tag' "$config_path" 2>/dev/null | head -n 1)

            if [[ -z "$main_selector" ]]; then
                _err "No selector group found in config"
                return 1
            fi

            mapfile -t files < <(jq -r --arg ms "$main_selector" '.outbounds[] | select(.type == "selector" and .tag == $ms) | .outbounds[]' "$config_path" 2>/dev/null)

            if [[ ${#files[@]} -eq 0 ]]; then
                _err "No proxy profiles found"
                return 1
            fi

            local active_name
            active_name=$(jq -r --arg ms "$main_selector" '.outbounds[] | select(.type == "selector" and .tag == $ms) | .default' "$config_path" 2>/dev/null)
            [[ -z "$active_name" || "$active_name" == "null" ]] && active_name="${files[0]}"

            if [[ -n "$2" ]]; then
                local idx="$2"
                if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#files[@]} )); then
                    local target_tag
                    target_tag="${files[$((idx-1))]}"
                    _wait "Selecting profile: $target_tag"

                    pkexec bash -c "jq --arg tag \"$target_tag\" --arg ms \"$main_selector\" '( .outbounds[] | select(.type == \"selector\" and .tag == \$ms) | .default ) = \$tag' \"$config_path\" > /tmp/vpn_cfg.json && mv /tmp/vpn_cfg.json \"$config_path\" && chmod 644 \"$config_path\" && systemctl restart sing-box" || { _err "Failed to change profile"; return 1; }

                    _ok "Profile changed to: $target_tag"
                else
                    _err "No profile with number ${idx}"
                    return 1
                fi
                return 0
            fi

            local i name type
            for i in "${!files[@]}"; do
                name="${files[$i]}"
                type=$(jq -r --arg tag "$name" '.outbounds[]? | select(.tag == $tag) | .type' "$config_path" 2>/dev/null | head -n 1)
                [[ -z "$type" || "$type" == "null" ]] && type="unknown"
                if [[ "$name" == "$active_name" ]]; then
                    echo "PROFILE_ACTIVE:$((i+1)):${type}:${name}"
                else
                    echo "PROFILE_ITEM:$((i+1)):${type}:${name}"
                fi
            done
            ;;

        help|-h|--help)
            echo "CMD:subscribe:<url>:download and generate config (Throne-style parsing)"
            echo "CMD:update-sub::update existing subscription"
            echo "CMD:select:[N]:select proxy node"
            echo "CMD:status::current status"
            echo "CMD:start::start sing-box"
            echo "CMD:stop::stop sing-box"
            echo "CMD:restart::restart sing-box"
            echo "CMD:kill::force-kill sing-box"
            echo "CMD:autostart:[on|off]:enable or disable autostart"
            echo "CMD:check::validate config.json for syntax errors"
            echo "CMD:ping::check current connection latency"
            echo "CMD:logs:[new]:logs (new — real-time)"
            echo "CMD:speedtest::run speed test"
            ;;

        *) _err "Invalid command. Try: vpn help"; return 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    vpn "$@"
fi
