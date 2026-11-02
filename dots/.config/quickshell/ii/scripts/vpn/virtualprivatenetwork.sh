#!/usr/bin/env bash
# VPN backend for services/Vpn.qml (sidebar VPN toggle + dialog, vpnDetails.qml):
# sing-box as the system unit `sing-box.service` (runs `sing-box -C
# /etc/sing-box`, i.e. EVERY *.json in that directory is merged — config.json
# must stay the only one). Nodes = the outbounds of the first `selector`
# outbound, the active one = its `default`; subscriptions are parsed by
# sub_parser.py. Nodes sing-box cannot carry (gRPC: Arch's sing-box has only
# the "lite" transport, which Xray servers reject; XHTTP, VLESS Encryption)
# go to Xray (xray.service) behind keyed local shadowsocks-2022 ports
# (xray_split.py); while there are any, xray.service starts / stops / restarts
# with sing-box. Without Xray the XHTTP / Encryption nodes are dropped (a
# SKIPPED:tag<TAB>why line each).
# The configs hold the nodes' secrets: root:<unit user> 0640. What the shell
# needs (nodes, types, the active one, whether Xray is in use, the applied
# routing) is written next to them, secret-free, to
# /etc/illogical-impulse/vpn/view.json (0644).
# config.json = compose(base, routing, overlay) (routing.py): base = the
# subscription's config (sub_parser + xray_split,
# /etc/illogical-impulse/vpn/base.json, root 0600), routing =
# Config.options.vpn.routing (direct / proxy / block rules by domain, IP,
# process, protocol, geosite / geoip; FakeIP, remote DNS, Hysteria2 speeds),
# overlay = the user's own sing-box JSON
# (~/.config/illogical-impulse/vpn/custom.json), applied last. Root keeps
# copies of the applied routing / overlay and the geosite / geoip rule-sets
# (/etc/illogical-impulse/vpn/{routing,custom}.json, rules/), so a
# subscription update or a node switch recomposes the same way.
# Privileges: user halves run as the user (downloads, the overlay); root
# halves (`_*`) via pkexec, which asks for the password. start / stop go
# through systemd's polkit check (no prompt once `setup` installed its rule).
# Deliberately NOT "pkexec this script without a password" (the old setup):
# the script lives in a user-writable directory, so that rule handed root to
# any program of the user. Every root half removes it.
#
#   state              one JSON line: { installed, unit (systemctl
#                      is-active), enabled (autostart), online (a probe
#                      through it answered), profile, profiles: [{ tag,
#                      type (shown), base, xray, insecure }], subscription,
#                      killswitch (on), blocking (its table is up while
#                      sing-box is not), restarting (a root half is
#                      restarting the units itself: unit / blocking are in
#                      flux), routing (the applied one), customPending (the
#                      overlay differs from the applied one), passwordless
#                      (`setup` is done and its copy of these scripts is
#                      current) }
#   start | stop | restart
#                      systemctl start / stop / restart sing-box (+ xray)
#   enable | disable   autostart at boot (systemctl enable / disable;
#                      polkit always asks — unit files are not in the rule)
#   killswitch on|off  (root) the kill switch: while it is on, starting
#                      sing-box also raises ii-vpn-killswitch.service (a
#                      drop-in `Wants=`), an nftables table that rejects all
#                      outgoing traffic except loopback, the TUN, sing-box's
#                      / Xray's own (by uid) and the LAN (DNS excepted). It
#                      outlives a crashed sing-box: only `stop` takes it down
#   select <tag>       (root) make <tag> the selector default, restart the
#                      unit if it runs
#   subscribe [url]    (url: the argument, or $II_VPN_URL — the shell's way:
#                      argv is world-readable in /proc, the environment is
#                      not) download it as the user, then (root) parse +
#                      check + install, restart the unit if it runs; once
#                      applied, remember the URL (user state, 0600; a failed
#                      one keeps the old)
#   update             subscribe again with the remembered URL
#                      Both also read what the provider says besides the
#                      nodes (sub_meta.py: response headers, body `#key:`
#                      lines, its routing profile — downloaded too if it is
#                      a URL) into $provider_file (user state, 0600: title,
#                      traffic, expiry, banners, update interval...); its
#                      routing part goes in force with the nodes, as the
#                      routing's "provider" key (routing.py). $II_VPN_HWID=1:
#                      send a device id (x-hwid, ...) for providers that
#                      limit devices. A `new-url` / `new-domain` the provider
#                      sends is what gets remembered.
#   check              (user only, no root) download the subscription again
#                      and refresh $provider_file: "OK:changed" (the nodes
#                      differ from the applied ones: `update` applies them)
#                      or "OK:same"
#   unsubscribe        (root) stop the VPN, remove the URL, the configs and
#                      the node list
#   apply [json] [refresh]
#                      routing (json = Config.options.vpn.routing; without
#                      it the last one) + the overlay: validate, download the
#                      geosite / geoip rule-sets it needs (as the user; older
#                      than a day or `refresh` = again), then (root) compose,
#                      check, install, restart; a config sing-box cannot start
#                      with is rolled back
#   edit               the overlay in $VISUAL / $EDITOR (a skeleton first)
#   migrate            the old setup's state as one JSON line { routing,
#                      overlay } (routing.py migrate of the old custom rules,
#                      {} without them); its subscription URL moves to the
#                      user state
#   ping               latency of an HTTP probe: "OK:<ms>" / "ERR:"
#   speedtest          speedtest-cli --simple (ERR_MISSING without it)
#   setup              (root, once; again after editing these scripts) a
#                      root-owned copy of them in /usr/local/lib/ii-vpn and a
#                      polkit rule: the active local session of the calling
#                      user may, without a password, start / stop / restart
#                      sing-box.service, xray.service and the kill switch
#                      unit, and pkexec THE COPY for a node switch (_select)
#                      and a routing-only apply (_reroute) — never this
#                      user-writable script, never an overlay change or a
#                      subscription (those can make sing-box, which may read
#                      any file, serve or route anything).
# Errors: "ERR:<message>" and exit 1; a missing tool = "ERR:Can't find
# dependency: <name>".
#
# Root halves run from the copy while it matches these files (else from
# here, which polkit always asks for). What a password-free caller passes
# them is untrusted: routing as a JSON string (a path could name a
# root-only file), rule-set files read without following symlinks and only
# if the caller (PKEXEC_UID) owns them (routing.py install-rules).
set -u

