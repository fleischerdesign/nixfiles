import QtQuick
import qs.services

// This provider checks if the search query is a mathematical expression
// and provides the result as a search item.
Item {
    id: root

    // --- Public API for SearchService ---
    signal resultsReady(var resultsArray)

    function query(searchText) {
        const trimmedText = searchText.trim()
        var results = []

        // Only consider queries that have a number and an operator.
        if (trimmedText.length > 2 && /^[\d\s\(\)\+\-\*\/\.]+$/.test(trimmedText)) {
            try {
                const result = eval(trimmedText)

                // Ensure the result is a valid number.
                if (typeof result === 'number' && isFinite(result)) {
                    results.push({
                        "name": "" + result, // Must be a string
                        "icon": {
                            "type": "fontIcon",
                            "source": "calculate",
                            "fontFamily": "Material Symbols Rounded"
                        },
                        "genericName": "Ergebnis von: " + trimmedText,
                        "entryObject": {
                            "execute": function() {
                                // TODO: Copy result to clipboard
                                console.log("Calculator result executed: " + result)
                            }
                        }
                    })
                }
            } catch (e) {
                // The expression was invalid, so do nothing.
            }
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
