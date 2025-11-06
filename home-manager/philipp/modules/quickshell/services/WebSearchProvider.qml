import QtQuick
import qs.services
import qs.components
import Quickshell.Io

// This provider provides a web search action for any given search query.
Item {
    id: root

    // --- Public API for SearchService ---
    signal resultsReady(var resultsArray, int generation)
    signal ready

    // --- Component Factory ---
    Component {
        id: actionFactory
        Action {
            property string searchText

            Process {
                id: shellProcess
                onExited: (exitCode) => {
                    if (exitCode !== 0) {
                        NotificationService.send(
                            "Fehler beim Öffnen des Browsers",
                            "Der Befehl 'xdg-open' konnte nicht ausgeführt werden.",
                            "dialog-error"
                        )
                    }
                }
            }

            onTriggered: {
                const encodedText = encodeURIComponent(searchText)
                const url = "https://www.google.com/search?q=" + encodedText
                shellProcess.command = ["xdg-open", url]
                shellProcess.running = true
            }
        }
    }

    // --- Query Logic ---
    function query(searchText, generation) {
        console.log(`[WebSearchProvider] Received query for generation ${generation} with text: "${searchText}"`)
        var results = []
        const trimmedText = searchText.trim()

        if (trimmedText !== "") {
            var actionInstance = actionFactory.createObject(root, { "searchText": trimmedText });

            results.push({
                "name": "Im Web suchen nach: '" + trimmedText + "'",
                "priority": 0,
                "icon": {
                    "type": "fontIcon",
                    "source": "search",
                    "fontFamily": "Material Symbols Rounded"
                },
                "genericName": "Öffnet den Browser mit der Google-Suche",
                "entryObject": actionInstance
            })
        }
        console.log(`[WebSearchProvider] Sending ${results.length} results for generation ${generation}`)
        resultsReady(results, generation)
    }

    // --- Lifecycle ---
    Component.onCompleted: {
        console.log("[WebSearchProvider] Component.onCompleted")
        SearchService.registerProvider(root)
        ready()
    }

    Component.onDestruction: {
        SearchService.unregisterProvider(root)
    }
}
