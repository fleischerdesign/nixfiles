import QtQuick
import qs.services.search as Search
import qs.components
import Quickshell.Io // Import the Process component

// This provider checks if the search query is a mathematical expression
// and provides the result as a search item.
Item {
    id: root

    // --- Public API for Search.SearchService ---
    signal resultsReady(var resultsArray, int generation)
    signal ready

    property var metadata: ({ "regex": "^[\\d\\s\\(\\)\\+\\-\\*\\/\\.]+$" })

    // --- Query Logic ---
    function query(searchText, generation) {
        console.log(`[CalculatorProvider] Received query for generation ${generation} with text: "${searchText}"`)
        const trimmedText = searchText.trim()
        var results = []

        try {
            const result = eval(trimmedText)

            if (typeof result === 'number' && isFinite(result)) {
                results.push({
                    "name": "" + result,
                    "priority": 100,
                    "icon": {
                        "type": "fontIcon",
                        "source": "calculate",
                        "fontFamily": "Material Symbols Rounded"
                    },
                    "genericName": "Ergebnis von: " + trimmedText,
                    "actionObject": {
                        "type": "copy",
                        "text": String(result)
                    }
                })
            }
        } catch (e) {
            // Invalid expression, do nothing.
        }
        
        console.log(`[CalculatorProvider] Sending ${results.length} results for generation ${generation}`)
        resultsReady(results, generation)
    }

    // --- Lifecycle ---
    Component.onCompleted: {
        console.log("[CalculatorProvider] Component.onCompleted")
        Search.SearchService.registerProvider(root)
        ready()
    }

    Component.onDestruction: {
        Search.SearchService.unregisterProvider(root)
    }
}