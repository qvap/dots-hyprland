#!/usr/bin/env python3
# Split routing + the user's own config overlay for sing-box
# (virtualprivatenetwork.sh).
#
# Routing (Config.options.vpn.routing, edited in the VPN details window):
#   { "final": "proxy" | "direct",
#     "rules": [ { "action": "proxy" | "direct" | "block",
#                  "match": ["geoip:ru", "geosite:category-ru", "domain:example.com",
#                            "process:steam", ...], "enabled": true }, ... ],
#     "fakeip": false, "remoteDns": "8.8.8.8",
#     "hysteria2UpMbps": 0, "hysteria2DownMbps": 0 }
# Rules are tried in order, the first match wins; within a rule any matcher
# may match. Matchers:
#   domain:<d>   d and its subdomains        full:<d>     exactly d
#   keyword:<s>  domain contains s           regexp:<re>  domain regex
#   ip:<cidr>    destination address         process:<n>  executable name
#   path:<p>     executable path             protocol:<p> sniffed (bittorrent,
#                                                         quic, stun, ...)
#   geosite:<name>[@source]   geoip:<name>[@source]
#   a bare value = ip: if it parses as an address / CIDR, else domain:.
# geosite / geoip are binary rule-sets (.srs) from SOURCES, tried in order
# unless @source pins one; the script downloads them (`rulesets`), compose reads
# them from the rules dir. LAN (private addresses) always goes direct.
# DNS follows the route: domains routed direct resolve through dns-direct
# (CDNs answer with nearby addresses), proxied ones through dns-remote,
# blocked ones are refused.
# fakeip: DNS answers from 198.18.0.0/15 for what the TUN asks (faster, no
# leaks; breaks some apps: Spotify is kept on real addresses). remoteDns: the
# DoH server queried through the proxy. hysteria2*Mbps (> 0): the speeds told
# to Hysteria2 nodes (Brutal congestion control), over the subscription's.
#
# Overlay (the user's own sing-box JSON, applied last, wins over everything):
# objects merge recursively, `null` deletes a key, arrays of tagged objects
# (outbounds, endpoints, inbounds, dns.servers, route.rule_set) merge by tag
# (same tag = replaced), route.rules / dns.rules are put in front of the
# generated ones (after the sniff / hijack-dns rules and Xray's uid rule),
# other arrays replace. The result's tag references (outbounds, DNS servers,
# rule-sets) are checked: `sing-box check` does not, sing-box fails at start.
#
#   routing.py check <routing.json> [overlay.json]       exit 1 + message
#   routing.py rulesets <routing.json>                   "file<TAB>url..." lines
#   routing.py compose <base.json> <routing.json> <overlay.json> <rules dir> <out>
#   routing.py migrate <custom_rules.json>   the old rules file -> one JSON line
#                                            { routing, overlay } (see migrate())
# Missing routing / overlay files = none (everything through the proxy).

import ipaddress
import json
import os
import re
import sys

SOURCES = {
    "runetfreedom": {
        "geosite": "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-{}.srs",
        "geoip": "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geoip/geoip-{}.srs",
    },
    "metacubex": {
        "geosite": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/{}.srs",
        "geoip": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/{}.srs",
    },
    "sagernet": {
        "geosite": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-{}.srs",
        "geoip": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-{}.srs",
    },
}
SOURCE_ORDER = ("runetfreedom", "metacubex", "sagernet")
ACTIONS = ("proxy", "direct", "block")
# Matcher prefix -> headless rule field (inline rule-sets).
FIELDS = {
    "domain": "domain_suffix", "full": "domain", "keyword": "domain_keyword",
    "regexp": "domain_regex", "ip": "ip_cidr", "process": "process_name",
    "path": "process_path",
}
DNS_FIELDS = ("domain_suffix", "domain", "domain_keyword", "domain_regex")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._!-]*$")
HOST_RE = re.compile(r"^[A-Za-z0-9.:\[\]-]+$")
SPOTIFY = ["scdn.co", "spotify.com", "spotifycdn.com"]
PREFIX = "ii-"


