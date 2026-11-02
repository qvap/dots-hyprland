#!/usr/bin/env python3
# What a subscription's provider says besides the nodes (virtualprivatenetwork.sh,
# run as the user): the response headers (curl -D) and the body's `#key: value`
# / `://routing/...` lines, in the conventions of Happ / INCY / Remnawave
# panels. Headers win over body lines.
#
#   sub_meta.py routing-url <headers> <body>
#       the URL of the provider's routing profile, if it gives one (an
#       `autorouting` header, a `://routing/onadd/https://...` link): the
#       script downloads it and passes it to `meta`
#   sub_meta.py meta <headers> <body> [<routing profile>]
#       one JSON object (provider.json, read by services/Vpn.qml):
#       { fetched, title, description, traffic: { upload, download, total } |
#         null, expire (unix s, 0 = none), updateInterval (hours, 0 = none),
#         supportUrl, webPageUrl, announce, announceUrl, newUrl,
#         banner: { text, buttonText, url, color, buttonColor } | null,
#         expiryBanner: { ... } | null,
#         routing: { final, rules, dns, fakeip, sort, fragment } (keys at
#         their default left out), routingInfo: { name, dropped, final } }
#
# `routing` is the provider's part of the routing (routing.py, the
# "provider" key; routing.py validates it again as root): the profile's
# Block / Proxy / Direct lists as matcher rules (in that order: a site the
# provider proxies wins over its geosite in Direct), what Xray matchers have
# no word for here dropped (routingInfo.dropped counts them), its DNS servers and
# hosts, FakeDNS, and the headers `sort-order` and `fragmentation-*`.
# Profile format (Happ / INCY):
#   { "Name", "GlobalProxy": "true" | "false", "RemoteDNSType": "DoH" | "DoU",
#     "RemoteDNSDomain", "RemoteDNSIP", "DomesticDNSType", "DomesticDNSDomain",
#     "DomesticDNSIP", "DnsHosts": { domain: ip }, "FakeDNS", "DirectSites",
#     "DirectIp", "ProxySites", "ProxyIp", "BlockSites", "BlockIp", ... }
# Xray-only fields (DomainStrategy, Geoipurl / Geositeurl: .dat files) are
# ignored: geosite / geoip names come from routing.py's .srs sources.

import base64
import gzip
import ipaddress
import json
import re
import sys
import time
import urllib.parse

MAX_RULE_VALUES = 2000  # the routing travels as an argument (MAX_ARG_STRLEN)
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._!-]*$")
HOST_RE = re.compile(r"^[A-Za-z0-9.-]+$")
DOMAIN_RE = re.compile(r"^[A-Za-z0-9*._-]+$")
COLOR_RE = re.compile(r"^#?[0-9A-Fa-f]{3,8}$")


# --- Decoding ---------------------------------------------------------------

def b64(s):
    s = re.sub(r"\s+", "", s or "").replace("-", "+").replace("_", "/")
    return base64.b64decode(s + "=" * (-len(s) % 4))


def value_of(v):
    """A header value: plain, `base64:...`, `gzip:...` (base64 of gzip) and
    chains of them (`base64:gzip:...`)."""
    v = (v or "").strip()
    for _ in range(4):
        low = v[:7].lower()
        try:
            if low.startswith("base64:"):
                v = b64(v[7:]).decode("utf-8", "replace").strip()
                continue
            if low.startswith("gzip:"):
                v = gzip.decompress(b64(v[5:])).decode("utf-8", "replace").strip()
                continue
        except Exception:
            return ""
        break
    return v


def read_headers(path):
    """The last response's headers (curl -D writes one block per redirect),
    lower-case names; a repeated header: the first."""
    try:
        with open(path, encoding="latin-1") as f:
            text = f.read()
    except OSError:
        return {}
    blocks = [b for b in re.split(r"\r?\n\r?\n", text) if b.strip()]
    out = {}
    if not blocks:
        return out
    for line in blocks[-1].splitlines()[1:]:
        name, sep, val = line.partition(":")
        if sep and name.strip():
            # Headers are latin-1 on the wire; panels send UTF-8 anyway.
            try:
                val = val.encode("latin-1").decode("utf-8")
            except UnicodeError:
                pass
            out.setdefault(name.strip().lower(), val.strip())
    return out


def body_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read().strip()
    except OSError:
        return ""
    if re.fullmatch(r"[A-Za-z0-9+/_\-=\s]+", text or "-"):
        try:
            dec = b64(text).decode("utf-8")
            if "://" in dec or "#" in dec:
                return dec
        except Exception:
            pass
    return text