config=/etc/sing-box/config.json
unit=sing-box
xray_config=/etc/xray/config.json
etc=/etc/illogical-impulse/vpn
view=$etc/view.json
probe=http://cp.cloudflare.com/generate_204
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/vpn
sub_file=$state_dir/subscription
routing_file=$state_dir/routing.json
provider_file=$state_dir/provider.json
sub_hash=$state_dir/subscription.sha256
custom_file=${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/vpn/custom.json
rules_cache=${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/vpn/rules
base=$etc/base.json
routing_etc=$etc/routing.json
custom_etc=$etc/custom.json
rules_etc=$etc/rules
rule=/etc/polkit-1/rules.d/50-ii-vpn.rules
sys_dir=/usr/local/lib/ii-vpn
sys_files=(virtualprivatenetwork.sh routing.py sub_parser.py xray_split.py)
ks_unit=ii-vpn-killswitch
ks_unit_file=/etc/systemd/system/$ks_unit.service
ks_dropin=/etc/systemd/system/$unit.service.d/ii-vpn-killswitch.conf
ks_rules=$etc/killswitch.nft
ks_table="inet ii_vpn_killswitch"
# sub_parser.py names the TUN this; the kill switch lets it through.
tun_name=ii-tun
# The old setup (a passwordless pkexec rule for this script, root-written
# files): removed / migrated.
old_rule=/etc/polkit-1/rules.d/50-vpn-virtualprivatenetwork.rules
old_sub_url=/etc/sing-box/subscription_url
old_sub_cache=/var/cache/illogical-impulse/sing-box/subscription_raw.txt
old_rules=/etc/illogical-impulse/sing-box/custom_rules.json
self=$(realpath "$0")
here=$(dirname "$self")

# Root halves hold a lock on $ops_lock (lock_ops) and name themselves in
# $restart_mark: `state` reports restarting while that process lives (the
# panel holds the unit / kill switch it shows meanwhile).
ops_lock=/run/ii-vpn/lock
restart_mark=/run/ii-vpn/restarting
unchecked=""
# Xray ran before restart_checked touched it (roll_back runs it again).
xray_ran=""

err() {
    echo "ERR:$*"
    exit 1
}

# HACK (systemd 262: `systemctl start|stop a b` sends EnqueueUnitJobMany,
# which its D-Bus policy does not let a user call — denied before polkit is
# asked). One call per unit, in the order given. Undo (one call again) when
# org.freedesktop.systemd1.conf allows EnqueueUnitJobMany.
units_do() {
    local verb=$1 u
    shift
    for u in "$@"; do
        systemctl "$verb" "$u" || return 1
    done
}

# The script pkexec runs: the root-owned copy while it is this one's (the
# password-free rule covers only it), else this one (polkit asks).
root_self() {
    local f
    for f in "${sys_files[@]}"; do
        cmp -s "$here/$f" "$sys_dir/$f" || { echo "$self"; return; }
    done
    echo "$sys_dir/virtualprivatenetwork.sh"
}

# Xray carries some nodes (and is installed): it runs alongside sing-box.
uses_xray() {
    command -v xray >/dev/null || return 1
    jq -e '.xray == true' "$view" >/dev/null 2>&1
}

# Root: the unit's user / group (Arch runs sing-box as `sing-box`; root where
# the unit has no User=).
unit_user() {
    local u
    u=$(systemctl show -p User --value "$unit" 2>/dev/null)
    echo "${u:-root}"
}
unit_group() {
    getent group "$(unit_user)" >/dev/null && unit_user || echo root
}

# Root: every root half starts here; the old passwordless rule goes.
root_only() {
    [ "$(id -u)" -eq 0 ] || err "root only"
    rm -f "$old_rule"
}

# The tools a command needs ("ERR:Can't find dependency: <name>").
need() {
    local t
    for t in "$@"; do
        command -v "$t" >/dev/null || err "Can't find dependency: $t"
    done
}

# sha256 of a file, "" when missing.
hash_of() {
    [ -f "$1" ] && sha256sum <"$1" | cut -c1-64
}

# The panel's view of $config: { profile, profiles: [{ tag, type (shown),
# base, xray, insecure }], xray, routing, customHash }. $1 = nodes moved to
# Xray ("tag<TAB>type<TAB>flags" lines; empty file / none = none).
view_of() {
    local xn='{}' r='{}'
    [ -s "${1:-}" ] && xn=$(jq -Rn '[inputs | split("\t") | select(length >= 2)
        | { key: .[0], value: { base: .[1], insecure: ((.[2] // "") | contains("insecure")) } }] | from_entries' "$1")
    [ -s "$routing_etc" ] && r=$(jq -c . "$routing_etc" 2>/dev/null || echo '{}')
    jq -c --arg ms "$(selector)" --argjson xn "$xn" --argjson r "$r" --arg ch "$(hash_of "$custom_etc")" '
        . as $c
        | ([$c.outbounds[]?, $c.endpoints[]?] | map(select(.tag | type == "string") | { key: .tag, value: .type }) | from_entries) as $types
        | ([$c.outbounds[]? | select(.type == "selector" and .tag == $ms)][0]) as $sel
        | def node($t): ($xn[$t]) as $x
            | if $x then { tag: $t, base: $x.base, xray: true, insecure: $x.insecure,
                           type: ($x.base + " · xray" + (if $x.insecure then " · ⚠ cert checked" else "" end)) }
              else { tag: $t, base: ($types[$t] // ""), xray: false, insecure: false, type: ($types[$t] // "") } end;
        {
            profile: (if $sel then ($sel.default // $sel.outbounds[0] // "") else "" end),
            profiles: (if $sel then [$sel.outbounds[]? | node(.)] else [] end),
            xray: ($xn != {}),
            routing: $r,
            customHash: $ch
        }' "$config"
}

# Root: compose $config's content from base $1 (routing $2, overlay $3) into
# $4, then `sing-box check` it. Prints ERR: and fails on either.
compose() {
    local out
    out=$(python3 -I "$here/routing.py" compose "$1" "$2" "$3" "$rules_etc" "$4") || { echo "$out"; return 1; }
    out=$(sing-box check -c "$4" 2>&1) ||
        { echo "ERR:sing-box: $(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g' | tail -n 1)"; return 1; }
}

# Root: the rule-sets routing $1 needs, from the calling user's download
# dir $2 (owned by them, no symlinks: routing.py install-rules) to
# $rules_etc. Ones no longer needed stay until prune_rules (a rollback may
# need them).
install_rules() {
    python3 -I "$here/routing.py" install-rules "$1" "${2:-}" "$rules_etc" "${PKEXEC_UID:--1}"
}

# Root: drop the rule-sets routing $1 does not need (the new config is up).
prune_rules() {
    python3 -I "$here/routing.py" prune-rules "$1" "$rules_etc"
}

# Root: restart the running unit on the just-installed $config and make sure
# it stays up: what `check` cannot see fails only at start. $1 = Xray with
# it: "on" (restart on the new $xray_config), "off" (stop), "" (untouched).
# If it does not come up, roll_back (the view still describes the .bak
# copies: it is written only after this). A unit that is not
# running (stopped, failed, crash-looping: maybe not the config's fault,
# e.g. another VPN holds the routes) is not started here: $unchecked is set,
# the change is in place for the next start, unverified (an UNCHECKED line
# tells the panel). A running Xray still follows its new config.
restart_checked() {
    local xr=${1:-} xu=""
    [ "$xr" = on ] && xu=xray
    if ! systemctl is-active -q "$unit"; then
        case $xr in
        on)
            # A running (or starting) Xray is checked on its new config: if
            # it does not stay up, the configs go back (the sing-box one
            # names its ports / keys).
            case $(systemctl is-active xray 2>/dev/null) in
            inactive | failed) ;;
            *)
                xray_ran=1
                systemctl restart xray
                stays_up xray || roll_back xray on
                ;;
            esac
            ;;
        off) systemctl stop xray ;;
        esac
        unchecked=1
        echo "UNCHECKED:sing-box is not running: applies on its next start"
        return 0
    fi
    systemctl is-active -q xray && xray_ran=1
    case $xr in
    on) systemctl restart xray ;;
    off) systemctl stop xray ;;
    esac
    # shellcheck disable=SC2086 # $xu: none or one word
    systemctl restart "$unit" && stays_up "$unit" $xu && return 0
    roll_back "$unit" "$xr"
}

# Root: $1 (sing-box or xray) did not come up on the new configs ($2 = Xray
# as for restart_checked). The .bak copies go back ($base's too with
# $with_base), what ran before runs again and is checked the same way, and
# this fails, saying how that went. A config without a .bak (none before)
# is not run again: sing-box is stopped instead of left failing.
roll_back() {
    local what=$1 xr=${2:-} name=sing-box why restored="" xrestored="" up=()
    [ "$what" = xray ] && name=Xray
    why=$(journalctl -u "$what" ${xr:+-u xray} -n 20 -o cat --since "-10s" 2>/dev/null | grep -iE 'fatal|error' |
        tail -n 1 | sed 's/\x1b\[[0-9;]*m//g')
    if [ -f "$config.bak" ]; then
        install -m 640 -g "$(unit_group)" "$config.bak" "$config"
        restored=1
    fi
    [ -n "${with_base:-}" ] && [ -f "$base.bak" ] && install -m 600 "$base.bak" "$base"
    if [ "$xr" = on ] && [ -f "$xray_config.bak" ]; then
        install -m 640 -g xray "$xray_config.bak" "$xray_config"
        xrestored=1
    fi
    if [ "$what" = "$unit" ] && [ -z "$restored" ]; then
        [ -n "$xr" ] && systemctl stop xray
        systemctl stop "$unit"
        err "sing-box did not start with it (no previous config to restore)${why:+: $why}$(ks_note)"
    fi
    # Xray, if this touched it: on its old config if the old setup uses it
    # or it ran before, else stopped.
    if [ -n "$xr" ]; then
        if { uses_xray || [ -n "$xray_ran" ]; } && { [ "$xr" = off ] || [ -n "$xrestored" ]; }; then
            systemctl restart xray
            up+=(xray)
        else
            systemctl stop xray
        fi
    fi
    if [ "$what" = "$unit" ]; then
        systemctl restart "$unit"
        up=("$unit" "${up[@]}")
    fi
    [ ${#up[@]} -gt 0 ] && ! stays_up "${up[@]}" &&
        err "$name did not start with it, nor with the previous config${why:+: $why}$(ks_note)"
    [ "$what" = xray ] && [ -z "$xrestored" ] &&
        err "Xray did not start with it (no previous config to restore: stopped)${why:+: $why}"
    # Xray left alone (not this change's) may be down all the same.
    [ -z "$xr" ] && uses_xray && [ "$(xray_state)" = down ] &&
        err "$name did not start with it, previous config restored (but Xray is down or restarting after a crash: its nodes do not work now)${why:+: $why}"
    err "$name did not start with it, previous config restored${why:+: $why}"
}

# Root: the units $@ come up and stay up for a second; any failed / stopped
# one ends the wait early, ~6 s at most.
stays_up() {
    local i u s n=0
    for i in $(seq 30); do
        sleep 0.2
        s=active
        for u in "$@"; do
            case $(systemctl is-active "$u" 2>/dev/null) in
            active) ;;
            failed | inactive) return 1 ;;
            *) s=starting ;;
            esac
        done
        if [ "$s" = active ]; then
            n=$((n + 1))
            [ $n -ge 5 ] && return 0
        else
            n=0
        fi
    done
    return 1
}

# Start time of process $1 (field 22 of its stat, after the "(comm)" that
# may hold spaces); fails when there is no such process. PID + start time
# name one process: a reused PID has another.
proc_start() {
    local s
    { s=$(<"/proc/$1/stat"); } 2>/dev/null || return 1
    # shellcheck disable=SC2086 # split into the fields
    set -- ${s##*) }
    echo "${20}"
}

# Root halves that change configs run one at a time: an exclusive lock on
# $ops_lock, taken before their .bak copies (a second one would overwrite
# the first's rollback). Root-only (0600 from its creation): a lock needs
# only an open fd, and a world-readable file let any user hold it forever,
# stalling every operation and the panel's status. The kernel drops it
# with the holder, however it ends. The holder then writes "PID start" to
# $restart_mark (0644, root's directory: nobody else can fake it) for
# `state`; a dead holder's mark is stale by itself.
lock_ops() {
    local d um m
    d=$(dirname "$ops_lock")
    mkdir -p -m 755 "$d" || err "cannot create $d"
    um=$(umask)
    umask 077
    exec 9>>"$ops_lock"
    m=$?
    umask "$um"
    [ $m -eq 0 ] && chmod 600 "$ops_lock" || err "cannot open $ops_lock"
    flock -w 30 9 || err "another VPN operation is still running"
    m=$(mktemp "$restart_mark.XXXXXX") &&
        printf '%s %s\n' "$$" "$(proc_start $$)" >"$m" && chmod 644 "$m" && mv -f "$m" "$restart_mark" ||
        { rm -f "$m"; err "cannot write $restart_mark"; }
}

# Xray: up | starting | down (failed, stopped, or waiting out Restart= after
# a crash, which is "activating" too: auto-restart, auto-restart-queued in
# systemd 254+).
xray_state() {
    case $(systemctl is-active xray 2>/dev/null) in
    active) echo up ;;
    activating | reloading)
        case $(systemctl show -P SubState xray 2>/dev/null) in
        auto-restart*) echo down ;;
        *) echo starting ;;
        esac
        ;;
    *) echo down ;;
    esac
}