class Bad(Exception):
    pass


def load(path, default):
    if not path or not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if not text.strip():
        return default
    try:
        return json.loads(text)
    except ValueError as e:
        raise Bad("%s: %s" % (os.path.basename(path), e))


def is_ip(v):
    try:
        ipaddress.ip_network(v, strict=False)
        return True
    except ValueError:
        return False


def parse(m):
    """matcher string -> (kind, value, source)"""
    if not isinstance(m, str) or not m.strip():
        raise Bad("empty matcher")
    m = m.strip()
    kind, sep, value = m.partition(":")
    if not sep or kind not in FIELDS and kind not in ("geosite", "geoip", "protocol"):
        # Bare value (an IPv6 address has colons but no known prefix).
        kind, value = ("ip", m) if is_ip(m) else ("domain", m)
    value = value.strip()
    if not value:
        raise Bad("%s: empty value" % m)
    source = ""
    if kind in ("geosite", "geoip"):
        value, _, source = value.lower().partition("@")
        if not NAME_RE.match(value):
            raise Bad("%s: bad list name" % m)
        if source and source not in SOURCES:
            raise Bad("%s: unknown source (%s)" % (m, ", ".join(SOURCE_ORDER)))
    elif kind == "ip" and not is_ip(value):
        raise Bad("%s: not an address / CIDR" % m)
    elif kind == "regexp":
        try:
            re.compile(value)
        except re.error as e:
            raise Bad("%s: %s" % (m, e))
    return kind, value, source


def rules_of(routing):
    if not isinstance(routing, dict):
        raise Bad("routing: not an object")
    final = routing.get("final", "proxy")
    if final not in ("proxy", "direct"):
        raise Bad("routing.final: proxy | direct")
    dns = routing.get("remoteDns") or ""
    if not isinstance(dns, str) or dns and not HOST_RE.match(dns):
        raise Bad("remoteDns: a host name or address")
    for k in ("hysteria2UpMbps", "hysteria2DownMbps"):
        v = routing.get(k, 0)
        if not isinstance(v, int) or isinstance(v, bool) or v < 0:
            raise Bad("%s: a whole number >= 0" % k)
    out = []
    for i, r in enumerate(routing.get("rules") or []):
        if not isinstance(r, dict) or r.get("action") not in ACTIONS:
            raise Bad("rule %d: action must be %s" % (i + 1, " | ".join(ACTIONS)))
        if r.get("enabled", True) is False:
            continue
        match = r.get("match") or []
        if isinstance(match, str):
            match = [match]
        out.append((r["action"], [parse(m) for m in match]))
    return final, out


def ruleset_file(kind, name, source):
    return "%s-%s%s.srs" % (kind, name, "@" + source if source else "")


def rulesets(routing):
    """Unique (file, [urls]) the routing needs, in rule order."""
    seen, out = set(), []
    for _, matchers in rules_of(routing)[1]:
        for kind, value, source in matchers:
            if kind not in ("geosite", "geoip"):
                continue
            f = ruleset_file(kind, value, source)
            if f in seen:
                continue
            seen.add(f)
            out.append((f, [SOURCES[s][kind].format(value) for s in ((source,) if source else SOURCE_ORDER)]))
    return out


