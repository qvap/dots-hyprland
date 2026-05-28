#!/usr/bin/env bash

vpn() {
    local config_path="/etc/sing-box/config.json"
    local profiles_dir="/etc/sing-box/profiles"

    _ok()   { echo "OK:$*"; }
    _err()  { echo "ERR:$*"; }
    _info() { echo "INFO:$*"; }
    _wait() { echo "WAIT:$*"; }

    _active_name() {
        if [[ ! -f "$config_path" || ! -d "$profiles_dir" ]]; then
            echo ""
            return
        fi
        local cfg_sum
        cfg_sum=$(md5sum "$config_path" 2>/dev/null | awk '{print $1}')
        local f name fsum
        for f in "$profiles_dir"/*.json; do
            [[ -f "$f" ]] || continue
            fsum=$(md5sum "$f" 2>/dev/null | awk '{print $1}')
            if [[ "$fsum" == "$cfg_sum" ]]; then
                name=$(basename "$f" .json)
                echo "$name"
                return
            fi
        done
        echo ""
    }

    _apply_profile() {
        local target_file="$1"
        local name
        name=$(basename "$target_file" .json)
        # Use single quotes or pass variables via environment/arguments for safety
        pkexec bash -c 'cp "$1" "$2" && systemctl restart sing-box' _ "$target_file" "$config_path" || { _err "Error applying config"; return 1; }
        _ok "Activated profile: ${name}"
    }

    local tool
    for tool in jq curl base64 python3 find md5sum; do
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
        start|stop|restart|kill|autostart|update|subscribe|update-sub) needs_root=1 ;;
        select) [[ -n "$2" ]] && needs_root=1 ;;
    esac

    if [[ $needs_root -eq 1 && $EUID -ne 0 ]]; then
        exec pkexec "${BASH_SOURCE[0]}" "$@"
    fi

    if [[ $EUID -eq 0 ]]; then
        pkexec() { "$@"; }
    fi

    case "$cmd" in

        start)
            _wait "Starting sing-box"
            pkexec systemctl start sing-box && _ok "sing-box started" || _err "Error starting"
            ;;

        stop)
            _wait "Stopping sing-box"
            pkexec systemctl stop sing-box && _ok "sing-box stopped" || _err "Error stopping"
            ;;

        restart)
            _wait "Restarting sing-box"
            pkexec systemctl restart sing-box && _ok "sing-box restarted" || _err "Error restarting"
            ;;

        kill)
            _wait "Force stopping sing-box"
            pkexec systemctl kill sing-box && _ok "sing-box stopped (kill)" || _err "Error stopping (kill)"
            ;;

        autostart)
            case "$2" in
                on)
                    pkexec systemctl enable sing-box && _ok "Autostart enabled" || _err "Error"
                    ;;
                off)
                    pkexec systemctl disable sing-box && _ok "Autostart disabled" || _err "Error"
                    ;;
                *)
                    _err "Usage: vpn autostart on|off"
                    return 1
                    ;;
            esac
            ;;

        status)
            local state active_name
            state=$(systemctl is-active sing-box 2>/dev/null)
            active_name=$(_active_name)

            if [[ "$state" == "active" ]]; then
                # Check internet connectivity through the VPN proxy
                if ! curl -s -o /dev/null -m 2 http://cp.cloudflare.com/generate_204; then
                    state="connecting"
                fi
            fi

            echo "STATUS:${state}"
            echo "PROFILE:${active_name}"
            ;;

        speedtest)
            if ! command -v speedtest-cli &>/dev/null; then
                echo "ERR_MISSING"
                return 0
            fi
            speedtest-cli --simple 2>/dev/null || echo "ERR_FAILED"
            ;;

        logs)
            if [[ "$2" == "new" || "$2" == "-f" ]]; then
                pkexec journalctl -u sing-box --output cat -f
            else
                pkexec journalctl -u sing-box --output cat -e
            fi
            ;;

        update)
            if [[ $# -lt 2 ]]; then
                _err "Usage: vpn update '<json>'"
                return 1
            fi
            echo "${@:2}" | jq . > /tmp/vpn_config_tmp.json 2>/dev/null
            if [[ $? -ne 0 ]]; then
                _err "Invalid JSON"
                rm -f /tmp/vpn_config_tmp.json
                return 1
            fi
            _wait "Applying config"
            pkexec bash -c "mv /tmp/vpn_config_tmp.json \"$config_path\" && systemctl restart sing-box" \
                && _ok "Config applied and service restarted" \
                || _err "Error writing file"
            ;;

        update-sub)
            local sub_url
            sub_url=$(pkexec cat /etc/sing-box/subscription_url 2>/dev/null)
            if [[ -z "$sub_url" ]]; then
                _err "URL подписки не найден. Сначала выполните 'vpn subscribe <url>' для сохранения."
                return 1
            fi
            # call the function directly
            vpn subscribe "$sub_url"
            ;;

        subscribe)
            if [[ $# -lt 2 ]]; then
                _err "Usage: vpn subscribe <url>"
                return 1
            fi

            local sub_url="$2"
            echo -n "$sub_url" | pkexec tee /etc/sing-box/subscription_url > /dev/null

            local tmp_file="/tmp/vpn_sub_raw.tmp"
            local decoded_file="/tmp/vpn_sub_decoded.tmp"

            _wait "Downloading subscription"
            if ! curl -sL -A "sing-box" -o "$tmp_file" "$sub_url"; then
                _err "Failed to download subscription"
                return 1
            fi

            _wait "Decoding"
            if ! base64 -d "$tmp_file" > "$decoded_file" 2>/dev/null; then
                _err "Data is not in Base64 format"
                rm -f "$tmp_file" "$decoded_file"
                return 1
            fi

            _wait "Parsing profiles"

            python3 - "$config_path" "$decoded_file" <<'PYEOF'
import sys, urllib.parse, json, os, base64, ipaddress

config_path  = sys.argv[1]
decoded_file = sys.argv[2]

def make_template(server_host):
    host_rule = []
    if is_domain(server_host):
        host_rule = [{'domain': [server_host], 'action': 'route', 'server': 'dns-direct'}]

    return {
        'log': {'level': 'info', 'timestamp': True},
        'dns': {
            'servers': [
                {
                    'tag': 'dns-remote',
                    'type': 'https',
                    'server': '1.1.1.1',
                    'path': '/dns-query'
                },
                {
                    'tag': 'dns-direct',
                    'type': 'local'
                }
            ],
            'rules': host_rule,
            'final': 'dns-remote',
            'strategy': 'ipv4_only'
        },
        'inbounds': [
            {
                'type': 'tun',
                'tag': 'tun-in',
                'address': ['172.19.0.1/24', 'fdfe:dcba:9876::1/96'],
                'auto_route': True,
                'auto_redirect': True,
                'strict_route': True,
                'stack': 'system'
            }
        ],
        'outbounds': [
            {'type': 'direct', 'tag': 'direct'}
        ],
        'route': {
            'auto_detect_interface': True,
            'final': 'proxy',
            'default_domain_resolver': {'server': 'dns-direct'},
            'rules': [
                {'action': 'sniff'},
                {'protocol': 'dns', 'action': 'hijack-dns'}
            ]
        }
    }

out_dir = '/tmp/vpn_profiles'
if os.path.exists(out_dir):
    for f in os.listdir(out_dir):
        os.remove(os.path.join(out_dir, f))
else:
    os.makedirs(out_dir, exist_ok=True)

def is_domain(host_str):
    try:
        ipaddress.ip_address(host_str)
        return False
    except ValueError:
        return True

VALID_FP = {'chrome', 'firefox', 'safari', 'edge', '360', 'qq', 'ios'}

def build_tls(sec, sni, fp, pbk='', sid=''):
    tls = {
        'enabled': True,
        'server_name': sni,
        'utls': {'enabled': True, 'fingerprint': fp if fp in VALID_FP else 'chrome'}
    }
    if sec == 'reality':
        tls['reality'] = {'enabled': True, 'public_key': pbk, 'short_id': sid}
    return tls

def build_grpc_transport(service_name):
    return {'type': 'grpc', 'service_name': service_name if service_name else 'grpc'}

def build_ws_transport(path, host):
    t = {'type': 'websocket', 'path': path if path else '/'}
    if host:
        t['headers'] = {'Host': host}
    return t

def build_httpupgrade_transport(path, host):
    t = {'type': 'httpupgrade', 'path': path if path else '/'}
    if host:
        t['host'] = host
    return t

lines = open(decoded_file, 'r').read().splitlines()
count = 0

for line in lines:
    line = line.strip()
    if not line:
        continue
    tag, host, outbound = None, None, None

    # ── VLESS ─────────────────────────────────────────────────────────────
    if line.startswith('vless://'):
        try:
            u = urllib.parse.urlparse(line)
            tag  = urllib.parse.unquote(u.fragment) if u.fragment else u.netloc.split(':')[0]
            uuid, netloc = u.netloc.split('@', 1) if '@' in u.netloc else ('', u.netloc)
            if not uuid:
                continue
            host, port = netloc.split(':', 1) if ':' in netloc else (netloc, 443)
            q = {k.lower(): v for k, v in urllib.parse.parse_qs(u.query).items()}

            outbound = {
                'type': 'vless', 'tag': 'proxy',
                'server': host, 'server_port': int(port),
                'uuid': uuid,
                'packet_encoding': q.get('packetencoding', ['xudp'])[0]
            }

            flow = q.get('flow', [''])[0]
            if flow == 'xtls-rprx-vision':
                outbound['flow'] = flow

            sec = q.get('security', [''])[0].lower()
            if sec in ('reality', 'tls'):
                outbound['tls'] = build_tls(
                    sec,
                    sni=q.get('sni', [''])[0],
                    fp=q.get('fp', ['chrome'])[0],
                    pbk=q.get('pbk', [''])[0],
                    sid=q.get('sid', [''])[0]
                )

            t_type = q.get('type', ['tcp'])[0].lower()
            if t_type == 'grpc':
                s_name = q.get('servicename', q.get('service_name', q.get('path', [''])))[0]
                outbound['transport'] = build_grpc_transport(s_name)
                outbound.pop('flow', None)
                outbound.pop('packet_encoding', None)
            elif t_type == 'ws':
                outbound['transport'] = build_ws_transport(
                    q.get('path', ['/'])[0],
                    q.get('host', q.get('sni', ['']))[0]
                )
            elif t_type == 'httpupgrade':
                outbound['transport'] = build_httpupgrade_transport(
                    q.get('path', ['/'])[0],
                    q.get('host', q.get('sni', ['']))[0]
                )
        except Exception:
            continue

    # ── TROJAN ────────────────────────────────────────────────────────────
    elif line.startswith('trojan://'):
        try:
            u = urllib.parse.urlparse(line)
            tag      = urllib.parse.unquote(u.fragment) if u.fragment else u.netloc.split(':')[0]
            password, netloc = u.netloc.split('@', 1) if '@' in u.netloc else ('', u.netloc)
            if not password:
                continue
            host, port = netloc.split(':', 1) if ':' in netloc else (netloc, 443)
            q = {k.lower(): v for k, v in urllib.parse.parse_qs(u.query).items()}

            outbound = {
                'type': 'trojan', 'tag': 'proxy',
                'server': host, 'server_port': int(port),
                'password': urllib.parse.unquote(password)
            }

            sec = q.get('security', ['tls'])[0].lower()
            if sec in ('reality', 'tls'):
                outbound['tls'] = build_tls(
                    sec,
                    sni=q.get('sni', [''])[0],
                    fp=q.get('fp', ['chrome'])[0],
                    pbk=q.get('pbk', [''])[0],
                    sid=q.get('sid', [''])[0]
                )

            t_type = q.get('type', ['tcp'])[0].lower()
            if t_type == 'grpc':
                s_name = q.get('servicename', q.get('service_name', q.get('path', q.get('host', ['']))))[0]
                outbound['transport'] = build_grpc_transport(s_name)
            elif t_type == 'ws':
                outbound['transport'] = build_ws_transport(
                    q.get('path', ['/'])[0],
                    q.get('host', q.get('sni', ['']))[0]
                )
            elif t_type == 'httpupgrade':
                outbound['transport'] = build_httpupgrade_transport(
                    q.get('path', ['/'])[0],
                    q.get('host', q.get('sni', ['']))[0]
                )
        except Exception:
            continue

    # ── VMESS ─────────────────────────────────────────────────────────────
    elif line.startswith('vmess://'):
        try:
            raw_b64 = line[8:] + '=' * (-(len(line) - 8) % 4)
            data    = json.loads(base64.b64decode(raw_b64).decode('utf-8'))

            tag  = data.get('ps', f'VMess_{count}')
            host = data.get('add', '')
            port = int(data.get('port', 443))
            uuid = data.get('id', '')
            if not uuid:
                continue

            outbound = {
                'type': 'vmess', 'tag': 'proxy',
                'server': host, 'server_port': port,
                'uuid': uuid, 'security': 'auto', 'packet_encoding': 'xudp'
            }

            tls_type = str(data.get('tls', '')).lower()
            if tls_type in ('tls', 'reality'):
                outbound['tls'] = build_tls(
                    tls_type,
                    sni=data.get('sni', ''),
                    fp=data.get('fp', 'chrome'),
                    pbk=data.get('pbk', ''),
                    sid=data.get('sid', '')
                )

            net_type    = str(data.get('net', 'tcp')).lower()
            path        = data.get('path', '')
            host_header = data.get('host', '')

            if net_type == 'grpc':
                outbound['transport'] = build_grpc_transport(path or host_header)
                outbound.pop('packet_encoding', None)
            elif net_type == 'ws':
                outbound['transport'] = build_ws_transport(path, host_header)
            elif net_type == 'httpupgrade':
                outbound['transport'] = build_httpupgrade_transport(path, host_header)
        except Exception:
            continue

    # ── SHADOWSOCKS ───────────────────────────────────────────────────────
    elif line.startswith('ss://'):
        try:
            u   = urllib.parse.urlparse(line)
            tag = urllib.parse.unquote(u.fragment) if u.fragment else u.netloc.split(':')[0]
            if '@' in u.netloc:
                userinfo, netloc = u.netloc.split('@', 1)
                host, port = netloc.split(':', 1) if ':' in netloc else (netloc, 8388)
                try:
                    ui_dec = base64.b64decode(userinfo + '=' * (-len(userinfo) % 4)).decode('utf-8')
                    method, password = ui_dec.split(':', 1) if ':' in ui_dec else (_ for _ in ()).throw(Exception())
                except Exception:
                    if ':' in userinfo:
                        method, password = userinfo.split(':', 1)
                    else:
                        continue
            else:
                decoded  = base64.b64decode(u.netloc + '=' * (-len(u.netloc) % 4)).decode('utf-8')
                userinfo, netloc = decoded.split('@', 1)
                method, password = userinfo.split(':', 1)
                host, port = netloc.split(':', 1) if ':' in netloc else (netloc, 8388)

            outbound = {
                'type': 'shadowsocks', 'tag': 'proxy',
                'server': host, 'server_port': int(port),
                'method': method, 'password': password
            }
        except Exception:
            continue

    # ── HYSTERIA2 ─────────────────────────────────────────────────────────
    elif line.startswith(('hysteria2://', 'hy2://')):
        try:
            u   = urllib.parse.urlparse(line)
            tag = urllib.parse.unquote(u.fragment) if u.fragment else u.netloc.split(':')[0]
            password, netloc = u.netloc.split('@', 1) if '@' in u.netloc else ('', u.netloc)
            if not password:
                continue
            host, port = netloc.split(':', 1) if ':' in netloc else (netloc, 443)
            q = {k.lower(): v for k, v in urllib.parse.parse_qs(u.query).items()}

            outbound = {
                'type': 'hysteria2', 'tag': 'proxy',
                'server': host, 'server_port': int(port),
                'password': urllib.parse.unquote(password),
                'tls': {
                    'enabled': True,
                    'server_name': q.get('sni', [host])[0],
                    'insecure': q.get('insecure', ['0'])[0] in ('1', 'true')
                }
            }
        except Exception:
            continue

    # ── Build profile ────────────────────────────────────────────────────
    if outbound and tag and host:
        fname = tag.replace('/', '_').replace('\\', '_').strip() or f'profile_{count}'
        # Truncate if too long (max 255 bytes for ext4)
        fname = fname.encode('utf-8')[:240].decode('utf-8', 'ignore')
        p_cfg = make_template(host)
        p_cfg['outbounds'] = [outbound] + p_cfg['outbounds']
        with open(f'{out_dir}/{fname}.json', 'w') as f:
            json.dump(p_cfg, f, indent=2, ensure_ascii=False)
        print(f'PROFILE_ITEM:{count + 1}:{tag}')
        count += 1

print(f'PROFILE_COUNT:{count}')
if count == 0:
    sys.exit(1)
PYEOF

            local py_exit=$?
            rm -f "$tmp_file" "$decoded_file"

            if [[ $py_exit -ne 0 ]]; then
                _err "Can't extract profiles from subscription"
                return 1
            fi

            pkexec bash -c "rm -rf \"$profiles_dir\" && mkdir -p \"$profiles_dir\" && cp -r /tmp/vpn_profiles/. \"$profiles_dir/\""
            rm -rf /tmp/vpn_profiles

            _ok "Profiles imported"

            local first_profile
            first_profile=$(find "$profiles_dir" -maxdepth 1 -type f -name "*.json" | sort | head -n 1)
            if [[ -n "$first_profile" ]]; then
                _apply_profile "$first_profile"
            fi
            ;;

        select)
            if [[ ! -d "$profiles_dir" ]]; then
                _err "Profiles not found. First run: vpn subscribe <url>"
                return 1
            fi

            mapfile -t files < <(find "$profiles_dir" -maxdepth 1 -type f -name "*.json" | sort)
            if [[ ${#files[@]} -eq 0 ]]; then
                _err "No available profiles"
                return 1
            fi

            local active_name
            active_name=$(_active_name)

            if [[ -n "$2" ]]; then
                local idx="$2"
                if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#files[@]} )); then
                    _apply_profile "${files[$((idx-1))]}"
                else
                    _err "No profile with number ${idx} (total: ${#files[@]})"
                    return 1
                fi
                return 0
            fi

            local i name
            for i in "${!files[@]}"; do
                name=$(basename "${files[$i]}" .json)
                if [[ "$name" == "$active_name" ]]; then
                    echo "PROFILE_ACTIVE:$((i+1)):${name}"
                else
                    echo "PROFILE_ITEM:$((i+1)):${name}"
                fi
            done
            ;;

        help|-h|--help)
            echo "CMD:subscribe:<url>:download Base64 subscription"
            echo "CMD:update-sub::update existing subscription"
            echo "CMD:select:[N]:select profile (N — immediately, without list)"
            echo "CMD:status::current status and active profile"
            echo "CMD:start::start sing-box"
            echo "CMD:stop::stop sing-box"
            echo "CMD:restart::restart sing-box"
            echo "CMD:kill::force stop"
            echo "CMD:autostart:on|off:automatic start on system load"
            echo "CMD:logs:[new]:logs (new — real-time)"
            echo "CMD:update:<json>:apply config directly"
            ;;

        *)
            _err "Invalid command: ${cmd}. Try: vpn help"
            return 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    vpn "$@"
fi