def body_meta(text):
    """`#key: value` lines and `://routing/...` links of the body."""
    meta, links = {}, []
    if text.lstrip().startswith(("{", "[")):
        return meta, links  # JSON: no lines
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r"^#\s*([A-Za-z][A-Za-z0-9-]*)\s*:\s*(.*)$", line)
        if m:
            meta.setdefault(m.group(1).lower(), m.group(2).strip())
        elif re.match(r"^[a-z0-9-]*://(auto)?routing/", line, re.I) or re.match(r"^[a-z0-9-]*://onadd/", line, re.I):
            links.append(line)
    return meta, links


# --- Small value parsers -----------------------------------------------------

def http_url(v):
    v = (v or "").strip()
    u = urllib.parse.urlparse(v)
    if u.scheme in ("http", "https") and u.hostname and not re.search(r"[\s\x00-\x1f]", v):
        return v
    return ""


def tg_or_url(v):
    """A link a button may open: http(s), tg:, mailto:."""
    v = (v or "").strip()
    if http_url(v):
        return v
    if re.match(r"^(tg|mailto):[^\s]+$", v):
        return v
    if re.match(r"^[^@\s]+@[^@\s]+\.[a-z]{2,}$", v, re.I):
        return "mailto:" + v
    return ""


def color(v):
    v = (v or "").strip()
    if COLOR_RE.match(v):
        return v if v.startswith("#") else "#" + v
    return ""


def integer(v, lo=0, hi=None):
    try:
        n = int(float(str(v).strip()))
    except (TypeError, ValueError):
        return None
    if n < lo or (hi is not None and n > hi):
        return None
    return n


def truthy(v):
    return str(v).strip().lower() in ("1", "true", "yes", "on")


def userinfo(v):
    """`upload=..; download=..; total=..; expire=..` -> (traffic, expire)."""
    v = (v or "").strip()
    if v == "0":
        return None, 0
    f = {}
    for part in re.split(r"[;,]", v):
        k, sep, n = part.partition("=")
        if sep:
            f[k.strip().lower()] = integer(n)
    expire = f.get("expire") or 0
    if expire > 32000000000:  # milliseconds
        expire //= 1000
    traffic = None
    if any(f.get(k) is not None for k in ("upload", "download", "total")):
        traffic = {k: f.get(k) or 0 for k in ("upload", "download", "total")}
    return traffic, expire


def title_of(v):
    """`profile-title`: base64 = name on the first line, the rest a
    description."""
    raw = (v or "").strip()
    v = value_of(raw)
    if raw.lower().startswith("base64:") and "\n" in v:
        name, _, desc = v.partition("\n")
        return name.strip()[:60], desc.strip()[:300]
    return v[:60], ""


# --- Routing profile ---------------------------------------------------------

def profile_from_link(link):
    """A `<scheme>://routing/{add|onadd}/<base64 | url>` link (or a bare
    base64 / JSON) -> ("url", u) | ("json", obj) | ("off", None) | None."""
    s = (link or "").strip()
    if not s:
        return None
    if s.lower() == "off" or re.match(r"^[a-z0-9-]*://routing/off/?$", s, re.I):
        return ("off", None)
    m = re.match(r"^[a-z0-9-]*://(?:auto)?routing/(?:(?:on)?add/)?(.*)$", s, re.I | re.S) \
        or re.match(r"^[a-z0-9-]*://onadd/(.*)$", s, re.I | re.S)
    if m:
        s = m.group(1).strip()
    if http_url(s):
        # A GitHub page of the file: its raw content instead.
        s = re.sub(r"^https://github\.com/([^/]+)/([^/]+)/blob/", r"https://raw.githubusercontent.com/\1/\2/", s)
        return ("url", s)
    obj = profile_json(s)
    return ("json", obj) if obj is not None else None


def profile_json(text):
    text = (text or "").strip()
    for cand in (text, None):
        if cand is None:
            try:
                cand = b64(text).decode("utf-8")
            except Exception:
                return None
        try:
            obj = json.loads(cand)
        except ValueError:
            continue
        if isinstance(obj, list) and obj and isinstance(obj[0], dict):
            obj = obj[0]
        if isinstance(obj, dict):
            return obj
    return None


def profile_source(headers, links):
    """INCY's priority: the autorouting header > a body URL line > the
    routing header > a body base64 line."""
    cands = []
    if headers.get("autorouting"):
        cands.append(value_of(headers["autorouting"]))
    url_links = [l for l in links if (profile_from_link(l) or ("",))[0] == "url"]
    cands += url_links
    if headers.get("routing"):
        cands.append(value_of(headers["routing"]))
    cands += [l for l in links if l not in url_links]
    for c in cands:
        p = profile_from_link(c)
        if p:
            return p
    return None


def field(obj, *names):
    low = {k.lower(): v for k, v in obj.items()} if isinstance(obj, dict) else {}
    for n in names:
        if n.lower() in low:
            return low[n.lower()]
    return None


