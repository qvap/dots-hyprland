pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Browses Wallpaper Engine "Video" wallpapers on the Steam Workshop and downloads
 * them with steamcmd (scripts/wallpaperEngine/download.py) into the animated
 * wallpapers folder, then applies them through Wallpapers.
 */
Singleton {
    id: root

    readonly property int appId: 431960
    readonly property int pageSize: 30
    readonly property var options: Config.options.wallpaperSelector.wallpaperEngine
    readonly property string downloadScriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/wallpaperEngine/download.py`
    readonly property string loginQmlPath: FileUtils.trimFileProtocol(Quickshell.shellPath("steamLogin.qml"))
    readonly property string loginLockPath: `${FileUtils.trimFileProtocol(Directories.cache)}/steamLogin.lock`
    readonly property string downloadDir: root.expandPath(root.options.downloadDir) || FileUtils.trimFileProtocol(`${Directories.pictures}/Wallpapers/Animated`)
    readonly property bool usingApi: root.options.apiKey.length > 0
    property string userAgent: Config.options?.networking?.userAgent || "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

    // Browsing
    property var items: []
    property string searchQuery: ""
    property string sort: "trend" // "trend", "top", "recent"
    property int page: 0
    property bool hasMore: true
    property bool loading: false
    property string errorMessage: ""
    property int requestSerial: 0
    property bool loaded: false

    // Downloads
    property var downloadedFiles: ({}) // workshop id -> absolute path
    property list<string> queue: []
    property string currentDownload: ""
    property string downloadStatus: "" // "login", "confirm", "downloading", "copying"
    property real downloadProgress: 0
    property string applyAfterDownload: "" // Only the last clicked item gets applied
    property string lastError: ""
    property bool loginRequired: false
    property list<string> pendingLogin: [] // Items waiting for a Steam sign-in

    readonly property var sortModes: ({
        "trend": { api: 3, browse: "trend" },
        "top": { api: 0, browse: "toprated" },
        "recent": { api: 1, browse: "mostrecent" }
    })

    function load() {} // For forcing initialization

    // "~/x" and relative paths are taken from the home folder; nothing here runs through a shell
    function expandPath(path) {
        const trimmed = FileUtils.trimFileProtocol(path.trim());
        if (trimmed.length === 0) return "";
        const home = FileUtils.trimFileProtocol(Directories.home).replace(/\/+$/, "");
        if (trimmed === "~") return home;
        if (trimmed.startsWith("~/")) return home + trimmed.slice(1);
        if (!trimmed.startsWith("/")) return `${home}/${trimmed}`;
        return trimmed;
    }

    function ensureLoaded() {
        root.refreshDownloaded(); // Files may have been deleted since the tab was last open
        if (root.loaded) return;
        root.loaded = true;
        root.refresh();
    }

    function refresh() {
        root.refreshDownloaded();
        root.requestSerial++; // Drop the response of a request for the previous query
        root.loading = false;
        root.items = [];
        root.page = 0;
        root.hasMore = true;
        root.loadMore();
    }

    function loadMore() {
        if (root.loading || !root.hasMore) return;
        root.fetchPage(root.page + 1);
    }

    onSearchQueryChanged: if (root.loaded) searchDebounce.restart()
    onSortChanged: if (root.loaded) root.refresh()
    onUsingApiChanged: if (root.loaded) root.refresh()
    Connections {
        target: root.options
        function onShowMatureChanged() {
            if (root.loaded) root.refresh();
        }
        function onDownloadDirChanged() {
            if (root.loaded) root.refreshDownloaded();
        }
    }

    Timer {
        id: searchDebounce
        interval: 500
        onTriggered: root.refresh()
    }

    // Requests
    function fetchPage(pageNumber) {
        const serial = ++root.requestSerial;
        root.loading = true;
        root.errorMessage = "";
        const finish = (results, more, error = "") => {
            if (serial !== root.requestSerial) return;
            root.loading = false;
            if (error.length > 0) {
                root.errorMessage = error;
                root.hasMore = false;
                return;
            }
            const known = new Set(root.items.map(item => item.id));
            const fresh = results.map(root.mapItem).filter(item => item && !known.has(item.id));
            root.items = [...root.items, ...fresh];
            root.page = pageNumber;
            root.hasMore = more && results.length > 0;
        };
        if (root.usingApi) root.queryApi(pageNumber, finish);
        else root.scrapeBrowsePage(pageNumber, finish);
    }

    function requiredTags() {
        return root.options.showMature ? ["Video"] : ["Video", "Everyone"];
    }

    function request(method, url, body, callback) {
        const xhr = new XMLHttpRequest();
        xhr.open(method, url);
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            callback(xhr.status, xhr.responseText);
        };
        if (body) xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        try {
            xhr.setRequestHeader("User-Agent", root.userAgent);
        } catch (e) {}
        xhr.send(body ?? null);
    }

    function queryApi(pageNumber, finish) {
        const params = [
            `key=${encodeURIComponent(root.options.apiKey)}`,
            `appid=${root.appId}`,
            `query_type=${root.sortModes[root.sort].api}`,
            `page=${pageNumber}`,
            `numperpage=${root.pageSize}`,
            "match_all_tags=true",
            "return_tags=true",
            ...root.requiredTags().map((tag, i) => `requiredtags[${i}]=${encodeURIComponent(tag)}`)
        ];
        if (root.sort === "trend") params.push("days=7");
        if (root.searchQuery.trim().length > 0) params.push(`search_text=${encodeURIComponent(root.searchQuery.trim())}`);
        root.request("GET", `https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/?${params.join("&")}`, null, (status, text) => {
            if (status === 401 || status === 403) return finish([], false, Translation.tr("Steam rejected the Web API key"));
            if (status !== 200) return finish([], false, Translation.tr("Workshop request failed (HTTP %1)").arg(status));
            try {
                const response = JSON.parse(text).response;
                const results = response.publishedfiledetails ?? [];
                finish(results, pageNumber * root.pageSize < (response.total ?? 0));
            } catch (e) {
                finish([], false, Translation.tr("Could not parse the Workshop response"));
            }
        });
    }

    function scrapeBrowsePage(pageNumber, finish) {
        const sortName = root.sortModes[root.sort].browse;
        const params = [
            `appid=${root.appId}`,
            `browsesort=${sortName}`,
            `actualsort=${sortName}`,
            "section=readytouseitems",
            `p=${pageNumber}`,
            ...root.requiredTags().map(tag => `requiredtags%5B%5D=${encodeURIComponent(tag)}`)
        ];
        if (root.sort === "trend") params.push("days=7");
        if (root.searchQuery.trim().length > 0) params.push(`searchtext=${encodeURIComponent(root.searchQuery.trim())}`);
        root.request("GET", `https://steamcommunity.com/workshop/browse/?${params.join("&")}`, null, (status, text) => {
            if (status !== 200) return finish([], false, Translation.tr("Workshop request failed (HTTP %1)").arg(status));
            const embedded = root.parseEmbeddedResults(text);
            if (embedded) return finish(embedded.results, embedded.currentPage < embedded.totalPages);
            // Markup changed: collect item links and ask the API for their details
            const ids = [...new Set([...text.matchAll(/filedetails\/\?id=(\d+)/g)].map(m => m[1]))];
            if (ids.length === 0) return finish([], false);
            root.fetchDetails(ids, details => finish(details, true));
        });
    }

    // The browse page is server-rendered with its react-query state embedded as JSON
    function parseEmbeddedResults(html) {
        const match = html.match(/<script type="application\/json" id="valve-ssr-data"[^>]*>([\s\S]*?)<\/script>/);
        if (!match) return null;
        try {
            const queryData = JSON.parse(JSON.parse(match[1]).renderContext.queryData);
            const data = queryData.queries.map(query => query.state?.data).find(data => Array.isArray(data?.results) && data.total_pages !== undefined);
            if (!data) return null;
            return { results: data.results, currentPage: data.current_page, totalPages: data.total_pages };
        } catch (e) {
            console.log("[WallpaperEngine] Could not parse embedded Workshop data:", e);
            return null;
        }
    }

    function fetchDetails(ids, callback) {
        const body = [`itemcount=${ids.length}`, ...ids.map((id, i) => `publishedfileids[${i}]=${id}`)].join("&");
        root.request("POST", "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/", body, (status, text) => {
            try {
                callback(status === 200 ? JSON.parse(text).response.publishedfiledetails : []);
            } catch (e) {
                callback([]);
            }
        });
    }

    function mapItem(item) {
        if ((item.result !== undefined && item.result !== 1) || !item.preview_url) return null;
        if ((item.consumer_appid ?? item.consumer_app_id) !== root.appId) return null;
        const tags = (item.tags ?? []).map(tag => tag.tag);
        if (!tags.includes("Video")) return null;
        const rating = ["Everyone", "Questionable", "Mature"].find(r => tags.includes(r)) ?? "";
        if (!root.options.showMature && rating !== "Everyone") return null;
        return {
            id: String(item.publishedfileid),
            title: item.title ?? "",
            previewUrl: item.preview_url,
            fileSize: parseInt(item.file_size ?? "0"),
            resolution: tags.map(tag => tag.match(/(\d+)\s*x\s*(\d+)/)).find(match => match)?.slice(1).join("×") ?? "",
            rating: rating,
            url: `https://steamcommunity.com/sharedfiles/filedetails/?id=${item.publishedfileid}`
        };
    }

    // Downloads
    function isDownloaded(id) {
        return root.downloadedFiles[id] !== undefined;
    }

    function isQueued(id) {
        return root.queue.includes(id);
    }

    function select(id, darkMode = Appearance.m3colors.darkmode) {
        if (root.isDownloaded(id)) {
            // The file may have been deleted; existsProc downloads it again then
            existsProc.itemId = id;
            existsProc.darkMode = darkMode;
            existsProc.exec(["test", "-f", root.downloadedFiles[id]]);
            return;
        }
        root.applyAfterDownload = id;
        downloadProc.darkMode = darkMode;
        if (root.options.steamUser.length === 0 || root.loginRequired) {
            root.waitForLogin([id]);
            return;
        }
        if (root.currentDownload !== id && !root.isQueued(id)) root.queue = [...root.queue, id];
        root.processQueue();
    }

    // Holds downloads back until steamLogin.qml reports a sign-in
    function waitForLogin(ids) {
        root.pendingLogin = [...root.pendingLogin, ...ids.filter(id => !root.pendingLogin.includes(id))];
        root.openLogin();
    }

    function cancel(id) {
        root.queue = root.queue.filter(queued => queued !== id);
        root.pendingLogin = root.pendingLogin.filter(pending => pending !== id);
        if (root.applyAfterDownload === id) root.applyAfterDownload = "";
        if (root.currentDownload === id) downloadProc.signal(15);
    }

    function processQueue() {
        if (downloadProc.running || root.queue.length === 0) return;
        const id = root.queue[0];
        root.queue = root.queue.slice(1);
        root.currentDownload = id;
        root.downloadStatus = "login";
        root.downloadProgress = 0;
        root.lastError = "";
        downloadProc.donePath = "";
        downloadProc.errorText = "";
        downloadProc.errorCode = "";
        downloadProc.command = [
            "python3", root.downloadScriptPath, id,
            "--user", root.options.steamUser,
            "--target-dir", root.downloadDir,
            ...(root.options.keepWorkshopCache ? ["--keep-cache"] : [])
        ];
        downloadProc.running = true;
    }

    function openLogin() {
        // The lock is held while the window is open, so a second call does nothing
        Quickshell.execDetached(["flock", "-n", root.loginLockPath, "qs", "-p", root.loginQmlPath]);
    }

    function reportError(message) {
        root.lastError = message;
        Quickshell.execDetached(["notify-send", "-a", "Shell", "-i", "dialog-error", "Wallpaper Engine", message]);
    }

    Process {
        id: downloadProc
        property string donePath: ""
        property string errorText: ""
        property string errorCode: ""
        property bool darkMode: Appearance.m3colors.darkmode
        stdout: SplitParser {
            onRead: line => {
                let match = line.match(/^STATUS (\w+)/);
                if (match) root.downloadStatus = match[1];
                match = line.match(/^PROGRESS (\d+)\/(\d+)/);
                if (match && parseInt(match[2]) > 0) root.downloadProgress = parseInt(match[1]) / parseInt(match[2]);
                match = line.match(/^DONE (.+)$/);
                if (match) downloadProc.donePath = match[1];
                match = line.match(/^ERROR (\w+) (.+)$/);
                if (match) {
                    downloadProc.errorCode = match[1];
                    downloadProc.errorText = match[2];
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            const id = root.currentDownload;
            if (downloadProc.donePath.length > 0) {
                root.loginRequired = false;
                root.downloadedFiles = Object.assign({}, root.downloadedFiles, { [id]: downloadProc.donePath });
                if (root.applyAfterDownload === id) {
                    root.applyAfterDownload = "";
                    Wallpapers.select(downloadProc.donePath, downloadProc.darkMode);
                }
            } else if (["guard", "auth"].includes(downloadProc.errorCode)) {
                // The rest of the queue would fail the same way
                root.loginRequired = true;
                const waiting = [id, ...root.queue];
                root.queue = [];
                root.reportError(Translation.tr("Sign in to Steam to download Workshop wallpapers"));
                root.waitForLogin(waiting);
            } else if (downloadProc.errorText.length > 0) {
                root.reportError(downloadProc.errorText);
            } else if (exitCode !== 0 && exitCode !== 143) { // 143: cancelled
                root.reportError(Translation.tr("Download failed (exit code %1)").arg(exitCode));
            }
            root.currentDownload = "";
            root.downloadStatus = "";
            root.downloadProgress = 0;
            root.processQueue();
        }
    }

    IpcHandler {
        target: "wallpaperEngine"

        // Called by steamLogin.qml after a successful sign-in. The account comes
        // with the call because this shell may not have reloaded the config yet.
        function loginFinished(user: string): void {
            if (user.length > 0 && root.options.steamUser !== user) root.options.steamUser = user;
            root.loginRequired = false;
            const waiting = root.pendingLogin;
            root.pendingLogin = [];
            root.queue = [...root.queue, ...waiting.filter(id => id !== root.currentDownload && !root.isQueued(id))];
            root.processQueue();
        }
    }

    Process {
        id: existsProc
        property string itemId: ""
        property bool darkMode: Appearance.m3colors.darkmode
        onExited: (exitCode, exitStatus) => {
            const id = existsProc.itemId;
            if (exitCode === 0) {
                Wallpapers.select(root.downloadedFiles[id], existsProc.darkMode);
                return;
            }
            const files = Object.assign({}, root.downloadedFiles);
            delete files[id];
            root.downloadedFiles = files;
            root.select(id, existsProc.darkMode);
        }
    }

    function refreshDownloaded() {
        downloadedProc.exec(["find", root.downloadDir, "-maxdepth", "1", "-type", "f", "-name", "wallpaper_*"]);
    }

    Process {
        id: downloadedProc
        stdout: StdioCollector {
            onStreamFinished: {
                const files = {};
                for (const path of text.split("\n")) {
                    const match = path.match(/\/wallpaper_(\d+)\.(mp4|mkv|webm|mov)$/);
                    if (match) files[match[1]] = path;
                }
                root.downloadedFiles = files;
            }
        }
    }
}