# Root: a note for an error that leaves sing-box down while the kill switch
# holds traffic.
ks_note() {
    systemctl is-active -q "$ks_unit" && echo "; the kill switch blocks traffic until VPN stop"
}

# User: download the rule-sets routing $1 needs to $rules_cache (each from
# the first source that has it); ones younger than a day are kept unless $2.
fetch_rules() {
    local list line f u got
    list=$(python3 -I "$here/routing.py" rulesets "$1") || err "${list#ERR:}"
    [ -n "$list" ] || return 0
    mkdir -p "$rules_cache"
    while IFS= read -r line; do
        IFS=$'\t' read -r -a parts <<<"$line"
        f=${parts[0]}
        # "?": only provider rules want it, and compose skips it if missing.
        optional=""
        [ "${f:0:1}" = "?" ] && optional=1 && f=${f:1}
        [ -z "${2:-}" ] && [ -n "$(find "$rules_cache/$f" -mmin -1440 2>/dev/null)" ] && continue
        got=""
        for u in "${parts[@]:1}"; do
            if curl -4 -sfL --connect-timeout 10 -m 120 "$u" -o "$rules_cache/$f.part" &&
                [ "$(head -c3 "$rules_cache/$f.part")" = SRS ]; then
                mv "$rules_cache/$f.part" "$rules_cache/$f"
                got=1
                break
            fi
        done
        rm -f "$rules_cache/$f.part"
        # A stale copy beats none (GitHub unreachable right now): ours, or
        # root's installed one (install_rules keeps it when we have none).
        [ -n "$got" ] || [ -s "$rules_cache/$f" ] || [ -s "$rules_etc/$f" ] || [ -n "$optional" ] ||
            err "cannot download ${f%.srs}"
    done <<<"$list"
}