def as_list(v):
    if isinstance(v, list):
        return [x for x in v if isinstance(x, str) and x.strip()]
    if isinstance(v, str):
        return [x for x in re.split(r"[\n,]+", v) if x.strip()]
    return []


def is_ip(v):
    try:
        ipaddress.ip_network(v, strict=False)
        return True
    except ValueError:
        return False


def site_matcher(v):
    """An Xray domain matcher -> ours, or None (no equivalent)."""
    v = v.strip()
    kind, sep, rest = v.partition(":")
    kind = kind.lower() if sep else ""
    if kind == "geosite":
        # geosite:name@attr: attributes have no .srs; the whole list instead
        # would route more than asked: dropped.
        name = rest.strip().lower()
        return "geosite:" + name if NAME_RE.match(name) and "@" not in name else None
    if kind in ("domain", "full", "keyword"):
        return "%s:%s" % (kind, rest.strip()) if rest.strip() and DOMAIN_RE.match(rest.strip()) else None
    if kind == "regexp":
        try:
            re.compile(rest)
        except re.error:
            return None
        return "regexp:" + rest if rest else None
    if kind == "dotless":
        return None
    if sep and kind in ("ext", "geoip"):
        return None
    if not sep:
        # Xray: a plain string matches anywhere in the name.
        return "keyword:" + v if DOMAIN_RE.match(v) else None
    return None


PRIVATE = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "169.254.0.0/16",
           "127.0.0.0/8", "fc00::/7", "fe80::/10"]


def ip_matchers(v):
    v = v.strip()
    if v.startswith("!"):
        return None
    kind, sep, rest = v.partition(":")
    if sep and kind.lower() == "geoip":
        name = rest.strip().lower()
        if name == "private":
            return ["ip:" + c for c in PRIVATE]
        return ["geoip:" + name] if NAME_RE.match(name) and "@" not in name else None
    if is_ip(v):
        return ["ip:" + v]
    return None


def dns_server(kind, domain, ip):
    """A Happ DNS pair -> { type, server, path, tlsName } | None."""
    kind = str(kind or "").strip().lower()
    domain = str(domain or "").strip()
    ip = str(ip or "").strip()
    if ip and not is_ip(ip):
        ip = ""
    if kind in ("dou", "udp", "dns"):
        host = ip or (domain if HOST_RE.match(domain) else "")
        return {"type": "udp", "server": host} if host else None
    if kind in ("doh", "https", ""):
        u = urllib.parse.urlparse(domain if "://" in domain else "https://" + domain) if domain else None
        host = u.hostname if u and u.hostname and HOST_RE.match(u.hostname) else ""
        path = u.path if u and u.path and re.fullmatch(r"/[A-Za-z0-9._~/-]*", u.path) else "/dns-query"
        if not (ip or host):
            return None
        s = {"type": "https", "server": ip or host, "path": path}
        if ip and host and not is_ip(host):
            s["tlsName"] = host
        return s
    return None


def routing_of(profile):
    """The profile -> our provider routing (see the header)."""
    out = {"rules": [], "dropped": 0}
    if not isinstance(profile, dict):
        return out
    name = field(profile, "Name")
    if isinstance(name, str):
        out["name"] = name.strip()[:60]
    gp = field(profile, "GlobalProxy")
    if gp is not None:
        out["final"] = "proxy" if truthy(gp) else "direct"
    budget = MAX_RULE_VALUES
    for action, sites, ips in (("block", "BlockSites", "BlockIp"),
                               ("proxy", "ProxySites", "ProxyIp"),
                               ("direct", "DirectSites", "DirectIp")):
        match = []
        for v in as_list(field(profile, sites)):
            m = site_matcher(v)
            if m and budget > 0:
                match.append(m)
                budget -= 1
            else:
                out["dropped"] += 1
        for v in as_list(field(profile, ips)):
            ms = ip_matchers(v)
            if ms and budget >= len(ms):
                match += ms
                budget -= len(ms)
            else:
                out["dropped"] += 1
        if match:
            # Order kept, duplicates out.
            out["rules"].append({"action": action, "match": list(dict.fromkeys(match))})
    dns = {}
    remote = dns_server(field(profile, "RemoteDNSType"), field(profile, "RemoteDNSDomain"),
                        field(profile, "RemoteDNSIP") or field(profile, "RemoteDns"))
    domestic = dns_server(field(profile, "DomesticDNSType"), field(profile, "DomesticDNSDomain"),
                          field(profile, "DomesticDNSIP") or field(profile, "DomesticDns"))
    if remote:
        dns["remote"] = remote
    if domestic:
        dns["domestic"] = domestic
    hosts = {}
    raw_hosts = field(profile, "DnsHosts")
    if isinstance(raw_hosts, dict):
        for d, ips in raw_hosts.items():
            ips = [i.strip() for i in as_list(ips) if is_ip(i.strip()) and "/" not in i]
            if isinstance(d, str) and HOST_RE.match(d.strip()) and ips and len(hosts) < 200:
                hosts[d.strip().lower()] = ips
    if hosts:
        dns["hosts"] = hosts
    if dns:
        out["dns"] = dns
    if truthy(field(profile, "FakeDNS") or ""):
        out["fakeip"] = True
    return out


