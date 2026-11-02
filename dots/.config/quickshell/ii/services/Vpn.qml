pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/* VPN: sing-box as a system unit (+ xray.service for gRPC / XHTTP nodes),
 * driven by scripts/vpn/virtualprivatenetwork.sh. State = one `state` JSON
 * poll (every 5 s, faster while a change settles). One operation at a time
 * (`busy`); start / stop go through systemd's polkit check (no password once
 * the "start without password" rule is installed), everything that writes
 * the config through pkexec. Split routing lives in
 * Config.options.vpn.routing and the user's own sing-box JSON (the overlay)
 * in ~/.config/illogical-impulse/vpn/custom.json; both take effect on
 * applyRouting() (sing-box restarts; a config it cannot start with is rolled
 * back). `pending` = either differs from what is in force.
 * The provider's word (headers / body lines of the subscription: title,
 * traffic, expiry, banners, its routing / DNS / fragmentation / node order)
 * is read by scripts/vpn/sub_meta.py into `provider` (provider.json in the
 * user state). Its routing part rides along as the routing's "provider" key
 * and goes in force with every subscribe / update; one refreshed by `check`
 * (every profile-update-interval, 24 h without one, no root) is put in
 * force by itself when that needs no password and nothing of the user's
 * is pending, else it shows as pending like the user's changes.
 */