def compose_routing(cfg, routing, rules_dir):
    final, rules = rules_of(routing)
    route = cfg.setdefault("route", {})
    sets = route.setdefault("rule_set", [])
    rrules = route.setdefault("rules", [])
    dns = cfg.setdefault("dns", {})
    drules = dns.setdefault("rules", [])
    proxy = next((o["tag"] for o in cfg.get("outbounds", []) if o.get("type") == "selector"), "proxy")
    target = {"proxy": {"outbound": proxy}, "direct": {"outbound": "direct"}, "block": {"action": "reject"}}
    dns_target = {"proxy": {"server": "dns-remote"}, "direct": {"server": "dns-direct"},
                  "block": {"action": "reject"}}

    rrules.append({"ip_is_private": True, "outbound": "direct"})
    files = set()
    gen_dns = []
    for i, (action, matchers) in enumerate(rules):
        fields, dfields, tags, dtags, protocols = {}, {}, [], [], []
        for kind, value, source in matchers:
            if kind == "protocol":
                protocols.append(value)
            elif kind in ("geosite", "geoip"):
                f = ruleset_file(kind, value, source)
                tag = PREFIX + f[:-4]
                if f not in files:
                    path = os.path.join(rules_dir, f)
                    if not os.path.exists(path):
                        raise Bad("%s:%s is not downloaded" % (kind, value))
                    files.add(f)
                    sets.append({"type": "local", "tag": tag, "format": "binary", "path": path})
                tags.append(tag)
                if kind == "geosite":
                    dtags.append(tag)
            else:
                field = FIELDS[kind]
                fields.setdefault(field, []).append(value)
                if field in DNS_FIELDS:
                    dfields.setdefault(field, []).append(value)
        if fields:
            tag = "%sr%d" % (PREFIX, i + 1)
            sets.append({"type": "inline", "tag": tag, "rules": [{k: v} for k, v in fields.items()]})
            tags.insert(0, tag)
        if dfields:
            tag = "%sd%d" % (PREFIX, i + 1)
            sets.append({"type": "inline", "tag": tag, "rules": [{k: v} for k, v in dfields.items()]})
            dtags.insert(0, tag)
        if tags:
            rrules.append(dict({"rule_set": tags}, **target[action]))
        if protocols:
            rrules.append(dict({"protocol": protocols}, **target[action]))
        if dtags:
            gen_dns.append(dict({"rule_set": dtags}, **dns_target[action]))

    route["final"] = proxy if final == "proxy" else "direct"
    for s in dns.get("servers", []):
        if s.get("tag") == "dns-remote" and routing.get("remoteDns"):
            s["server"] = routing["remoteDns"]
    if routing.get("fakeip"):
        dns.setdefault("servers", []).append({"tag": "dns-fakeip", "type": "fakeip",
                                              "inet4_range": "198.18.0.0/15",
                                              "inet6_range": "fc00::/18"})
        gen_dns += [
            {"action": "route", "domain_suffix": SPOTIFY, "server": "dns-remote"},
            # IPv4 only (the rule action `strategy` is deprecated in 1.14):
            # fake A answers, empty AAAA ones.
            {"action": "route", "inbound": "tun-in", "query_type": ["A"],
             "server": "dns-fakeip", "disable_cache": True},
            {"action": "predefined", "inbound": "tun-in", "query_type": ["AAAA"],
             "rcode": "NOERROR"},
        ]
    for o in cfg.get("outbounds", []):
        if o.get("type") == "hysteria2":
            for k, f in (("hysteria2UpMbps", "up_mbps"), ("hysteria2DownMbps", "down_mbps")):
                if routing.get(k):
                    o[f] = routing[k]
    # Before the catch-all (sub_parser's last DNS rule, no matcher fields).
    catch = len(drules)
    if drules and set(drules[-1]) <= {"action", "server", "strategy"}:
        catch = len(drules) - 1
        # Unmatched names resolve where their traffic goes.
        drules[-1]["server"] = "dns-remote" if final == "proxy" else "dns-direct"
    drules[catch:catch] = gen_dns
    if not sets:
        route.pop("rule_set")


TAGGED = {("outbounds",), ("endpoints",), ("inbounds",), ("dns", "servers"), ("route", "rule_set")}
PREPEND = {("route", "rules"), ("dns", "rules")}


def merge(base, over, path=()):
    for k, v in over.items():
        p = path + (k,)
        if v is None:
            base.pop(k, None)
        elif isinstance(v, dict) and isinstance(base.get(k), dict):
            merge(base[k], v, p)
        elif isinstance(v, list) and isinstance(base.get(k), list) and p in TAGGED:
            by_tag = {o.get("tag"): j for j, o in enumerate(base[k]) if isinstance(o, dict)}
            for o in v:
                j = by_tag.get(o.get("tag")) if isinstance(o, dict) else None
                if j is None:
                    base[k].append(o)
                else:
                    base[k][j] = o
        elif isinstance(v, list) and isinstance(base.get(k), list) and p in PREPEND:
            # After the leading sniff / hijack-dns rules (theirs see the
            # sniffed domain) and Xray's own uid rule (no loop through the
            # TUN); DNS has no such rules (index 0).
            n = 0
            while n < len(base[k]) and (base[k][n].get("action") in ("sniff", "hijack-dns")
                                        or "user_id" in base[k][n]):
                n += 1
            base[k][n:n] = v
        else:
            base[k] = v