# --- Commands ----------------------------------------------------------------

def pick(headers, meta, *names):
    for n in names:
        if headers.get(n):
            return value_of(headers[n])
    for n in names:
        if meta.get(n):
            return value_of(meta[n])
    return ""


def meta_of(headers, body, profile_path):
    meta, links = body_meta(body)
    out = {"fetched": int(time.time())}
    t = headers.get("profile-title") or meta.get("profile-title") or headers.get("subscription-name") or ""
    title, desc = title_of(t)
    if not title:
        cd = headers.get("content-disposition", "")
        m = re.search(r"filename\*?=(?:UTF-8'')?\"?([^\";]+)", cd, re.I)
        if m:
            title = re.sub(r"\.(txt|yaml|yml|json)$", "", urllib.parse.unquote(m.group(1)).strip(), flags=re.I)[:60]
    out["title"], out["description"] = title, desc
    ui = headers.get("subscription-userinfo") or meta.get("subscription-userinfo")
    out["traffic"], out["expire"] = userinfo(ui) if ui else (None, 0)
    out["updateInterval"] = integer(pick(headers, meta, "profile-update-interval"), 1, 24 * 365) or 0
    out["supportUrl"] = tg_or_url(pick(headers, meta, "support-url")) or tg_or_url(pick(headers, meta, "support-email"))
    out["webPageUrl"] = http_url(pick(headers, meta, "profile-web-page-url", "homepage"))
    out["announce"] = pick(headers, meta, "announce")[:500]
    out["announceUrl"] = tg_or_url(pick(headers, meta, "announce-url"))
    new = http_url(value_of(headers.get("new-url", "")))
    if not new and headers.get("new-domain"):
        dom = value_of(headers["new-domain"]).strip().lower()
        if HOST_RE.match(dom) and "." in dom:
            new = "@" + dom  # the script swaps the host of the URL it has
    out["newUrl"] = new
    text = pick(headers, meta, "banner-text")
    out["banner"] = {
        "text": text[:300],
        "buttonText": pick(headers, meta, "banner-button-text")[:40],
        "url": tg_or_url(pick(headers, meta, "banner-button-url", "banner-url")),
        "color": color(pick(headers, meta, "banner-bg-color")),
        "buttonColor": color(pick(headers, meta, "banner-button-color")),
    } if text else None
    etext = pick(headers, meta, "expiry-banner-text")
    out["expiryBanner"] = {
        "text": etext[:300],
        "buttonText": pick(headers, meta, "expiry-banner-button-text")[:40],
        "url": tg_or_url(pick(headers, meta, "expiry-banner-button-url", "expiry-banner-url")),
        "color": color(pick(headers, meta, "expiry-banner-bg-color")),
        "buttonColor": color(pick(headers, meta, "expiry-banner-button-color")),
    } if etext else None

    profile = None
    src = profile_source(headers, links)
    if src and src[0] == "json":
        profile = src[1]
    elif src and src[0] == "url" and profile_path:
        try:
            with open(profile_path, encoding="utf-8", errors="replace") as f:
                profile = profile_json(f.read())
        except OSError:
            profile = None
    routing = routing_of(profile) if src and src[0] != "off" else {"rules": [], "dropped": 0}
    sort = pick(headers, meta, "sort-order").lower()
    if sort in ("name", "ping"):
        routing["sort"] = sort
    if truthy(pick(headers, meta, "fragmentation-enable")):
        routing["fragment"] = True
    # What only informs (the panel shows it) apart: `routing` is compared
    # with the applied one, a change there restarts sing-box.
    out["routingInfo"] = {"name": routing.pop("name", ""), "dropped": routing.pop("dropped", 0),
                          "final": routing.get("final", "")}
    if not routing["rules"]:
        del routing["rules"]
    out["routing"] = routing
    return out


def main():
    a = sys.argv[1:]
    if len(a) >= 3 and a[0] == "routing-url":
        _, links = body_meta(body_text(a[2]))
        src = profile_source(read_headers(a[1]), links)
        if src and src[0] == "url":
            print(src[1])
        return
    if len(a) >= 3 and a[0] == "meta":
        print(json.dumps(meta_of(read_headers(a[1]), body_text(a[2]), a[3] if len(a) > 3 else ""),
                         ensure_ascii=False))
        return
    sys.stderr.write("usage: see the header\n")
    sys.exit(2)


if __name__ == "__main__":
    main()