QtObject {
    id: root

    property string scriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/vpn/virtualprivatenetwork.sh`
    property string overlayPath: `${FileUtils.trimFileProtocol(Directories.shellConfig)}/vpn/custom.json`
    property string providerPath: `${FileUtils.trimFileProtocol(Directories.state)}/user/vpn/provider.json`

    // Last `state` poll
    property bool polled: false
    property bool installed: true
    property string unit: "inactive"
    property bool enabled: false // Autostart at boot
    property bool online: false
    property string activeProfile: ""
    // [{ tag, name, type, base, xray, insecure, isActive, index }]
    property var profiles: []
    property bool hasSubscription: false
    property bool killswitch: false
    // The kill switch holds traffic back: sing-box died while it was up
    property bool blocking: false
    property bool passwordless: false
    property var appliedRouting: ({})
    property bool customPending: false

    // Running operation: "" | start | stop | restart | autostart | killswitch
    // | select | subscribe | update | unsubscribe | routing | setup
    property string busy: ""
    property string selecting: ""
    property string lastError: ""
    property string missingDependency: ""
    property string subscriptionStatus: ""
    property string subscriptionUrl: ""
    // Up but the probe through it failed for 12 s: the node is dead
    property bool stalled: false
    // A root half is restarting the units itself (`state`): the unit and the
    // kill switch pass through states that are no real change
    property bool restarting: false
    // Start / stop / restart too pass through "kill switch up, sing-box not"
    // (it is ordered before sing-box): no "traffic blocked" for those
    readonly property bool holdBlocking: restarting || ["start", "stop", "restart"].includes(busy)
    // Bumped when an operation ends: a poll started before that is stale
    property int opGen: 0

    property string pingResult: ""
    property bool isPinging: false
    property string speedResult: ""
    property bool isSpeedtesting: false

    // The overlay file's text ("" = none)
    property string overlayText: ""

    // --- The provider (provider.json, sub_meta.py) ---
    property var provider: ({})
    // `check` found nodes other than the applied ones
    property bool updateAvailable: false
    property bool isChecking: false
    readonly property string providerTitle: provider?.title ?? ""
    readonly property string providerDescription: provider?.description ?? ""
    readonly property var traffic: provider?.traffic ?? null
    readonly property real trafficUsed: traffic ? (traffic.upload ?? 0) + (traffic.download ?? 0) : 0
    readonly property real trafficTotal: traffic?.total ?? 0 // 0 = unlimited
    readonly property int expire: provider?.expire ?? 0 // unix s, 0 = never
    property real now: Date.now()
    readonly property real daysLeft: expire > 0 ? (expire * 1000 - now) / 86400000 : Infinity
    readonly property bool expired: expire > 0 && daysLeft <= 0
    // INCY's expiry banner: 3 days before
    readonly property bool expiringSoon: expire > 0 && daysLeft <= 3
    readonly property var providerRouting: provider?.routing ?? ({})
    readonly property int providerRuleCount: (providerRouting.rules ?? []).length

    readonly property bool isScanning: busy === "subscribe" || busy === "update" || busy === "unsubscribe"
    readonly property bool isRoutingBusy: busy === "routing"
    readonly property bool needsSubscription: polled && !hasSubscription && profiles.length === 0
    // Switched on (wanted up), whatever the probe says
    readonly property bool on: busy === "start" || busy === "restart" || (busy !== "stop" && (unit === "active" || unit === "activating" || unit === "reloading"))
    // inactive | connecting | active | offline | disconnecting | blocked |
    // failed | unavailable
    readonly property string status: {
        if (!installed)
            return "unavailable";
        if (busy === "stop" || unit === "deactivating")
            return "disconnecting";
        if (on) {
            const idle = busy === "" || busy === "autostart" || busy === "killswitch";
            if (unit === "active" && idle)
                return online ? "active" : stalled ? "offline" : "connecting";
            return "connecting";
        }
        if (blocking)
            return "blocked";
        return unit === "failed" ? "failed" : "inactive";
    }
    readonly property string statusText: {
        switch (status) {
        case "unavailable":
            return Translation.tr("sing-box is not installed");
        case "active":
            return Translation.tr("Connected");
        case "connecting":
            return busy === "select" ? Translation.tr("Switching node...") : Translation.tr("Connecting");
        case "offline":
            return Translation.tr("No connection");
        case "disconnecting":
            return Translation.tr("Disconnecting");
        case "blocked":
            return Translation.tr("Kill switch: traffic blocked");
        case "failed":
            return Translation.tr("Failed");
        }
        return Translation.tr("Disconnected");
    }

    readonly property var routing: routingObject()
    readonly property bool routingPending: canon(routing) !== canon(appliedRouting)
    // Only the user's part (the provider's is put in force by itself)
    readonly property bool userRoutingPending: canon(routing, false) !== canon(appliedRouting, false)
    readonly property bool pending: installed && hasSubscription && (routingPending || customPending)

    property Timer refreshTimer
    property Timer settleTimer
    property Timer stallTimer
    property Process stateProc
    property Process opProc
    property Process pingProc
    property Process speedtestProc
    property Process migrateProc
    property Process checkProc
    property Timer checkTimer
    property FileView providerFile
    property FileView overlayFile
    property Connections configConnections

    // --- Routing (Config.options.vpn.routing) ---

    // What routing.py reads ("final" is a reserved word in QML properties);
    // withProvider: the provider's part too (the Advanced editor leaves it out)
    function routingObject(withProvider) {
        const r = Config.options.vpn.routing;
        let o = {
            "final": r.defaultRoute,
            "rules": r.rules,
            "fakeip": r.fakeip,
            "remoteDns": r.remoteDns,
            "hysteria2UpMbps": r.hysteria2UpMbps,
            "hysteria2DownMbps": r.hysteria2DownMbps,
            "useProviderRules": r.useProviderRules,
            "useProviderDns": r.useProviderDns,
            "useProviderFragment": r.useProviderFragment
        };
        if (withProvider ?? true)
            o.provider = providerRouting;
        return o;
    }

    // Key-order-free JSON, defaults filled in (never applied = defaults);
    // withProvider false: the user's part only
    function canon(r, withProvider) {
        // Config's list<var> is no JS array (Array.isArray says false): a
        // JSON round trip makes plain arrays of it
        r = JSON.parse(JSON.stringify(r ?? {}));
        const sort = v => Array.isArray(v) ? v.map(sort) : (v && typeof v === "object") ? Object.keys(v).sort().reduce((o, k) => {
            o[k] = sort(v[k]);
            return o;
        }, {}) : v;
        let c = {
            "final": r?.final ?? "proxy",
            "rules": r?.rules ?? [],
            "fakeip": r?.fakeip ?? false,
            "remoteDns": r?.remoteDns ?? "8.8.8.8",
            "hysteria2UpMbps": r?.hysteria2UpMbps ?? 0,
            "hysteria2DownMbps": r?.hysteria2DownMbps ?? 0,
            "useProviderRules": r?.useProviderRules ?? true,
            "useProviderDns": r?.useProviderDns ?? true,
            "useProviderFragment": r?.useProviderFragment ?? true
        };
        if (withProvider ?? true)
            c.provider = r?.provider ?? {};
        return JSON.stringify(sort(c));
    }

    // values: one rule with a matcher per value, e.g. ("direct", "geoip",
    // ["ru"]) -> { action: "direct", match: ["geoip:ru"] }
    function addRule(action, kind, values) {
        const match = values.map(v => v.trim()).filter(v => v.length > 0).map(v => `${kind}:${v}`);
        if (match.length === 0)
            return false;
        Config.options.vpn.routing.rules = Config.options.vpn.routing.rules.concat([
            {
                "action": action,
                "match": match,
                "enabled": true
            }
        ]);
        return true;
    }

    function removeRule(index) {
        let rules = Config.options.vpn.routing.rules.slice();
        rules.splice(index, 1);
        Config.options.vpn.routing.rules = rules;
    }

    function moveRule(index, delta) {
        let rules = Config.options.vpn.routing.rules.slice();
        const to = index + delta;
        if (to < 0 || to >= rules.length)
            return;
        const rule = rules.splice(index, 1)[0];
        rules.splice(to, 0, rule);
        Config.options.vpn.routing.rules = rules;
    }

    function setRuleEnabled(index, enabled) {
        let rules = Config.options.vpn.routing.rules.slice();
        rules[index] = Object.assign({}, rules[index], {
            "enabled": enabled
        });
        Config.options.vpn.routing.rules = rules;
    }

    function clearRules() {
        Config.options.vpn.routing.rules = [];
    }

    // Routing + overlay into force; refresh = download the geosite / geoip
    // lists again even if fresh
    function applyRouting(refresh) {
        if (busy === "")
            run("routing", ["apply", JSON.stringify(routingObject())].concat(refresh ? ["refresh"] : []));
    }

    // The routing as the JSON the Advanced editor shows (routing.py's form)
    function routingJson() {
        return JSON.stringify(JSON.parse(JSON.stringify(routingObject(false))), null, 2);
    }

    // The Advanced editor's JSON into Config (Apply puts it in force):
    // "" = saved, else what is wrong. Rule contents are checked by routing.py
    // on Apply; here only what Config could not hold.
    function saveRoutingJson(text) {
        let r;
        try {
            r = JSON.parse(text);
        } catch (e) {
            return Translation.tr("Invalid JSON") + ": " + e.message;
        }
        if (!r || typeof r !== "object" || Array.isArray(r))
            return Translation.tr("The routing must be a JSON object");
        const flags = ["useProviderRules", "useProviderDns", "useProviderFragment"];
        const known = ["final", "rules", "fakeip", "remoteDns", "hysteria2UpMbps", "hysteria2DownMbps"].concat(flags);
        const unknown = Object.keys(r).filter(k => !known.includes(k));
        if (unknown.length > 0)
            return Translation.tr("Unknown key: %1").arg(unknown[0]);
        const final = r.final ?? "proxy";
        if (!["proxy", "direct", "provider"].includes(final))
            return Translation.tr("final: proxy | direct | provider");
        const rules = r.rules ?? [];
        if (!Array.isArray(rules))
            return Translation.tr("rules: must be an array");
        for (let i = 0; i < rules.length; i++) {
            const rule = rules[i];
            if (!rule || typeof rule !== "object" || Array.isArray(rule) || !["proxy", "direct", "block"].includes(rule.action))
                return Translation.tr("Rule %1: action must be proxy | direct | block").arg(i + 1);
        }
        const mbps = v => Number.isInteger(v ?? 0) && (v ?? 0) >= 0;
        if (!mbps(r.hysteria2UpMbps) || !mbps(r.hysteria2DownMbps))
            return Translation.tr("hysteria2*Mbps: a whole number >= 0");
        if (typeof (r.remoteDns ?? "") !== "string" || typeof (r.fakeip ?? false) !== "boolean")
            return Translation.tr("remoteDns: a string, fakeip: true | false");
        const badFlag = flags.find(k => typeof (r[k] ?? true) !== "boolean");
        if (badFlag)
            return Translation.tr("%1: true | false").arg(badFlag);
        const c = Config.options.vpn.routing;
        c.defaultRoute = final;
        c.rules = rules;
        c.fakeip = r.fakeip ?? false;
        c.remoteDns = r.remoteDns ?? "8.8.8.8";
        c.hysteria2UpMbps = r.hysteria2UpMbps ?? 0;
        c.hysteria2DownMbps = r.hysteria2DownMbps ?? 0;
        for (const k of flags)
            c[k] = r[k] ?? true;
        return "";
    }

    // The overlay in a terminal editor (a skeleton if there is none yet)
    function editOverlay() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.terminal} bash "$0" edit`, scriptPath]);
    }

    // --- Connection ---

    function toggle() {
        setActive(!on);
    }

    function setActive(up) {
        if (busy !== "")
            return;
        resetCommandStatus();
        if (up && needsSubscription) {
            subscriptionStatus = Translation.tr("Enter subscription URL to continue.");
            return;
        }
        run(up ? "start" : "stop", [up ? "start" : "stop"]);
    }

    function restart() {
        if (busy === "")
            run("restart", ["restart"]);
    }

    function setAutostart(enable) {
        if (busy === "" && enable !== enabled)
            run("autostart", [enable ? "enable" : "disable"]);
    }

    function setKillswitch(enable) {
        if (busy === "" && enable !== killswitch)
            run("killswitch", ["killswitch", enable ? "on" : "off"]);
    }

    // Lift a kill switch left blocking by a dead sing-box (a plain stop)
    function release() {
        if (busy === "" && blocking)
            run("stop", ["stop"]);
    }

    // The polkit rule for start / stop without a password (asks once)
    function setupPasswordless() {
        if (busy === "")
            run("setup", ["setup"]);
    }

    // tag, or a 1-based index into profiles (the old API)
    function selectProfile(tagOrIndex) {
        const tag = typeof tagOrIndex === "number" ? (profiles[tagOrIndex - 1]?.tag ?? "") : tagOrIndex;
        if (busy !== "" || tag === "" || tag === activeProfile)
            return;
        resetCommandStatus();
        selecting = tag;
        run("select", ["select", tag]);
    }

    function subscribe(url) {
        const cleanUrl = url.trim();
        if (cleanUrl.length === 0) {
            subscriptionStatus = Translation.tr("Enter subscription URL to continue.");
            return;
        }
        if (busy !== "")
            return;
        resetCommandStatus();
        subscriptionUrl = cleanUrl;
        // The URL is the provider's access token: in the environment, which
        // only this user can read, not in argv (any user's `ps` shows that)
        run("subscribe", ["subscribe"], Object.assign(subscriptionEnv(), {
            "II_VPN_URL": cleanUrl
        }));
    }

    function updateSubscription() {
        if (busy === "" && hasSubscription) {
            resetCommandStatus();
            run("update", ["update"], subscriptionEnv());
        }
    }

    // The provider's info again (traffic, expiry, its routing) without
    // applying the nodes: no root; `updateAvailable` if they changed
    function checkSubscription() {
        if (!hasSubscription || checkProc.running || busy === "subscribe" || busy === "update")
            return;
        isChecking = true;
        checkProc.environment = subscriptionEnv();
        checkProc.running = true;
    }

    // Due: the provider's update interval (24 h without one) has passed
    function checkIfDue() {
        const hours = provider?.updateInterval > 0 ? provider.updateInterval : 24;
        if ((Date.now() / 1000) - (provider?.fetched ?? 0) >= hours * 3600)
            checkSubscription();
    }

    function subscriptionEnv() {
        return Config.options.vpn.sendHwid ? {
            "II_VPN_HWID": "1"
        } : {};
    }

    function formatBytes(n) {
        const units = ["B", "KB", "MB", "GB", "TB", "PB"];
        let i = 0;
        while (n >= 1024 && i < units.length - 1) {
            n /= 1024;
            i++;
        }
        return (i >= 3 ? n.toFixed(n < 10 ? 2 : 1) : Math.round(n)) + " " + units[i];
    }

    // "5.00 GB / 50.0 GB", "5.00 GB / ∞"; "" = the provider says nothing
    readonly property string trafficText: traffic ? `${formatBytes(trafficUsed)} / ${trafficTotal > 0 ? formatBytes(trafficTotal) : "∞"}` : ""
    readonly property string expiryText: {
        if (expire <= 0)
            return "";
        const date = new Date(expire * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat);
        if (expired)
            return Translation.tr("Expired %1").arg(date);
        return Translation.tr("Until %1 (%2 d.)").arg(date).arg(Math.max(0, Math.floor(daysLeft)));
    }

    // A link the provider sent (support, announce, banner button)
    function openProviderLink(url) {
        if (/^(https?|tg|mailto):/.test(url ?? ""))
            Qt.openUrlExternally(url);
    }

    // A changed provider routing (a `check`) into force by itself: only
    // password-free (`setup` done), with nothing of the user's pending (an
    // apply takes all of it), once per version (a failed one is shown as
    // pending, not retried in a loop)
    property string autoAppliedProvider: ""
    function autoApplyProvider() {
        const key = canon(routing);
        if (!polled || !installed || !hasSubscription || busy !== "" || !passwordless || !routingPending || userRoutingPending || customPending || key === autoAppliedProvider)
            return;
        autoAppliedProvider = key;
        run("routing", ["apply", JSON.stringify(routingObject())]);
    }

    function deleteSubscription() {
        if (busy !== "")
            return;
        resetCommandStatus();
        subscriptionStatus = Translation.tr("Deleting subscription...");
        run("unsubscribe", ["unsubscribe"]);
    }

    function openLogs() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.terminal} journalctl -f -n 200 -u sing-box -u xray`]);
    }

    function testPing() {
        if (isPinging)
            return;
        pingResult = "";
        isPinging = true;
        pingProc.running = true;
    }

    function testSpeed() {
        if (isSpeedtesting)
            return;
        speedResult = "";
        isSpeedtesting = true;
        speedtestProc.running = true;
    }

    function refresh() {
        if (stateProc.running)
            return;
        stateProc.gen = opGen;
        stateProc.running = true;
    }

    // --- Internals ---

    function notify(message) {
        if (message.length > 0)
            Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "network-vpn-symbolic", Translation.tr("VPN"), message]);
    }

    function resetCommandStatus() {
        lastError = "";
        missingDependency = "";
        subscriptionStatus = "";
    }

    function run(kind, args, env) {
        busy = kind;
        lastError = "";
        opProc.kind = kind;
        // Per run: an earlier one's variables must not stay set
        opProc.environment = env ?? {};
        opProc.command = ["bash", scriptPath].concat(args);
        opProc.running = true;
    }

    // The old setup's custom rules / subscription URL, once
    function migrate() {
        if (!Config.options.vpn.migrated && !migrateProc.running)
            migrateProc.running = true;
    }

    Component.onCompleted: {
        // FileView does not create the overlay's directory when saving
        Quickshell.execDetached(["mkdir", "-p", FileUtils.parentDirectory(overlayPath)]);
        refresh();
        refreshTimer.start();
        if (Config.ready)
            migrate();
        // After the first poll (hasSubscription known)
        Qt.callLater(() => firstCheck.start());
    }

    property Timer firstCheck: Timer {
        interval: 30000
        onTriggered: root.checkIfDue()
    }

    configConnections: Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                root.migrate();
        }
    }

    onOnlineChanged: if (online)
        stalled = false
    onUnitChanged: if (unit !== "active")
        stalled = false
    onBlockingChanged: if (blocking)
        notify(Translation.tr("VPN is down, the kill switch blocks traffic"))

    refreshTimer: Timer {
        interval: (root.status === "connecting" || root.status === "disconnecting" || root.settleTimer.running) ? 1000 : 5000
        repeat: true
        onTriggered: root.refresh()
    }

    settleTimer: Timer {
        interval: 8000
    }

    stallTimer: Timer {
        interval: 12000
        // Not while a root half restarts the units (the probe is not held then)
        running: root.unit === "active" && !root.online && root.busy === "" && !root.restarting && !root.stalled
        onTriggered: {
            root.stalled = true;
            root.notify(Translation.tr("No connection through the VPN"));
        }
    }

    stateProc: Process {
        property int gen: 0
        command: ["bash", root.scriptPath, "state"]
        onExited: if (stateProc.gen !== root.opGen)
            Qt.callLater(root.refresh)
        stdout: StdioCollector {
            onStreamFinished: {
                if (stateProc.gen !== root.opGen)
                    return;
                try {
                    const s = JSON.parse(text);
                    root.installed = s.installed;
                    root.restarting = s.restarting ?? false;
                    if (!root.restarting)
                        root.unit = s.unit || "inactive";
                    root.enabled = s.enabled ?? false;
                    root.online = s.online ?? false;
                    root.activeProfile = s.profile ?? "";
                    const profiles = (s.profiles ?? []).map((p, i) => Object.assign({}, p, {
                            "name": p.tag,
                            "isActive": p.tag === s.profile,
                            "index": i + 1
                        }));
                    if (JSON.stringify(profiles) !== JSON.stringify(root.profiles))
                        root.profiles = profiles;
                    root.hasSubscription = s.subscription ?? false;
                    root.killswitch = s.killswitch ?? false;
                    if (!root.holdBlocking)
                        root.blocking = s.blocking ?? false;
                    root.passwordless = s.passwordless ?? false;
                    if (root.canon(s.routing) !== root.canon(root.appliedRouting))
                        root.appliedRouting = s.routing ?? {};
                    root.customPending = s.customPending ?? false;
                } catch (e) {
                    console.warn("[Vpn] bad state:", text);
                }
                root.polled = true;
                Qt.callLater(root.autoApplyProvider);
            }
        }
    }

    opProc: Process {
        property string kind: ""
        stdout: StdioCollector {
            id: opOutput
        }
        onExited: (exitCode, exitStatus) => {
            const lines = opOutput.text.trim().split("\n");
            const err = lines.find(l => l.startsWith("ERR:"));
            // sing-box was not running: saved, not tried (restart_checked)
            const unchecked = lines.some(l => l.startsWith("UNCHECKED:"));
            // Nodes the import dropped (xray_split.py): "SKIPPED:tag<TAB>why"
            const skipped = lines.filter(l => l.startsWith("SKIPPED:")).map(l => l.substring(8));
            const kind = opProc.kind;
            root.busy = "";
            root.selecting = "";
            root.stalled = false;
            root.opGen++;
            if (exitCode === 0) {
                if (kind === "subscribe" || kind === "update") {
                    if (skipped.length > 0)
                        console.info("[Vpn] skipped nodes:", skipped.join("; ").replace(/\t/g, ": "));
                    let msg = unchecked ? Translation.tr("Subscription saved, applies on next VPN start") : Translation.tr("Subscription applied successfully");
                    if (skipped.length > 0)
                        msg += " · " + Translation.tr("nodes skipped: %1").arg(skipped.length);
                    root.subscriptionStatus = msg;
                    root.updateAvailable = false;
                } else if (kind === "routing" && unchecked) {
                    root.notify(Translation.tr("Routing saved, applies on next VPN start"));
                } else if (kind === "unsubscribe") {
                    root.updateAvailable = false;
                    root.subscriptionUrl = "";
                    root.subscriptionStatus = Translation.tr("Subscription deleted and profiles cleared");
                }
            } else if (!err && (exitCode === 126 || exitCode === 127)) {
                // pkexec: 126 = the password prompt was dismissed; 127 = not
                // authorized (some agents say so for a dismissed prompt too):
                // shown, no notification
                root.lastError = exitCode === 127 ? Translation.tr("Not authorized (polkit)") : "";
                root.subscriptionStatus = "";
            } else {
                root.lastError = err ? err.substring(4).trim() : Translation.tr("Failed");
                if (root.lastError.startsWith("Can't find dependency:")) {
                    root.missingDependency = root.lastError.substring(22).trim();
                    root.notify(Translation.tr("Install missing dependency") + ": " + root.missingDependency);
                } else if (kind === "subscribe" || kind === "update" || kind === "unsubscribe") {
                    root.subscriptionStatus = root.lastError;
                    root.notify(root.lastError);
                } else {
                    root.notify(root.lastError);
                }
            }
            root.refresh();
            root.settleTimer.restart();
        }
    }

    migrateProc: Process {
        command: ["bash", root.scriptPath, "migrate"]
        stdout: StdioCollector {
            onStreamFinished: {
                let m;
                try {
                    m = JSON.parse(text);
                } catch (e) {
                    console.warn("[Vpn] migration failed:", text);
                    return;
                }
                const r = m.routing;
                if (r && Config.options.vpn.routing.rules.length === 0) {
                    const c = Config.options.vpn.routing;
                    c.rules = r.rules ?? [];
                    c.fakeip = r.fakeip ?? false;
                    c.remoteDns = r.remoteDns ?? "8.8.8.8";
                    c.hysteria2UpMbps = r.hysteria2UpMbps ?? 0;
                    c.hysteria2DownMbps = r.hysteria2DownMbps ?? 0;
                }
                if (m.overlay && Object.keys(m.overlay).length > 0 && root.overlayText.trim().length === 0)
                    root.overlayFile.setText(JSON.stringify(m.overlay, null, 2) + "\n");
                Config.options.vpn.migrated = true;
                root.refresh();
            }
        }
    }

    overlayFile: FileView {
        path: root.overlayPath
        watchChanges: true
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: root.overlayText = text()
        onLoadFailed: root.overlayText = ""
        onSaved: root.refresh()
    }

    checkProc: Process {
        command: ["bash", root.scriptPath, "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.isChecking = false;
                const res = text.trim();
                if (res.includes("OK:changed")) {
                    if (!root.updateAvailable)
                        console.info("[Vpn] the subscription's nodes changed");
                    root.updateAvailable = true;
                } else if (res.includes("OK:same")) {
                    root.updateAvailable = false;
                } else {
                    console.warn("[Vpn] subscription check failed:", res);
                }
            }
        }
    }

    // Every 10 min: a check if one is due, and the clock for the expiry
    checkTimer: Timer {
        interval: 600000
        repeat: true
        running: true
        onTriggered: {
            root.now = Date.now();
            root.checkIfDue();
        }
    }

    providerFile: FileView {
        path: root.providerPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let p = {};
            try {
                p = JSON.parse(text());
            } catch (e) {
                console.warn("[Vpn] bad provider.json");
            }
            root.provider = (p && typeof p === "object") ? p : {};
            root.now = Date.now();
            if (root.expiringSoon && root.notifiedExpire !== root.expire) {
                root.notifiedExpire = root.expire;
                root.notify(root.expired ? Translation.tr("The VPN subscription has expired") : Translation.tr("The VPN subscription expires in %1 d.").arg(Math.max(0, Math.ceil(root.daysLeft))));
            }
            Qt.callLater(root.autoApplyProvider);
        }
        onLoadFailed: root.provider = {}
    }
    property int notifiedExpire: 0

    pingProc: Process {
        command: ["bash", root.scriptPath, "ping"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/OK:(\d+)/);
                root.pingResult = m ? `${m[1]} ms` : Translation.tr("Error");
                root.isPinging = false;
            }
        }
    }

    speedtestProc: Process {
        command: ["bash", root.scriptPath, "speedtest"]
        stdout: StdioCollector {
            onStreamFinished: {
                const res = text.trim();
                if (res === "ERR_MISSING") {
                    root.speedResult = Translation.tr("Install speedtest-cli");
                } else {
                    const num = re => (res.match(re) ?? [])[1] ?? "";
                    const down = num(/Download:\s*([\d.]+)/);
                    const up = num(/Upload:\s*([\d.]+)/);
                    root.speedResult = (down || up) ? `↓${down} ↑${up} Mb/s` : Translation.tr("Error");
                }
                root.isSpeedtesting = false;
            }
        }
    }
}