def check_refs(cfg):
    """`sing-box check` parses only: a dangling tag fails at start, with the
    VPN down. The references routing / an overlay can break."""
    outs = {o.get("tag") for k in ("outbounds", "endpoints") for o in cfg.get(k, []) if isinstance(o, dict)}
    dns = cfg.get("dns") or {}
    route = cfg.get("route") or {}
    servers = {s.get("tag") for s in dns.get("servers", []) if isinstance(s, dict)}
    sets = {s.get("tag") for s in route.get("rule_set", []) if isinstance(s, dict)}
    bad = []

    def need(kind, have, tag, where):
        if tag is not None and tag not in have:
            bad.append("%s: unknown %s %r" % (where, kind, tag))

    def resolver(r, where):
        need("DNS server", servers, r.get("server") if isinstance(r, dict) else r, where)

    def rules(lst, where, field, have, kind):
        for i, r in enumerate(lst or []):
            if not isinstance(r, dict):
                continue
            w = "%s[%d]" % (where, i)
            need(kind, have, r.get(field), w)
            rs = r.get("rule_set")
            for t in [rs] if isinstance(rs, str) else rs or []:
                need("rule-set", sets, t, w)
            rules(r.get("rules"), w, field, have, kind)  # logical rules

    need("outbound", outs, route.get("final"), "route.final")
    rules(route.get("rules"), "route.rules", "outbound", outs, "outbound")
    rules(dns.get("rules"), "dns.rules", "server", servers, "DNS server")
    need("DNS server", servers, dns.get("final"), "dns.final")
    if route.get("default_domain_resolver") is not None:
        resolver(route["default_domain_resolver"], "route.default_domain_resolver")
    for k in ("outbounds", "endpoints"):
        for o in cfg.get(k, []):
            if not isinstance(o, dict):
                continue
            w = "%s %r" % (k[:-1], o.get("tag"))
            for t in o.get("outbounds") or []:
                need("outbound", outs, t, w)
            need("outbound", outs, o.get("detour"), w)
            if o.get("domain_resolver") is not None:
                resolver(o["domain_resolver"], w)
    for s in dns.get("servers", []):
        if isinstance(s, dict):
            w = "dns server %r" % s.get("tag")
            need("outbound", outs, s.get("detour"), w)
            if s.get("domain_resolver") is not None:
                resolver(s["domain_resolver"], w)
    if bad:
        raise Bad("; ".join(bad[:3]) + (" (+%d more)" % (len(bad) - 3) if len(bad) > 3 else ""))


# The old custom_rules.json (one rule = sing-box fields, AND-ed by sing-box)
# -> the matcher form (OR-ed, which is what adding values one by one meant).
MIGRATE = {"domain": "full", "domain_suffix": "domain", "domain_keyword": "keyword",
           "domain_regex": "regexp", "ip_cidr": "ip", "process_name": "process",
           "process_path": "path", "protocol": "protocol", "geoip": "geoip",
           "geosite": "geosite"}
