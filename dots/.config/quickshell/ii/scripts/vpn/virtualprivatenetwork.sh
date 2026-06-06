#!/usr/bin/env bash

# ENTIRELY baked in Opus 4.8 — use this script on your own risk

vpn() {
    local config_path="/etc/sing-box/config.json"
    local custom_rules_path="/etc/illogical-impulse/sing-box/custom_rules.json"
    local sub_cache_path="/var/cache/illogical-impulse/sing-box/subscription_raw.txt"

    _ok()   { echo "OK:$*"; }
    _err()  { echo "ERR:$*"; }
    _info() { echo "INFO:$*"; }
    _wait() { echo "WAIT:$*"; }
    _needs_subscription() { echo "ERR_NEEDS_SUBSCRIPTION:$*"; }

    _rebuild_config_from_cache() {
        mkdir -p "$(dirname "$custom_rules_path")"
        if [[ ! -r "$sub_cache_path" ]]; then
            _err "Cached subscription not found. Run update-sub once."
            return 1
        fi

        local script_dir parser_file
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
        parser_file="$script_dir/sub_parser.py"

        _wait "Rebuilding config with custom rules..."
        rm -f "$config_path"
        python3 "$parser_file" "$config_path" "$sub_cache_path" "$custom_rules_path" || {
            _err "Failed to rebuild config with custom rules"
            return 1
        }
        chmod 644 "$config_path"
    }

    _require_config_for_runtime() {
        if [[ -r "$config_path" ]]; then
            return 0
        fi
        _needs_subscription "Subscription URL is not configured."
        return 2
    }

    _validate_rule_values() {
        local rule_type="$1"
        shift

        case "$rule_type" in
            domain|domain_suffix|domain_keyword|domain_regex|geoip|geosite|ip_cidr) ;;
            *) _err "Unsupported rule type: ${rule_type}"; return 1 ;;
        esac

        local value url kind
        for value in "$@"; do
            if [[ -z "$value" ]]; then
                _err "Rule value cannot be empty"
                return 1
            fi

            case "$rule_type" in
                domain_regex)
                    python3 - "$value" <<'PY' || { _err "Invalid domain regex: ${value}"; return 1; }
import re
import sys
re.compile(sys.argv[1])
PY
                    ;;
                ip_cidr)
                    python3 - "$value" <<'PY' || { _err "Invalid IP CIDR: ${value}"; return 1; }
