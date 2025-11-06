import QtQuick
import qs.services.search as Search
import qs.components
import Quickshell.Io

// This provider provides a web search action for any given search query.
Item {
    id: root

    // --- Public API for Search.SearchService ---
    signal resultsReady(var resultsArray, int generation)
    signal ready

    property var metadata: ({})

    // --- Query Logic ---
    function query(searchText, generation) {
        console.log(`[WebSearchProvider] Received query for generation ${generation} with text: "${searchText}"`)
        var results = []
        const trimmedText = searchText.trim()

        if (trimmedText !== "") {
            const encodedText = encodeURIComponent(trimmedText)
            const url = "https://www.google.com/search?q=" + encodedText

            results.push({
                "name": "Im Web suchen nach: '" + trimmedText + "'",
                "priority": 0,
                "icon": {
                    "type": "fontIcon",
                    "source": "search",
                    "fontFamily": "Material Symbols Rounded"
                },
                "genericName": "Öffnet den Browser mit der Google-Suche",
                "actionObject": {
                    "type": "url",
                    "url": url
                }
            })
        }
        console.log(`[WebSearchProvider] Sending ${results.length} results for generation ${generation}`)
        resultsReady(results, generation)
    }

    // --- Lifecycle ---
    Component.onCompleted: {
        console.log("[WebSearchProvider] Component.onCompleted")
        Search.SearchService.registerProvider(root)
        ready()
    }

    Component.onDestruction: {
        Search.SearchService.unregisterProvider(root)
    }
}