# Root: rewrite the view from $config. $1 = the Xray node list of a fresh
# apply; without one the current view's is kept (a node switch).
write_view() {
    local nodes=${1:-} own="" tmp
    if [ -z "$nodes" ] && [ -r "$view" ]; then
        own=$(mktemp) || return 1
        # (A view from before base / xray existed: parse the shown type.)
        jq -r '.profiles[] | select(.xray // (.type | endswith(" · xray")))
            | "\(.tag)\t\(.base // (.type | rtrimstr(" · xray")))\t\(if .insecure then "insecure" else "" end)"' "$view" >"$own"
        nodes=$own
    fi
    tmp=$(mktemp) || return 1
    local ok=0
    view_of "$nodes" >"$tmp" && mkdir -p "$(dirname "$view")" && install -m 644 "$tmp" "$view" || ok=1
    rm -f "$tmp" $own
    return $ok
}

# Root: the polkit rule for user $1 (see `setup`).
write_rule() {
    mkdir -p "$(dirname "$rule")"
    cat >"$rule" <<EOF
// illogical-impulse VPN (virtualprivatenetwork.sh setup): ${1} may, from
// the active local session and without a password, start / stop
// ${unit}.service, xray.service and ${ks_unit}.service, and run the
// root-owned ${sys_dir}/virtualprivatenetwork.sh for a node switch (_select)
// or a routing-only apply (_reroute; the overlay stays root's applied copy).
polkit.addRule(function (action, subject) {
    if (subject.user != "${1}" || !subject.local || !subject.active)
        return polkit.Result.NOT_HANDLED;
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        ["${unit}.service", "xray.service", "${ks_unit}.service"].indexOf(action.lookup("unit")) >= 0 &&
        ["start", "stop", "restart", "try-restart"].indexOf(action.lookup("verb")) >= 0)
        return polkit.Result.YES;
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "${sys_dir}/virtualprivatenetwork.sh" &&
        /^\S+ (_select|_reroute) /.test(action.lookup("command_line") || ""))
        return polkit.Result.YES;
    return polkit.Result.NOT_HANDLED;
});
EOF
    chmod 644 "$rule"
}

# Root: the kill switch's ruleset — output only (this host's own traffic).
# The VPN's own paths first, then the LAN minus DNS (the router would
# forward the names to the ISP), then reject (fails fast instead of hanging).
# `ct status dnat`: sing-box's auto_redirect sends TCP to its local port in
# the nat output hook, and the filter hook still sees the pre-NAT interface.
# Into $1 (install_ks_rules puts it in place).
write_ks_rules() {
    local uids out=$1
    # (A sing-box running as root lets root's traffic through as well.)
    uids=$(id -u "$(unit_user)") || return 1
    id -u xray >/dev/null 2>&1 && uids="$uids, $(id -u xray)"
    cat >"$out" <<EOF
# illogical-impulse VPN kill switch (virtualprivatenetwork.sh), loaded by ${ks_unit}.service.
table ${ks_table}
delete table ${ks_table}
table ${ks_table} {
    chain output {
        type filter hook output priority filter; policy accept;
        oifname "lo" accept
        oifname "${tun_name}" accept
        meta skuid { ${uids} } accept
        ct status dnat accept
        meta l4proto { tcp, udp } th dport { 53, 853 } reject
        ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4, 255.255.255.255 } accept
        ip6 daddr { fe80::/10, ff00::/8 } accept
        meta l4proto tcp reject with tcp reset
        reject with icmpx admin-prohibited
    }
}
EOF
    chmod 644 "$out"
}

ks_on() { [ -e "$ks_dropin" ]; }

# Root: while the kill switch is on, rewrite its table (the uids it lets
# through: Xray may have been installed since it was turned on) and reload
# it if it is up (the file deletes the old table first).
refresh_ks() {
    ks_on || return 0
    install_ks_rules || return 1
    if systemctl is-active -q "$ks_unit"; then nft -f "$ks_rules"; fi
}

# Root: write the kill switch's table to $ks_rules only once `nft -c` takes
# it: the unit loads that file, a broken one would leave the VPN unguarded.
install_ks_rules() {
    local tmp rc
    tmp=$(mktemp) || return 1
    write_ks_rules "$tmp" && nft -c -f "$tmp" && install -D -m 644 "$tmp" "$ks_rules"
    rc=$?
    rm -f "$tmp"
    return $rc
}

# Root: name the TUN of config file $1 $tun_name if it is not yet (one from
# before the TUN had a fixed name): the kill switch lets only that interface
# through. The rest = `install` args for it. 0 = renamed, 1 = nothing to
# do (named already, or no such file), 2 = the rename failed.
name_tun() {
    local f=$1 tmp rc
    shift
    [ -r "$f" ] || return 1
    jq -e --arg n "$tun_name" '[.inbounds[]? | select(.type == "tun")] | all(.interface_name == $n)' "$f" >/dev/null &&
        return 1
    tmp=$(mktemp) || return 2
    jq --arg n "$tun_name" '(.inbounds[]? | select(.type == "tun") | .interface_name) = $n' "$f" >"$tmp" &&
        sing-box check -c "$tmp" && install "$@" "$tmp" "$f"
    rc=$?
    rm -f "$tmp"
    [ $rc -eq 0 ] || return 2
}