import ipaddress
import sys
ipaddress.ip_network(sys.argv[1], strict=False)
PY
                    ;;
                geoip|geosite)
                    if [[ ! "$value" =~ ^[A-Za-z0-9_.-]+$ ]]; then
                        _err "Invalid ${rule_type} name: ${value}"
                        return 1
                    fi
                    kind="$rule_type"
                    if [[ "$kind" == "geoip" ]]; then
                        url="https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-${value,,}.srs"
                    else
                        url="https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-${value,,}.srs"
                    fi
                    if ! curl -fsIL -m 10 -A "Happ/1.0" "$url" >/dev/null; then
                        _err "${rule_type} does not exist or is unavailable: ${value}"
                        return 1
                    fi
                    ;;
            esac
        done
    }

    local tool
    for tool in jq curl python3 awk sing-box systemctl; do
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
        start|restart|check)
            if [[ ! -r "$config_path" ]]; then
                _needs_subscription "Subscription URL is not configured."
                return 2
            fi
            needs_root=1
            ;;
        stop|kill|autostart|update|subscribe|update-sub|delete-sub|unsubscribe|remove-sub|logs|rules) needs_root=1 ;;
        select) [[ -n "$2" ]] && needs_root=1 ;;
    esac

    if [[ $needs_root -eq 1 && $EUID -ne 0 ]]; then
        if ! command -v pkexec &>/dev/null; then
            _err "Can't find dependency: pkexec"
            return 1
        fi
        exec pkexec "${BASH_SOURCE[0]}" "$@"
    fi

    if [[ $EUID -eq 0 ]]; then
        pkexec() { "$@"; }

        local script_path
        script_path=$(realpath "${BASH_SOURCE[0]}")
        local rule_file="/etc/polkit-1/rules.d/50-vpn-virtualprivatenetwork.rules"
        if [[ ! -f "$rule_file" ]] || ! grep -qF "\"${script_path}\"" "$rule_file"; then
            _info "Creating/updating polkit rule for passwordless execution..."
            mkdir -p /etc/polkit-1/rules.d
            cat <<EOF > "$rule_file"
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "${script_path}") {
        return polkit.Result.YES;
    }
});
EOF
            chmod 644 "$rule_file"
            _ok "Polkit rule created/updated at ${rule_file}"
        fi
    fi

    local node_filter='.type == "vless" or .type == "vmess" or .type == "trojan" or .type == "shadowsocks" or .type == "hysteria2" or .type == "hysteria" or .type == "tuic" or .type == "anytls" or .type == "socks" or .type == "http" or .type == "ssh"'

    case "$cmd" in
        start|restart)
            _require_config_for_runtime || return $?
            _wait "${cmd^}ing sing-box"
            pkexec systemctl "$cmd" sing-box && _ok "sing-box ${cmd}ed" || _err "Error ${cmd}ing"
            ;;

        stop|kill)
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
            _require_config_for_runtime || return $?
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
                _needs_subscription "Subscription URL is not configured."
                return 2
            fi
            vpn subscribe "$sub_url"
            ;;

        delete-sub|unsubscribe|remove-sub)
            _wait "Stopping sing-box service..."
            pkexec systemctl stop sing-box >/dev/null 2>&1 || true
            rm -f "$config_path" /etc/sing-box/subscription_url "$sub_cache_path"
            _ok "Subscription deleted and profiles cleared"
            ;;

        subscribe)
            if [[ $# -lt 2 ]]; then
                _err "Usage: vpn subscribe <url> [--ipv4]"
                return 1
            fi

            local sub_url="$2"

            mkdir -p /etc/sing-box "$(dirname "$custom_rules_path")"
            rm -f "$config_path"
            echo -n "$sub_url" | tee /etc/sing-box/subscription_url >/dev/null

            local tmp_file="/tmp/vpn_sub_raw.txt"
            local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
            local parser_file="$script_dir/sub_parser.py"

            _wait "Downloading data..."
            if ! curl -sL -m 15 -A "Happ/1.0" "$sub_url" -o "$tmp_file"; then
                _err "Failed to download subscription."
                return 1
            fi
            mkdir -p "$(dirname "$sub_cache_path")"
            cp "$tmp_file" "$sub_cache_path"
            chmod 644 "$sub_cache_path"

            _wait "Parsing and building modern config..."

            # Launching parser as root: it overwrites config.json.
            pkexec python3 "$parser_file" "$config_path" "$tmp_file" "$custom_rules_path"
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
                _needs_subscription "Subscription URL is not configured."
                return 2
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

        rules)
            local action="${2:-show}"
            mkdir -p /etc/sing-box "$(dirname "$custom_rules_path")"

            case "$action" in
                path)
                    echo "RULES_PATH:${custom_rules_path}"
                    ;;

                show)
                    if [[ -f "$custom_rules_path" ]]; then
                        jq . "$custom_rules_path"
                    else
                        echo '{"rules":[]}'
                    fi
                    ;;

                template)
                    cat <<'EOF'
{
  "hysteria2": {
    "up_mbps": 50,
    "down_mbps": 200
  },
  "rules": [
    {
      "outbound": "proxy",
      "domain_suffix": ["example.com"],
      "geosite": ["youtube"],
      "geoip": ["telegram"]
    },
    {
      "outbound": "direct",
      "domain": ["local.example"],
      "geoip": ["private"]
    }
  ],
  "rule_sets": []
}
EOF
                    ;;

                set)
                    if [[ $# -lt 3 ]]; then
                        _err "Usage: vpn rules set <json-or-file>"
                        return 1
                    fi

                    local input="$3"
                    local tmp_rules="/tmp/vpn_custom_rules.json"
                    if [[ -f "$input" ]]; then
                        jq . "$input" > "$tmp_rules" || { _err "Invalid JSON"; rm -f "$tmp_rules"; return 1; }
                    else
                        jq . <<< "$input" > "$tmp_rules" || { _err "Invalid JSON"; rm -f "$tmp_rules"; return 1; }
                    fi
                    mv "$tmp_rules" "$custom_rules_path"
                    chmod 644 "$custom_rules_path"
                    _ok "Custom rules saved"
                    ;;

                add)
                    if [[ $# -lt 5 ]]; then
                        _err "Usage: vpn rules add <proxy|direct|block|OUTBOUND> <domain|domain_suffix|domain_keyword|domain_regex|geoip|geosite|ip_cidr> <value...>"
                        return 1
                    fi

                    local outbound="$3"
                    local rule_type="$4"
                    shift 4
                    _validate_rule_values "$rule_type" "$@" || return 1
                    local tmp_values="/tmp/vpn_custom_rule_values.json"
                    local tmp_rules="/tmp/vpn_custom_rules.json"
                    printf '%s\n' "$@" | jq -R . | jq -s . > "$tmp_values" || { _err "Failed to encode values"; rm -f "$tmp_values"; return 1; }
                    [[ -f "$custom_rules_path" ]] || echo '{"rules":[]}' > "$custom_rules_path"
                    jq --arg outbound "$outbound" --arg rule_type "$rule_type" --slurpfile values "$tmp_values" '
                        .rules = (.rules // []) |
                        .rules as $rules |
                        if ($outbound == "block" or $outbound == "reject") then
                            ($rules | map((.action // "route") == "reject") | index(true)) as $idx |
                            if $idx == null then
                                .rules += [{"action": "reject", ($rule_type): $values[0]}]
                            else
                                .rules[$idx][$rule_type] = (((.rules[$idx][$rule_type] // []) + $values[0]) | unique)
                            end
                        else
                            ($rules | map(((.action // "route") == "route") and ((.outbound // "proxy") == $outbound)) | index(true)) as $idx |
                            if $idx == null then
                                .rules += [{"outbound": $outbound, ($rule_type): $values[0]}]
                            else
                                .rules[$idx][$rule_type] = (((.rules[$idx][$rule_type] // []) + $values[0]) | unique)
                            end
                        end
                    ' "$custom_rules_path" > "$tmp_rules" || { _err "Failed to add rule"; rm -f "$tmp_values" "$tmp_rules"; return 1; }
                    mv "$tmp_rules" "$custom_rules_path"
                    chmod 644 "$custom_rules_path"
                    rm -f "$tmp_values"
                    _ok "Custom rule added"
                    ;;

                remove|delete)
                    if [[ $# -lt 3 || ! "$3" =~ ^[0-9]+$ ]]; then
                        _err "Usage: vpn rules remove <index> [rule-type value]"
                        return 1
                    fi

                    local idx="$3"
                    local rule_type="${4:-}"
                    local value="${5:-}"
                    local tmp_rules="/tmp/vpn_custom_rules.json"
                    [[ -f "$custom_rules_path" ]] || echo '{"rules":[]}' > "$custom_rules_path"
                    if [[ -n "$rule_type" ]]; then
                        jq --argjson idx "$idx" --arg rule_type "$rule_type" --arg value "$value" '
                            .rules = (.rules // []) |
                            if $idx < 0 or $idx >= (.rules | length) then
                                error("No rule with index " + ($idx | tostring))
                            else
                                .rules[$idx][$rule_type] = ((.rules[$idx][$rule_type] // []) | map(select(. != $value))) |
                                if ((.rules[$idx][$rule_type] // []) | length) == 0 then
                                    del(.rules[$idx][$rule_type])
                                else
                                    .
                                end |
                                if ((.rules[$idx] | keys - ["action", "outbound"]) | length) == 0 then
                                    .rules = (.rules | del(.[$idx]))
                                else
                                    .
                                end
                            end
                        ' "$custom_rules_path" > "$tmp_rules" || { _err "Failed to remove rule"; rm -f "$tmp_rules"; return 1; }
                    else
                        jq --argjson idx "$idx" '
                            .rules = (.rules // []) |
                            if $idx < 0 or $idx >= (.rules | length) then
                                error("No rule with index " + ($idx | tostring))
                            else
                                .rules = (.rules | del(.[$idx]))
                            end
                        ' "$custom_rules_path" > "$tmp_rules" || { _err "Failed to remove rule"; rm -f "$tmp_rules"; return 1; }
                    fi
                    mv "$tmp_rules" "$custom_rules_path"
                    chmod 644 "$custom_rules_path"
                    _ok "Custom rule removed"
                    ;;

                clear)
                    printf '{"rules":[]}' > "$custom_rules_path"
                    chmod 644 "$custom_rules_path"
                    _ok "Custom rules cleared"
                    ;;

                apply)
                    _rebuild_config_from_cache || return 1
                    _wait "Restarting sing-box service..."
                    pkexec systemctl restart sing-box && _ok "Custom rules applied" || _err "Error restarting sing-box"
                    ;;

                *)
                    _err "Usage: vpn rules [show|template|set|add|remove|clear|apply|path]"
                    return 1
                    ;;
            esac
            ;;

        help|-h|--help)
            echo "CMD:subscribe:<url>:download and generate config (Throne-style parsing)"
            echo "CMD:update-sub::update existing subscription"
            echo "CMD:delete-sub::delete saved subscription URL and clear generated profiles"
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
            echo "CMD:rules:[show|template|set|add|remove|clear|apply|path]:manage custom routing rules"
            ;;

        *) _err "Invalid command. Try: vpn help"; return 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    vpn "$@"
fi
