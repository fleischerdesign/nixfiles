import QtQuick
import qs.services
import qs.components
import Quickshell.Io

// This provider offers system-level actions like shutdown and reboot.
Item {
    id: root

    // --- Public API for SearchService ---
    signal resultsReady(var resultsArray, int generation)
    signal ready // We are ready immediately

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

    // --- Component Factory ---
    Component {
        id: actionFactory
        Action {
            property var commandToRun
            Process {
                id: shellProcess
                onExited: (exitCode) => {
                    if (exitCode !== 0) {
                        NotificationService.send(
                            "System-Aktion fehlgeschlagen",
                            `Befehl '${commandToRun[0]}' ist fehlgeschlagen.`,
                            "dialog-error"
                        )
                    }
                }
            }

            onTriggered: {
                shellProcess.command = commandToRun
                shellProcess.running = true
            }
        }
    }

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
                var actionInstance = actionFactory.createObject(root, { "commandToRun": action.command });

                results.push({
                    "name": action.name,
                    "priority": 90, // High, but below apps
                    "icon": {
                        "type": "fontIcon",
                        "source": action.icon,
                        "fontFamily": "Material Symbols Rounded"
                    },
                    "genericName": "System-Aktion ausführen",
                    "entryObject": actionInstance
                })
            }
        }
        console.log(`[SystemActionProvider] Sending ${results.length} results for generation ${generation}`)
        resultsReady(results, generation)
    }

    // --- Lifecycle ---
    Component.onCompleted: {
        console.log("[SystemActionProvider] Component.onCompleted")
        SearchService.registerProvider(root)
        ready()
    }

    Component.onDestruction: {
        SearchService.unregisterProvider(root)
    }
}