# Root: keep a copy of $1 as $1.bak for a rollback (0600: the same secrets);
# none (no $1) = no stale .bak either.
backup() {
    if [ -f "$1" ]; then install -m 600 "$1" "$1.bak"; else rm -f "$1.bak"; fi
}

# Tag of the first selector outbound (empty = none).
selector() {
    jq -r '[.outbounds[]? | select(.type == "selector") | .tag][0] // empty' "$config" 2>/dev/null
}

# A device id for providers that limit devices (x-hwid): stable per machine,
# not the machine id itself. UUID form, upper case.
hwid() {
    local h
    h=$({ cat /etc/machine-id 2>/dev/null || hostname; } | sed 's/^/ii-vpn-hwid|/' | sha256sum | cut -c1-32)
    h=${h^^}
    echo "${h:0:8}-${h:8:4}-${h:12:4}-${h:16:4}-${h:20:12}"
}

# A value for a curl config line: printable ASCII, no quotes / backslashes.
curl_safe() {
    printf '%s' "$1" | tr -cd 'A-Za-z0-9 ._()/:+-' | cut -c1-80
}

# User: download $url to $raw, its response headers to $hdr. The URL
# carries the provider's access token, and any local user can read a
# process's argv (/proc/<pid>/cmdline): it reaches curl as a config on
# stdin (printf is a builtin), never as an argument.
download_sub() {
    case "$url" in
    http://* | https://*) ;;
    *) err "not an http(s) URL" ;;
    esac
    case "$url" in
    *[[:space:][:cntrl:]]*) err "the URL has spaces or control characters" ;;
    esac
    local esc=${url//\\/\\\\} extra="" ver model
    esc=${esc//\"/\\\"}
    if [ "${II_VPN_HWID:-}" = 1 ]; then
        ver=$( (. /etc/os-release 2>/dev/null && echo "${VERSION_ID:-${BUILD_ID:-}}") )
        model=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
        extra=$(printf 'header = "x-hwid: %s"\nheader = "x-device-os: Linux"\nheader = "x-ver-os: %s"\nheader = "x-device-model: %s"\n' \
            "$(hwid)" "$(curl_safe "${ver:-$(uname -r)}")" "$(curl_safe "${model:-PC}")")
    fi
    # Happ's user agent: panels answer it with the Xray JSON / share links
    # sub_parser.py reads best, and with the headers sub_meta.py reads.
    printf 'url = "%s"\n%s\n' "$esc" "$extra" |
        curl -4 -sfL -m 20 --max-filesize 16M -A "Happ/1.0" -K - -D "$hdr" -o "$raw" ||
        err "Failed to download subscription"
    [ -s "$raw" ] || err "empty subscription"
}

# User: what the provider says ($hdr + $raw, its routing profile if that is a
# URL) to $meta (sub_meta.py meta). A profile that cannot be had is no
# error: the nodes still work, its rules come with a later update.
provider_meta() {
    local purl
    prof=$(mktemp) || err "mktemp"
    purl=$(python3 -I "$here/sub_meta.py" routing-url "$hdr" "$raw")
    if [ -n "$purl" ] && [[ $purl != *[[:space:][:cntrl:]\"\\]* ]]; then
        printf 'url = "%s"\n' "$purl" | curl -4 -sfL -m 20 --max-filesize 2M -A "Happ/1.0" -K - -o "$prof" || : >"$prof"
    fi
    python3 -I "$here/sub_meta.py" meta "$hdr" "$raw" "$prof" >"$meta" || echo '{}' >"$meta"
    rm -f "$prof"
}

# User: $1 into $provider_file (0600: support links, traffic: the user's).
save_provider() {
    mkdir -p "$state_dir"
    (umask 077 && cat "$1" >"$provider_file.new" && mv -f "$provider_file.new" "$provider_file")
}

# subscribe / update: download $url as the user, apply it with the
# provider's routing (root), then remember both.
subscribe_url() {
    raw=$(mktemp) && hdr=$(mktemp) && meta=$(mktemp) && rtmp=$(mktemp) || err "mktemp"
    trap 'rm -f "$raw" "$hdr" "$meta" "$rtmp"' EXIT
    download_sub
    provider_meta
    # The routing in force + the provider's new part.
    mkdir -p "$state_dir"
    [ -s "$routing_file" ] || echo '{}' >"$routing_file"
    jq -c --slurpfile m "$meta" '. + { provider: ($m[0].routing // {}) }' "$routing_file" >"$rtmp" ||
        err "bad routing state in $routing_file"
    fetch_rules "$rtmp"
    # pkexec's status as is (the panel tells 126 / 127 apart).
    pkexec "$(root_self)" _apply "$raw" "$rules_cache" "$(cat "$rtmp")" || exit
    # Remembered only once applied: a mistyped / dead URL, a rejected
    # subscription or a dismissed prompt keeps the working one for `update`.
    cat "$rtmp" >"$routing_file"
    save_provider "$meta" || err "applied, but cannot save the provider's info"
    hash_of "$raw" >"$sub_hash"
    # The provider moved: its new URL (or the old one on its new host).
    local new
    new=$(jq -r '.newUrl // ""' "$meta")
    if [ "${new:0:1}" = "@" ]; then
        new=$(printf '%s' "$url" | sed -E "s#^(https?://)([^/@]*@)?[^/:]+#\\1\\2${new:1}#")
    fi
    case "$new" in
    https://* | http://*) [[ $new == *[[:space:][:cntrl:]]* ]] || url=$new ;;
    esac
    (umask 077 && printf '%s' "$url" >"$sub_file.new" && mv -f "$sub_file.new" "$sub_file") ||
        err "applied, but cannot save the subscription URL"
}

# These go through pkexec: without it its exec fails with 127, which the
# panel would show as "not authorized".
case "${1:-}" in
killswitch | select | subscribe | update | apply)
    command -v pkexec >/dev/null || err "pkexec (polkit) is not installed"
    ;;
esac

case "${1:-}" in
state | ping | speedtest | edit | migrate | "" | help | -h | --help) ;;
check) need jq curl python3 ;;
*) need jq curl python3 sing-box systemctl ;;
esac

