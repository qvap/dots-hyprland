pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import qs.services
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

/* Wraparound for virtualprivatenetwork bash-script
*/

QtObject {
    id: root

    property string status: "inactive"
    property string activeProfile: ""
    property var profiles: []
    property bool isScanning: false
    property string pingResult: ""
    property bool isPinging: false
    property string speedResult: ""
    property bool isSpeedtesting: false
    property string routingRulesPath: "/etc/illogical-impulse/sing-box/custom_rules.json"
    property var routingRules: []
    property var routingRuleItems: []
    property string routingRulesRaw: "{\n  \"rules\": []\n}"
    property string routingStatus: ""
    property bool isRoutingBusy: false
    property bool needsSubscription: false
    property string subscriptionUrl: ""
    property string subscriptionStatus: ""
    property string lastError: ""
    property string missingDependency: ""
    property string scriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/vpn/virtualprivatenetwork.sh`

    property Timer refreshTimer
    property Process statusProc
    property Process profilesProc
    property Process subscribeProc
    property Process updateSubProc
    property Process deleteSubProc
    property Process startProc
    property Process stopProc
    property Process selectProc
    property Process pingProc
    property Process speedtestProc
    property Process rulesPathProc
    property Process rulesShowProc
    property Process rulesCommandProc

    function testSpeed() {
        if (isSpeedtesting)
            return;
        speedResult = "";
        isSpeedtesting = true;
        speedtestProc.running = true;
    }

    function testPing() {
        if (isPinging)
            return;
        pingResult = "";
        isPinging = true;
        pingProc.running = true;
    }

    function notify(message) {
        if (message.length > 0)
            Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "network-vpn-symbolic", Translation.tr("VPN"), message]);
    }

    function resetCommandStatus() {
        lastError = "";
        missingDependency = "";
        subscriptionStatus = "";
    }

    function setSubscriptionAvailable() {
        needsSubscription = false;
        if (subscriptionStatus === Translation.tr("Enter subscription URL to continue.") || subscriptionStatus === Translation.tr("Subscription URL is required before VPN can start."))
            subscriptionStatus = "";
    }

    function handleScriptOutput(text) {
        const lines = text.trim().split('\n');
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (line.length === 0)
                continue;
            if (line.startsWith("ERR_NEEDS_SUBSCRIPTION:")) {
                needsSubscription = true;
                subscriptionStatus = Translation.tr("Subscription URL is required before VPN can start.");
                lastError = subscriptionStatus;
            } else if (line.startsWith("ERR:")) {
                const message = line.substring(4).trim();
                lastError = message;
                if (message.startsWith("Can't find dependency:")) {
                    missingDependency = message.substring(22).trim();
                    subscriptionStatus = Translation.tr("Install missing dependency") + ": " + missingDependency;
                }
            } else if (line.startsWith("OK:")) {
                const message = line.substring(3).trim();
                if (message.includes("Subscription applied")) {
                    setSubscriptionAvailable();
                    subscriptionStatus = Translation.tr("Subscription applied successfully");
                } else if (message.includes("Subscription deleted")) {
                    needsSubscription = true;
                    subscriptionUrl = "";
                    activeProfile = "";
                    profiles = [];
                    status = "inactive";
                    subscriptionStatus = Translation.tr("Subscription deleted and profiles cleared");
                }
            }
        }
    }

    function toggle() {
        resetCommandStatus();
        if (status === "active" || status === "connecting") {
            status = "inactive";
            stopProc.running = true;
        } else if (needsSubscription) {
            subscriptionStatus = Translation.tr("Enter subscription URL to continue.");
        } else {
            status = "connecting";
            startProc.running = true;
        }
        refreshTimer.restart();
    }

    function selectProfile(index) {
        resetCommandStatus();
        selectProc.profileIndex = index;
        selectProc.running = true;
        refreshTimer.restart();
    }

    function subscribe(url) {
        const cleanUrl = url.trim();
        if (cleanUrl.length === 0) {
            needsSubscription = true;
            subscriptionStatus = Translation.tr("Enter subscription URL to continue.");
            return;
        }
        resetCommandStatus();
        subscriptionUrl = cleanUrl;
        isScanning = true;
        subscribeProc.command = ["bash", scriptPath, "subscribe", cleanUrl];
        subscribeProc.running = true;
    }

    function updateSubscription() {
        resetCommandStatus();
        isScanning = true;
        updateSubProc.command = ["bash", scriptPath, "update-sub"];
        updateSubProc.running = true;
    }

    function deleteSubscription() {
        if (isScanning)
            return;
        resetCommandStatus();
        subscriptionStatus = Translation.tr("Deleting subscription...");
        isScanning = true;
        deleteSubProc.command = ["bash", scriptPath, "delete-sub"];
        deleteSubProc.running = true;
    }

    function refreshRules() {
        rulesPathProc.running = true;
        rulesShowProc.running = true;
    }

    function addRoutingRule(outbound, ruleType, values) {
        if (isRoutingBusy)
            return;
        const cleanValues = values.filter(value => value.trim().length > 0);
        if (cleanValues.length === 0) {
            routingStatus = Translation.tr("Add at least one value");
            return;
        }
        isRoutingBusy = true;
        routingStatus = Translation.tr("Adding rule...");
        rulesCommandProc.command = ["bash", scriptPath, "rules", "add", outbound, ruleType].concat(cleanValues);
        rulesCommandProc.running = true;
    }

    function setRoutingRules(json) {
        if (isRoutingBusy)
            return;
        try {
            JSON.parse(json);
        } catch (e) {
            routingStatus = Translation.tr("Invalid JSON");
            return;
        }
        isRoutingBusy = true;
        routingStatus = Translation.tr("Saving rules...");
        rulesCommandProc.command = ["bash", scriptPath, "rules", "set", json];
        rulesCommandProc.running = true;
    }

    function buildRoutingRuleItems(rules) {
        const keys = ["domain", "domain_suffix", "domain_keyword", "domain_regex", "geoip", "geosite", "ip_cidr"];
        let items = [];
        for (let ruleIndex = 0; ruleIndex < rules.length; ruleIndex++) {
            const rule = rules[ruleIndex];
            if (!rule)
                continue;
            for (let keyIndex = 0; keyIndex < keys.length; keyIndex++) {
                const ruleType = keys[keyIndex];
                const values = rule[ruleType];
                if (!values || values.length === undefined)
                    continue;
                for (let valueIndex = 0; valueIndex < values.length; valueIndex++) {
                    items.push({
                        "ruleIndex": ruleIndex,
                        "ruleType": ruleType,
                        "value": values[valueIndex],
                        "action": rule.action || "route",
                        "outbound": rule.action === "reject" ? "block" : (rule.outbound || "proxy")
                    });
                }
            }
        }
        return items;
    }

    function removeRoutingRule(index) {
        if (isRoutingBusy)
            return;
        isRoutingBusy = true;
        routingStatus = Translation.tr("Removing rule...");
        rulesCommandProc.command = ["bash", scriptPath, "rules", "remove", index.toString()];
        rulesCommandProc.running = true;
    }

    function removeRoutingRuleItem(item) {
        if (isRoutingBusy || !item)
            return;
        isRoutingBusy = true;
        routingStatus = Translation.tr("Removing rule...");
        rulesCommandProc.command = ["bash", scriptPath, "rules", "remove", item.ruleIndex.toString(), item.ruleType, item.value.toString()];
        rulesCommandProc.running = true;
    }

    function clearRoutingRules() {
        if (isRoutingBusy)
            return;
        isRoutingBusy = true;
        routingStatus = Translation.tr("Clearing rules...");
        rulesCommandProc.command = ["bash", scriptPath, "rules", "clear"];
        rulesCommandProc.running = true;
    }

    function applyRoutingRules() {
        if (isRoutingBusy)
            return;
        isRoutingBusy = true;
        routingStatus = Translation.tr("Applying rules...");
        rulesCommandProc.command = ["bash", scriptPath, "rules", "apply"];
        rulesCommandProc.running = true;
    }

    function refresh() {
        statusProc.running = true;
        profilesProc.running = true;
    }

    Component.onCompleted: {
        refresh();
        refreshRules();
        refreshTimer.start();
    }

    startProc: Process {
        command: ["bash", root.scriptPath, "start"]
        stdout: StdioCollector {
            onStreamFinished: root.handleScriptOutput(text)
        }
        onExited: (exitCode, exitStatus) => {
            root.refresh();
            if (exitCode !== 0) {
                if (root.missingDependency.length > 0)
                    root.notify(Translation.tr("Install missing dependency") + ": " + root.missingDependency);
                else if (root.needsSubscription)
                    root.subscriptionStatus = Translation.tr("Enter subscription URL to continue.");
                else
                    root.notify(root.lastError.length > 0 ? root.lastError : Translation.tr("Failed to connect"));
            }
        }
    }

    stopProc: Process {
        command: ["bash", root.scriptPath, "stop"]
    }

    selectProc: Process {
        property int profileIndex: 1

        command: ["bash", root.scriptPath, "select", profileIndex.toString()]
        stdout: StdioCollector {
            onStreamFinished: root.handleScriptOutput(text)
        }
        onExited: (exitCode, exitStatus) => {
            root.refresh();
            if (exitCode !== 0 && !root.needsSubscription)
                root.notify(root.lastError.length > 0 ? root.lastError : Translation.tr("Failed to change node"));
        }
    }

    refreshTimer: Timer {
        interval: 5000
        repeat: true
        onTriggered: refresh()
    }

    statusProc: Process {
        command: ["bash", root.scriptPath, "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split('\n');
                let _status = root.status;
                let _profile = root.activeProfile;
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i].startsWith("STATUS:"))
                        _status = lines[i].substring(7).trim();
                    else if (lines[i].startsWith("PROFILE:"))
                        _profile = lines[i].substring(8).trim();
                }
                root.status = _status;
                root.activeProfile = _profile;
                if (_profile.length > 0 && _profile !== "None")
                    root.setSubscriptionAvailable();
            }
        }
    }

    profilesProc: Process {
        command: ["bash", root.scriptPath, "select"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.handleScriptOutput(text);
                const lines = text.trim().split('\n');
                let _profiles = [];
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i];
                    if (line.startsWith("PROFILE_ITEM:") || line.startsWith("PROFILE_ACTIVE:")) {
                        const parts = line.split(':');
                        if (parts.length >= 4)
                            _profiles.push({
                                "isActive": parts[0] === "PROFILE_ACTIVE",
                                "index": parseInt(parts[1]),
                                "type": parts[2].trim(),
                                "name": parts.slice(3).join(':').trim()
                            });
                    }
                }
                root.profiles = _profiles;
                if (_profiles.length > 0)
                    root.setSubscriptionAvailable();
            }
        }
    }

    subscribeProc: Process {
        stdout: StdioCollector {
            onStreamFinished: root.handleScriptOutput(text)
        }
        onExited: (exitCode, exitStatus) => {
            root.isScanning = false;
            root.refresh();
            if (exitCode === 0) {
                root.setSubscriptionAvailable();
                root.subscriptionStatus = Translation.tr("Subscription applied successfully");
            } else if (root.missingDependency.length > 0) {
                root.notify(Translation.tr("Install missing dependency") + ": " + root.missingDependency);
            } else {
                root.notify(root.lastError.length > 0 ? root.lastError : Translation.tr("Failed to load subscription"));
            }
        }
    }

    updateSubProc: Process {
        stdout: StdioCollector {
            onStreamFinished: root.handleScriptOutput(text)
        }
        onExited: (exitCode, exitStatus) => {
            root.isScanning = false;
            root.refresh();
            if (exitCode === 0) {
                root.setSubscriptionAvailable();
                root.subscriptionStatus = Translation.tr("Subscription applied successfully");
            } else if (root.needsSubscription) {
                root.subscriptionStatus = Translation.tr("Enter subscription URL to continue.");
            } else if (root.missingDependency.length > 0) {
                root.notify(Translation.tr("Install missing dependency") + ": " + root.missingDependency);
            } else {
                root.notify(root.lastError.length > 0 ? root.lastError : Translation.tr("Failed to update subscription"));
            }
        }
    }

    deleteSubProc: Process {
        stdout: StdioCollector {
            onStreamFinished: root.handleScriptOutput(text)
        }
        onExited: (exitCode, exitStatus) => {
            root.isScanning = false;
            root.refresh();
            if (exitCode === 0) {
                root.needsSubscription = true;
                root.subscriptionUrl = "";
                root.activeProfile = "";
                root.profiles = [];
                root.status = "inactive";
                root.subscriptionStatus = Translation.tr("Subscription deleted and profiles cleared");
            } else if (root.missingDependency.length > 0) {
                root.notify(Translation.tr("Install missing dependency") + ": " + root.missingDependency);
            } else {
                root.notify(root.lastError.length > 0 ? root.lastError : Translation.tr("Failed to delete subscription"));
            }
        }
    }

    pingProc: Process {
        command: ["bash", root.scriptPath, "ping"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split('\n');
                root.pingResult = Translation.tr("Error");
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (line.startsWith("OK:")) {
                        root.pingResult = line.substring(3).trim();
                        break;
                    }
                    if (line.startsWith("ERR:")) {
                        root.pingResult = Translation.tr("Error");
                    }
                }
                root.isPinging = false;
            }
        }
    }

    speedtestProc: Process {
        command: ["bash", root.scriptPath, "speedtest"]
        stdout: StdioCollector {
            onStreamFinished: {
                let res = text.trim();
                if (res === "ERR_MISSING") {
                    root.speedResult = Translation.tr("Install speedtest-cli");
                } else if (res === "" || res === "ERR_FAILED" || res.includes("Cannot")) {
                    root.speedResult = Translation.tr("Error");
                } else {
                    let lines = res.split('\n');
                    let down = "0", up = "0";
                    for (let i = 0; i < lines.length; i++) {
                        let line = lines[i].trim();
                        if (line.startsWith("Download:"))
                            down = line.substring(9).replace("Mbit/s", "Mb/s").trim();
                        if (line.startsWith("Upload:"))
                            up = line.substring(7).replace("Mbit/s", "Mb/s").trim();
                    }
                    if (down === "0" && up === "0") {
                        root.speedResult = Translation.tr("Error");
                    } else {
                        root.speedResult = "↓" + down + " ↑" + up;
                    }
                }
                root.isSpeedtesting = false;
            }
        }
    }

    rulesPathProc: Process {
        command: ["bash", root.scriptPath, "rules", "path"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split('\n');
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i].startsWith("RULES_PATH:")) {
                        root.routingRulesPath = lines[i].substring(11).trim();
                        break;
                    }
                }
            }
        }
    }

    rulesShowProc: Process {
        command: ["bash", root.scriptPath, "rules", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim().length > 0 ? text.trim() : '{"rules":[]}';
                root.routingRulesRaw = raw;
                try {
                    const parsed = JSON.parse(raw);
                    root.routingRules = parsed.rules || [];
                    root.routingRuleItems = root.buildRoutingRuleItems(root.routingRules);
                    if (root.routingStatus === Translation.tr("Invalid JSON"))
                        root.routingStatus = "";
                } catch (e) {
                    root.routingRules = [];
                    root.routingRuleItems = [];
                    root.routingStatus = Translation.tr("Failed to parse routing rules");
                }
            }
        }
    }

    rulesCommandProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split('\n');
                let lastMessage = "";
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (line.startsWith("OK:"))
                        lastMessage = line.substring(3).trim();
                    else if (line.startsWith("ERR:"))
                        lastMessage = line.substring(4).trim();
                    else if (line.startsWith("WAIT:"))
                        lastMessage = line.substring(5).trim();
                }
                if (lastMessage.length > 0)
                    root.routingStatus = lastMessage;
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.isRoutingBusy = false;
            root.refreshRules();
            root.refresh();
            if (exitCode !== 0) {
                if (root.routingStatus.length === 0)
                    root.routingStatus = Translation.tr("Routing command failed");
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "network-vpn-symbolic", Translation.tr("VPN Routing"), root.routingStatus]);
            } else if (root.routingStatus.length === 0) {
                root.routingStatus = Translation.tr("Done");
            }
        }
    }
}
