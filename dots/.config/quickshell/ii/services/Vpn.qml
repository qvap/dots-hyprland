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
    property string scriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/vpn/virtualprivatenetwork.sh`

    property Timer refreshTimer
    property Process statusProc
    property Process profilesProc
    property Process subscribeProc
    property Process updateSubProc
    property Process startProc
    property Process stopProc
    property Process selectProc
    property Process pingProc
    property Process speedtestProc

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

    function toggle() {
        if (status === "active" || status === "connecting") {
            status = "inactive";
            stopProc.running = true;
        } else {
            status = "connecting";
            startProc.running = true;
        }
        refreshTimer.restart();
    }

    function selectProfile(index) {
        selectProc.profileIndex = index;
        selectProc.running = true;
        refreshTimer.restart();
    }

    function subscribe(url) {
        isScanning = true;
        subscribeProc.command = ["bash", scriptPath, "subscribe", url];
        subscribeProc.running = true;
    }

    function updateSubscription() {
        isScanning = true;
        updateSubProc.command = ["bash", scriptPath, "update-sub"];
        updateSubProc.running = true;
    }

    function refresh() {
        statusProc.running = true;
        profilesProc.running = true;
    }

    Component.onCompleted: {
        refresh();
        refreshTimer.start();
    }

    startProc: Process {
        command: ["bash", root.scriptPath, "start"]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
            if (exitCode === 0)
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "network-vpn-symbolic", Translation.tr("VPN"), Translation.tr("Connection established")]);
            else
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "network-vpn-symbolic", Translation.tr("VPN"), Translation.tr("Failed to connect")]);
        }
    }

    stopProc: Process {
        command: ["bash", root.scriptPath, "stop"]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
            if (exitCode === 0)
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "network-vpn-symbolic", Translation.tr("VPN"), Translation.tr("Disconnected")]);
        }
    }

    selectProc: Process {
        property int profileIndex: 1

        command: ["bash", root.scriptPath, "select", profileIndex.toString()]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
            if (exitCode === 0)
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "network-vpn-symbolic", Translation.tr("VPN"), Translation.tr("Node changed")]);
            else
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "network-vpn-symbolic", Translation.tr("VPN"), Translation.tr("Failed to change node")]);
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
            }
        }
    }

    profilesProc: Process {
        command: ["bash", root.scriptPath, "select"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split('\n');
                let _profiles = [];
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i];
                    if (line.startsWith("PROFILE_ITEM:") || line.startsWith("PROFILE_ACTIVE:")) {
                        const parts = line.split(':');
                        if (parts.length >= 3)
                            _profiles.push({
                                "isActive": parts[0] === "PROFILE_ACTIVE",
                                "index": parseInt(parts[1]),
                                "name": parts.slice(2).join(':').trim()
                            });
                    }
                }
                root.profiles = _profiles;
            }
        }
    }

    subscribeProc: Process {
        onExited: (exitCode, exitStatus) => {
            root.isScanning = false;
            root.refresh();
            if (exitCode === 0)
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "network-vpn-symbolic", Translation.tr("VPN"), Translation.tr("Subscription loaded")]);
            else
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "network-vpn-symbolic", Translation.tr("VPN"), Translation.tr("Failed to load subscription")]);
        }
    }

    updateSubProc: Process {
        onExited: (exitCode, exitStatus) => {
            root.isScanning = false;
            root.refresh();
            if (exitCode === 0)
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "network-vpn-symbolic", Translation.tr("VPN"), Translation.tr("Subscription updated")]);
            else
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-i", "network-vpn-symbolic", Translation.tr("VPN"), Translation.tr("Failed to update subscription")]);
        }
    }

    pingProc: Process {
        command: ["bash", "-c", "curl -s -o /dev/null -w '%{time_total}' -m 5 http://cp.cloudflare.com/generate_204 || echo 'ERR'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let res = text.trim();
                if (res === "ERR" || res === "") {
                    root.pingResult = Translation.tr("Error");
                } else {
                    let ms = Math.round(parseFloat(res) * 1000);
                    root.pingResult = ms + " ms";
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
}