case "${1:-}" in
state)
    installed=false
    command -v sing-box >/dev/null && installed=true
    # Before and after the units are read: a restart that starts or ends
    # in between still counts. Marked = a root half is restarting: the
    # process its mark names (lock_ops) is still alive.
    restarting=false
    marked() {
        local pid start
        read -r pid start 2>/dev/null <"$restart_mark" || return 1
        [[ $pid =~ ^[0-9]+$ ]] && [ -n "$start" ] && [ "$(proc_start "$pid")" = "$start" ]
    }
    marked && restarting=true
    st=$(systemctl is-active "$unit" 2>/dev/null)
    # Up only once both are. Xray down (xray_state) = only its nodes are:
    # the probe through the active one tells (offline after the stall).
    if [ "$st" = active ] && uses_xray && [ "$(xray_state)" = starting ]; then
        st=activating
    fi
    enabled=false
    [ "$(systemctl is-enabled "$unit" 2>/dev/null)" = enabled ] && enabled=true
    online=false
    # IPv6 is broken on some hosts: -4.
    if [ "$st" = active ] && curl -4 -s -o /dev/null --connect-timeout 1 -m 2 "$probe"; then
        online=true
    fi
    sub=false
    [ -s "$sub_file" ] && sub=true
    ks=false
    ks_on && ks=true
    # Traffic held back: the table is up and sing-box is not (crashed,
    # failed, stopped behind the shell's back).
    blocking=false
    if systemctl is-active -q "$ks_unit" && ! systemctl is-active -q "$unit"; then
        blocking=true
    fi
    marked && restarting=true
    # The view; the old setup's world-readable config until the first apply.
    v=""
    if [ -r "$view" ]; then
        v=$(cat "$view")
    elif [ -r "$config" ]; then
        v=$(view_of "")
    fi
    # The rule covers the root-owned copy only: after these scripts changed,
    # pkexec asks again until `setup` copies them anew. (rules.d is not
    # readable by users on most systems: the copy, which `setup` installs
    # along with the rule, tells it is there.)
    pwless=false
    { [ -e "$rule" ] || [ -e "$sys_dir/virtualprivatenetwork.sh" ]; } && [ "$(root_self)" != "$self" ] && pwless=true
    jq -nc --argjson v "${v:-{\}}" --arg unit "$st" --argjson enabled "$enabled" --argjson installed "$installed" \
        --argjson online "$online" --argjson sub "$sub" --argjson ks "$ks" --argjson blocking "$blocking" \
        --argjson restarting "$restarting" --arg ch "$(hash_of "$custom_file")" --argjson pwless "$pwless" \
        '{ installed: $installed, unit: $unit, enabled: $enabled, online: $online, subscription: $sub,
        killswitch: $ks, blocking: $blocking, restarting: $restarting,
        profile: ($v.profile // ""), profiles: ($v.profiles // []),
        routing: ($v.routing // {}), customPending: ($ch != ($v.customHash // "")), passwordless: $pwless }'
    ;;
start | restart | enable | disable)
    # Xray first: sing-box's shadowsocks outbounds point at it. The kill
    # switch (if on) comes up with sing-box by itself (its drop-in).
    if uses_xray; then
        case $1 in
        start | restart) units_do "$1" xray "$unit" ;;
        *) systemctl "$1" xray "$unit" ;;
        esac || err "systemctl $1 failed"
    else
        systemctl "$1" "$unit" || err "systemctl $1 failed"
    fi
    ;;
stop)
    # Stop Xray too even if no node needs it any more. A deliberate stop is
    # the one thing that lowers the kill switch (also after a crash).
    units=("$unit")
    # Also one waiting out Restart= after a crash (shown as activating).
    case $(systemctl is-active xray 2>/dev/null) in
    inactive | failed) ;;
    *) units+=(xray) ;;
    esac
    systemctl is-active -q "$ks_unit" && units+=("$ks_unit")
    units_do stop "${units[@]}" || err "systemctl stop failed"
    ;;
killswitch)
    case "${2:-}" in
    on | off) ;;
    *) err "usage: killswitch on|off" ;;
    esac
    exec pkexec "$(root_self)" _killswitch "$2" "$(id -un)"
    ;;
select)
    [ -n "${2:-}" ] || err "usage: select <tag>"
    exec pkexec "$(root_self)" _select "$2"
    ;;
subscribe)
    # The shell passes the URL in the environment (only this user can read
    # it: /proc/<pid>/environ is 0400); an argument (by hand) is visible.
    url=${II_VPN_URL:-${2:-}}
    unset II_VPN_URL
    subscribe_url
    ;;
apply)
    mkdir -p "$state_dir"
    [ -n "${2:-}" ] && printf '%s\n' "$2" >"$routing_file"
    [ -s "$routing_file" ] || echo '{}' >"$routing_file"
    out=$(python3 -I "$here/routing.py" check "$routing_file" "$custom_file") || err "${out#ERR:}"
    fetch_rules "$routing_file" "${3:-}"
    # The overlay as applied (the view's hash of root's copy): routing only,
    # password-free with `setup` done; a changed overlay always asks.
    if [ "$(hash_of "$custom_file")" = "$(jq -r '.customHash // ""' "$view" 2>/dev/null)" ]; then
        exec pkexec "$(root_self)" _reroute "$(cat "$routing_file")" "$rules_cache"
    fi
    exec pkexec "$(root_self)" _routing "$(cat "$routing_file")" "$custom_file" "$rules_cache"
    ;;
unsubscribe)
    rm -f "$sub_file" "$provider_file" "$sub_hash"
    exec pkexec "$self" _unsubscribe
    ;;
migrate)
    mkdir -p "$state_dir"
    if [ ! -s "$sub_file" ] && [ -s "$old_sub_url" ] && [ -r "$old_sub_url" ]; then
        (umask 077 && cat "$old_sub_url" >"$sub_file")
    fi
    if [ -r "$old_rules" ]; then
        out=$(python3 -I "$here/routing.py" migrate "$old_rules") || err "${out#ERR:}"
        echo "$out"
    else
        echo '{}'
    fi
    ;;
edit)
    if [ ! -e "$custom_file" ]; then
        mkdir -p "$(dirname "$custom_file")"
        # Merged over the generated config (routing.py): rules here go first.
        printf '%s\n' '{' '  "route": { "rules": [] },' '  "dns": { "rules": [] }' '}' >"$custom_file"
    fi
    ed=${VISUAL:-${EDITOR:-}}
    if [ -z "$ed" ]; then
        for e in nvim vim nano vi; do
            command -v "$e" >/dev/null && { ed=$e; break; }
        done
    fi
    # shellcheck disable=SC2086 # "$EDITOR" may carry flags
    exec $ed "$custom_file"
    ;;