OLD_GEO = {"geosite": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-%s.srs",
           "geoip": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-%s.srs"}


def as_list(v):
    return v if isinstance(v, list) else [] if v is None else [v]


def migrate(old):
    """{ routing, overlay }: rules the matchers can say go to routing
    (geosite / geoip pinned to SagerNet, the old source); raw ones, custom
    outbounds and fields matchers have no word for (port, network, ...) go
    to the overlay as sing-box rules, with the remote rule-sets they used."""
    if isinstance(old, list):
        old = {"rules": old}
    if not isinstance(old, dict):
        raise Bad("custom rules: not an object")
    rules, over_rules, over_sets, seen = [], [], [], set()
    for rs in as_list(old.get("rule_sets")):
        if isinstance(rs, dict) and rs.get("tag"):
            over_sets.append(rs)
            seen.add(rs["tag"])
    for r in as_list(old.get("rules")):
        if not isinstance(r, dict):
            continue
        if r.get("raw") is True:
            over_rules.append({k: v for k, v in r.items() if k != "raw"})
            continue
        block = r.get("action") == "reject" or r.get("outbound") in ("block", "reject")
        action = "block" if block else r.get("outbound", "proxy")
        known = set(MIGRATE) | {"action", "outbound"}
        if action in ACTIONS and set(r) <= known:
            match = []
            for k, prefix in MIGRATE.items():
                for v in as_list(r.get(k)):
                    v = str(v).strip()
                    if prefix in ("geoip", "geosite"):
                        v = v.lower() + "@sagernet"
                    if v:
                        match.append(prefix + ":" + v)
            if match:
                rules.append({"action": action, "match": match, "enabled": True})
            continue
        rule = {k: v for k, v in r.items() if k not in ("geoip", "geosite")}
        if block:
            rule.pop("outbound", None)
            rule["action"] = "reject"
        tags = as_list(rule.get("rule_set"))
        for kind in ("geoip", "geosite"):
            for name in as_list(r.get(kind)):
                name = re.sub(r"[^a-z0-9_.-]+", "-", str(name).strip().lower())
                tag = "%s-%s" % (kind, name)
                tags.append(tag)
                if tag not in seen:
                    seen.add(tag)
                    over_sets.append({"tag": tag, "type": "remote", "format": "binary",
                                      "url": OLD_GEO[kind] % name, "download_detour": "direct"})
        if tags:
            rule["rule_set"] = tags
        over_rules.append(rule)
    dns = old.get("dns") if isinstance(old.get("dns"), dict) else {}
    hy = old.get("hysteria2") if isinstance(old.get("hysteria2"), dict) else {}

    def mbps(*keys):
        for k in keys:
            try:
                return max(0, int(float(hy[k])))
            except (KeyError, TypeError, ValueError):
                pass
        return 0

    routing = {"final": "proxy", "rules": rules, "fakeip": dns.get("fakeip") is True,
               "remoteDns": str(dns.get("remote") or "8.8.8.8"),
               "hysteria2UpMbps": mbps("up_mbps", "upMbps", "up"),
               "hysteria2DownMbps": mbps("down_mbps", "downMbps", "down")}
    overlay = {}
    if over_rules or over_sets:
        overlay["route"] = {}
        if over_rules:
            overlay["route"]["rules"] = over_rules
        if over_sets:
            overlay["route"]["rule_set"] = over_sets
    return {"routing": routing, "overlay": overlay}


def main():
    a = sys.argv[1:]
    try:
        if a[:1] == ["check"] and len(a) >= 2:
            rules_of(load(a[1], {}))
            over = load(a[2] if len(a) > 2 else "", {})
            if not isinstance(over, dict):
                raise Bad("overlay: not an object")
        elif a[:1] == ["migrate"] and len(a) == 2:
            print(json.dumps(migrate(load(a[1], {})), ensure_ascii=False))
        elif a[:1] == ["rulesets"] and len(a) == 2:
            for f, urls in rulesets(load(a[1], {})):
                print("\t".join([f] + urls))
        elif a[:1] == ["compose"] and len(a) == 6:
            cfg = load(a[1], None)
            if not isinstance(cfg, dict):
                raise Bad("no base config")
            compose_routing(cfg, load(a[2], {}), a[4])
            over = load(a[3], {})
            if not isinstance(over, dict):
                raise Bad("overlay: not an object")
            merge(cfg, over)
            check_refs(cfg)
            with open(a[5], "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2, ensure_ascii=False)
        else:
            sys.stderr.write("usage: see the header\n")
            sys.exit(2)
    except Bad as e:
        print("ERR:%s" % e)
        sys.exit(1)


if __name__ == "__main__":
    main()
