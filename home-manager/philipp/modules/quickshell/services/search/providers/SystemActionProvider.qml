import QtQuick
import qs.services.search as Search
import qs.components
import Quickshell.Io

// This provider offers system-level actions like shutdown and reboot.
BaseProvider {
    id: root

    // --- Data ---
    property var systemActions: [
        {
            name: "Herunterfahren",
            keywords: "shutdown poweroff ausschalten",
            icon: "power_settings_new",
            command: ["systemctl", "poweroff"]
        },
        {
            name: "Neu starten",
            keywords: "reboot neustart",
            icon: "restart_alt",
            command: ["systemctl", "reboot"]
        },
        {
            name: "Sperren",
            keywords: "lock sperren bildschirm",
            icon: "lock",
            command: ["loginctl", "lock-session"]
        }
    ]

    // --- Query Logic ---
    function query(searchText, generation) {
        console.log(`[SystemActionProvider] Received query for generation ${generation} with text: "${searchText}"`)
        var results = []
        const trimmedText = searchText.trim().toLowerCase()

        if (trimmedText === "") {
            resultsReady([], generation)
            return;
        }

        for (var i = 0; i < systemActions.length; i++) {
            const action = systemActions[i];
            const searchableString = (action.name + " " + action.keywords).toLowerCase()

            if (searchableString.includes(trimmedText)) {
                results.push({
                    "name": action.name,
                    "priority": 90, // High, but below apps
                    "icon": {
                        "type": "fontIcon",
                        "source": action.icon,
                        "fontFamily": "Material Symbols Rounded"
                    },
                    "genericName": "System-Aktion ausführen",
                    "actionObject": {
                        "type": "command",
                        "command": action.command
                    }
                })
            }
        }
        console.log(`[SystemActionProvider] Sending ${results.length} results for generation ${generation}`)
        resultsReady(results, generation)
    }
}