update)
    [ -s "$sub_file" ] || err "Subscription URL is not configured"
    url=$(<"$sub_file")
    subscribe_url
    ;;
check)
    [ -s "$sub_file" ] || err "Subscription URL is not configured"
    url=$(<"$sub_file")
    raw=$(mktemp) && hdr=$(mktemp) && meta=$(mktemp) || err "mktemp"
    trap 'rm -f "$raw" "$hdr" "$meta"' EXIT
    download_sub
    provider_meta
    save_provider "$meta" || err "cannot save the provider's info"
    # No hash yet (applied before hashes were kept): this one is the baseline.
    [ -s "$sub_hash" ] || hash_of "$raw" >"$sub_hash"
    if [ "$(hash_of "$raw")" = "$(cat "$sub_hash")" ]; then echo "OK:same"; else echo "OK:changed"; fi
    ;;
ping)
    t=$(curl -4 -s -o /dev/null -w '%{time_total}' --connect-timeout 5 -m 6 "$probe") || err "timeout"
    echo "OK:$(awk -v t="$t" 'BEGIN { printf "%d", t * 1000 }')"
    ;;
speedtest)
    command -v speedtest-cli >/dev/null || { echo ERR_MISSING; exit 1; }
    speedtest-cli --simple 2>/dev/null || { echo ERR_FAILED; exit 1; }
    ;;
setup)
    [ "$(id -u)" -eq 0 ] || exec pkexec "$self" setup "$(id -un)"
    root_only
    install -d -m 755 "$sys_dir"
    [ "$here" != "$sys_dir" ] && for f in "${sys_files[@]}"; do
        install -m 755 -o root -g root "$here/$f" "$sys_dir/$f" || err "cannot install $f"
    done
    write_rule "${2:?user}"
    echo "OK:$rule"
    ;;

# Root halves (pkexec) -------------------------------------------------------
_select)
    root_only
    lock_ops
    ms=$(selector)
    [ -n "$ms" ] || err "no selector outbound in $config"
    jq -e --arg ms "$ms" --arg tag "$2" \
        '.outbounds[] | select(.type == "selector" and .tag == $ms) | .outbounds | index($tag) != null' \
        "$config" >/dev/null || err "no node $2"
    tmp=$(mktemp) && btmp=$(mktemp) || err "mktemp"
    trap 'rm -f "$tmp" "$btmp"' EXIT
    sel='(.outbounds[] | select(.type == "selector" and .tag == $ms) | .default) = $tag'
    jq --arg ms "$ms" --arg tag "$2" "$sel" "$config" >"$tmp" || err "jq failed"
    # The base too (first: if the config then fails, the next recompose
    # still picks the node), or the next recompose would switch back.
    backup "$config"
    if [ -f "$base" ]; then
        jq --arg ms "$ms" --arg tag "$2" "$sel" "$base" >"$btmp" || err "jq failed on $base"
        backup "$base"
        with_base=1
        install -m 600 "$btmp" "$base" || err "cannot update $base"
    fi
    if ! install -m 640 -g "$(unit_group)" "$tmp" "$config"; then
        # Or the next recompose would switch to the node after all.
        [ -n "${with_base:-}" ] && install -m 600 "$base.bak" "$base"
        err "cannot update $config"
    fi
    # The view only once it is up: a rollback keeps the old node shown.
    restart_checked
    write_view || err "view update failed"
    echo "OK:$2"
    ;;
_killswitch)
    root_only
    lock_ops
    if [ "$2" = on ]; then
        command -v nft >/dev/null || err "nft (nftables) is not installed"
        id -u "$unit" >/dev/null 2>&1 || err "no $unit user"
        install_ks_rules || err "kill switch rules: nft rejected them or they could not be installed"
        # A config from before the TUN had a fixed name: name it, or the
        # table would block the VPN's own interface. The base too, or the
        # next recompose would bring the old name back. Before the switch
        # exists: if that fails (or sing-box does not come up with it, which
        # rolls both back), it does not go on.
        backup "$config"
        if [ -f "$base" ]; then
            backup "$base"
            with_base=1
            name_tun "$base" -m 600
            [ $? -eq 2 ] && err "cannot name the TUN $tun_name in $base"
        fi
        name_tun "$config" -m 640 -g "$(unit_group)"
        case $? in
        0) restart_checked ;;
        2)
            [ -n "${with_base:-}" ] && install -m 600 "$base.bak" "$base"
            err "cannot name the TUN $tun_name in $config"
            ;;
        esac
        cat >"$ks_unit_file" <<EOF
# illogical-impulse VPN kill switch (virtualprivatenetwork.sh): pulled in by ${unit}.service,
# stopped only by "virtualprivatenetwork.sh stop" — it outlives a crashed sing-box.
[Unit]
Description=illogical-impulse VPN kill switch
Before=${unit}.service xray.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/nft -f ${ks_rules}
ExecStop=-/usr/bin/nft delete table ${ks_table}
EOF
        mkdir -p "$(dirname "$ks_dropin")"
        printf '[Unit]\nWants=%s.service\n' "$ks_unit" >"$ks_dropin"
        # The password-free rule (if installed) learns the new unit.
        [ -e "$rule" ] && [ -n "${3:-}" ] && write_rule "$3"
        systemctl daemon-reload
        if systemctl is-active -q "$unit"; then
            systemctl start "$ks_unit" || err "kill switch failed to start"
        fi
    else
        systemctl stop "$ks_unit" 2>/dev/null
        rm -f "$ks_dropin"
        rmdir "$(dirname "$ks_dropin")" 2>/dev/null
        systemctl daemon-reload
    fi
    echo "OK:killswitch $2"
    ;;
