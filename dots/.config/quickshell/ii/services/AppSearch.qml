pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    // Deduped list to fix double icons
    readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values)
        .filter((app, index, self) => 
            index === self.findIndex((t) => (
                t.id === app.id
            ))
    )
    
    readonly property var preppedNames: list.map(a => ({
        name: Fuzzy.prepare(`${a.name} `),
        entry: a
    }))

    readonly property var preppedIcons: list.map(a => ({
        name: Fuzzy.prepare(`${a.icon} `),
        entry: a
    }))

    // ЙЦУКЕН -> QWERTY by physical key. Lets you type "ылнзу" (Russian layout) and find "skype".
    readonly property var ruToEnLayout: ({
        "й":"q","ц":"w","у":"e","к":"r","е":"t","н":"y","г":"u","ш":"i","щ":"o","з":"p","х":"[","ъ":"]",
        "ф":"a","ы":"s","в":"d","а":"f","п":"g","р":"h","о":"j","л":"k","д":"l","ж":";","э":"'",
        "я":"z","ч":"x","с":"c","м":"v","и":"b","т":"n","ь":"m","б":",","ю":".","ё":"`"
    })
    function translateLayout(str) {
        return str.toLowerCase().split("").map(c => root.ruToEnLayout[c] ?? c).join("");
    }

    function fuzzyQuery(search: string): var { // Idk why list<DesktopEntry> doesn't work
        const translated = translateLayout(search);
        if (root.sloppySearch) {
            const results = list.map(obj => ({
                entry: obj,
                score: Math.max(
                    Levendist.computeScore(obj.name.toLowerCase(), search.toLowerCase()),
                    Levendist.computeScore(obj.name.toLowerCase(), translated))
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        const queries = (translated !== search.toLowerCase()) ? [search, translated] : [search];
        const best = new Map();
        for (const q of queries) {
            Fuzzy.go(q, preppedNames, { all: true, key: "name" }).forEach(r => {
                const e = r.obj.entry;
                if (!best.has(e) || best.get(e) < r.score) best.set(e, r.score);
            });
        }
        return [...best.keys()].sort((a, b) => best.get(b) - best.get(a));
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0) 
            && !iconName.includes("image-missing");
    }

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";

        // Quickshell's desktop entry lookup
        const entry = DesktopEntries.byId(str);
        if (entry) return entry.icon;

        // Normal substitutions
        if (substitutions[str]) return substitutions[str];
        if (substitutions[str.toLowerCase()]) return substitutions[str.toLowerCase()];

        // Regex substitutions
        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str) return replacedName;
        }

        // Icon exists -> return as is
        if (iconExists(str)) return str;


        // Simple guesses
        const lowercased = str.toLowerCase();
        if (iconExists(lowercased)) return lowercased;

        const reverseDomainNameAppName = getReverseDomainNameAppName(str);
        if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;

        const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
        if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;

        const kebabNormalizedGuess = getKebabNormalizedAppName(str);
        if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;

        const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
        if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;

        // Search in desktop entries
        const iconSearchResults = Fuzzy.go(str, preppedIcons, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
        if (iconSearchResults.length > 0) {
            const guess = iconSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        const nameSearchResults = root.fuzzyQuery(str);
        if (nameSearchResults.length > 0) {
            const guess = nameSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        // Quickshell's desktop entry lookup
        const heuristicEntry = DesktopEntries.heuristicLookup(str);
        if (heuristicEntry) return heuristicEntry.icon;

        // Give up
        return "application-x-executable";
    }
}
