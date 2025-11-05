import QtQuick
import qs.services
import qs.components
import Quickshell.Io

// This provider provides a web search action for any given search query.
Item {
    id: root

    // --- Public API for SearchService ---
    signal resultsReady(var resultsArray)

    // --- Component Factory ---
    Component {
        id: actionFactory
        Action {
            property string searchText

            Process {
                id: shellProcess
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
    function query(searchText) {
        var results = []
        const trimmedText = searchText.trim()

        if (trimmedText !== "") {
            var actionInstance = actionFactory.createObject(root, { "searchText": trimmedText });

            results.push({
                "name": "Im Web suchen nach: '" + trimmedText + "'",
                "icon": {
                    "type": "fontIcon",
                    "source": "search",
                    "fontFamily": "Material Symbols Rounded"
                },
                "genericName": "Öffnet den Browser mit der Google-Suche",
                "entryObject": actionInstance
            })
        }
        resultsReady(results)
    }

    // --- Lifecycle ---
    Component.onCompleted: {
        SearchService.registerProvider(root)
    }

    Component.onDestruction: {
        SearchService.unregisterProvider(root)
    }
}