_apply)
    root_only
    lock_ops
    # Not *.json and not in /etc/sing-box: the unit merges every *.json there.
    tmp=$(mktemp) || err "mktemp"
    xtmp=$(mktemp) || err "mktemp"
    ntmp=$(mktemp) || err "mktemp"
    etmp=$(mktemp) || err "mktemp"
    ktmp=$(mktemp) || err "mktemp"
    rtmp=$(mktemp) || err "mktemp"
    trap 'rm -f "$tmp" "$xtmp" "$ntmp" "$etmp" "$ktmp" "$rtmp"' EXIT
    # $4 the routing to apply with it (JSON text: the user's + the provider's
    # new part); none = the applied one.
    if [ -n "${4:-}" ]; then
        printf '%s\n' "$4" >"$rtmp"
    elif [ -s "$routing_etc" ]; then
        cat "$routing_etc" >"$rtmp"
    fi
    out=$(python3 -I "$here/routing.py" check "$rtmp") || err "${out#ERR:}"
    python3 -I "$here/sub_parser.py" "$tmp" "$2" "$etmp" || err "no nodes in the subscription"
    # gRPC / XHTTP / VLESS Encryption nodes to Xray. Without it (or for a
    # transport Xray lacks) the XHTTP / Encryption ones are dropped: sing-box
    # would reject the whole config over one of them (SKIPPED: lines).
    if xuid=$(id -u xray 2>/dev/null) && command -v xray >/dev/null; then
        python3 -I "$here/xray_split.py" "$tmp" "$xtmp" "$ntmp" "$xuid" "$etmp"
    else
        python3 -I "$here/xray_split.py" --drop "$tmp" "$etmp"
    fi
    case $? in
    0) ;;
    2) err "no usable node: the subscription's nodes need Xray" ;;
    *) err "xray split failed" ;;
    esac
    # Keep the chosen node across an update (the parser defaults to the first,
    # often a provider's placeholder) if the new subscription still has it.
    keep=$([ -r "$config" ] && jq -r --arg ms "$(selector)" \
        '[.outbounds[]? | select(.type == "selector" and .tag == $ms) | .default][0] // empty' "$config")
    # Through another mktemp file and back into $tmp's own: a new file (a
    # redirect, root's umask) would be 0644 — every node's secrets readable
    # in /tmp until the restart check is done.
    if [ -n "$keep" ]; then
        jq --arg tag "$keep" '(.outbounds[] | select(.type == "selector" and (.outbounds | index($tag) != null)) | .default) = $tag' \
            "$tmp" >"$ktmp" && cat "$ktmp" >"$tmp"
    fi
    sing-box check -c "$tmp" || err "sing-box rejected the generated config"
    # $tmp = the new base; the config = it + the applied routing / overlay.
    install_rules "$rtmp" "${3:-}" || err "rule-set install failed"
    ctmp=$(mktemp) || err "mktemp"
    trap 'rm -f "$tmp" "$xtmp" "$ntmp" "$etmp" "$ktmp" "$rtmp" "$ctmp"' EXIT
    out=$(compose "$tmp" "$rtmp" "$custom_etc" "$ctmp") || err "${out#ERR:}"
    if [ -s "$ntmp" ]; then
        # Via stdin: newer Xray picks a file's loader by extension even with
        # -format, and mktemp names have none.
        out=$(xray run -test -format json -config stdin: <"$xtmp" 2>&1) ||
            err "xray rejected the generated config: $(printf '%s' "$out" | grep -v 'Reading config' | tail -n 1)"
    fi
    mkdir -p "$(dirname "$config")"
    # Backups hold the same secrets: root only.
    # Xray's uid may be new to the kill switch: let it through before it runs.
    refresh_ks || err "kill switch update failed"
    backup "$config"
    install -m 640 -g "$(unit_group)" "$ctmp" "$config"
    xr=off
    if [ -s "$ntmp" ]; then
        xr=on
        mkdir -p "$(dirname "$xray_config")"
        backup "$xray_config"
        install -m 640 -g xray "$xtmp" "$xray_config"
    fi
    # Base and view only once it is up: a rollback keeps the old ones.
    restart_checked "$xr"
    mkdir -p "$(dirname "$base")"
    install -m 600 "$tmp" "$base"
    install -m 644 "$rtmp" "$routing_etc"
    write_view "$ntmp" || err "view update failed"
    # Unverified (not running): the old rule-sets stay for a rollback by hand.
    [ -n "$unchecked" ] || prune_rules "$routing_etc"
    echo "OK:applied"
    ;;
_unsubscribe)
    root_only
    lock_ops
    units=("$unit")
    systemctl is-active -q xray && units+=(xray)
    systemctl is-active -q "$ks_unit" && units+=("$ks_unit")
    systemctl stop "${units[@]}" 2>/dev/null
    rm -f "$config" "$config.bak" "$base" "$base.bak" "$view" "$xray_config" "$xray_config.bak" \
        "$old_sub_url" "$old_sub_cache"
    echo "OK:Subscription deleted and profiles cleared"
    ;;
_routing | _reroute)
    root_only
    lock_ops
    # $2 the routing (JSON text, not a path: a password-free caller could
    # name a root-only file, which would end up 0644 in $routing_etc).
    # _routing (polkit asks): $3 the user's overlay (may be missing), $4 the
    # rule-set downloads. _reroute (password-free): $3 the downloads; the
    # overlay is the applied one, untouched.
    tmps=()
    trap 'rm -f "${tmps[@]}"' EXIT
    rtmp=$(mktemp) && otmp=$(mktemp) && ctmp=$(mktemp) || err "mktemp"
    tmps=("$rtmp" "$otmp" "$ctmp")
    printf '%s\n' "${2:-}" >"$rtmp"
    if [ "$1" = _routing ]; then
        dl=${4:-}
        [ ! -L "${3:-}" ] || err "$3 is a symlink"
        if [ -f "${3:-}" ]; then cat -- "$3" >"$otmp" || err "cannot read $3"; else otmp=""; fi
    else
        dl=${3:-}
        if [ -f "$custom_etc" ]; then cat "$custom_etc" >"$otmp"; else otmp=""; fi
    fi
    out=$(python3 -I "$here/routing.py" check "$rtmp" "$otmp") || err "${out#ERR:}"
    # Before the base existed the config was one (nothing composed in yet).
    b=$base
    [ -f "$b" ] || b=$config
    [ -f "$b" ] || err "no config yet: import a subscription first"
    # A base from before the TUN had a fixed name (the kill switch needs it).
    if [ -f "$base" ]; then
        name_tun "$base" -m 600
        [ $? -eq 2 ] && err "cannot name the TUN $tun_name in $base"
    fi
    install_rules "$rtmp" "$dl" || err "rule-set install failed"
    out=$(compose "$b" "$rtmp" "$otmp" "$ctmp") || err "${out#ERR:}"
    mkdir -p "$(dirname "$base")"
    [ -f "$base" ] || install -m 600 "$config" "$base"
    backup "$config"
    install -m 640 -g "$(unit_group)" "$ctmp" "$config"
    # If it does not come up, the copies below stay the old ones, so the
    # change is still pending.
    restart_checked
    install -m 644 "$rtmp" "$routing_etc"
    [ -n "$unchecked" ] || prune_rules "$rtmp"
    # The overlay may name its own servers / keys: root only.
    if [ "$1" = _routing ]; then
        if [ -n "$otmp" ]; then install -m 600 "$otmp" "$custom_etc"; else rm -f "$custom_etc"; fi
    fi
    write_view || err "view update failed"
    echo "OK:routing applied"
    ;;
*)
    sed -n '2,/^set -u$/{/^set -u$/!p}' "$self"
    exit 2
    ;;
esac
