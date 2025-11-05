import QtQuick
import qs.services
import qs.components
import Quickshell.Io // Import the Process component

// This provider checks if the search query is a mathematical expression
// and provides the result as a search item.
Item {
    id: root

    // --- Public API for SearchService ---
    signal resultsReady(var resultsArray)

    // --- Component Factory ---
    // This defines a template for creating our Action objects. Each Action instance
    // will be a self-contained QObject with its own Process for executing shell commands.
    Component {
        id: actionFactory
                Action {
                    property string resultText
        
                    // Each Action instance gets its own private Process component for the copy action.
                    Process {
                        id: copyProcess
                    }
        
            onTriggered: {
                // 1. Copy to clipboard via wl-copy
                copyProcess.command = ["sh", "-c", `echo "${resultText}" | wl-copy`]
                copyProcess.running = true

                // 2. Send a notification via the NotificationService's public API
                NotificationService.send(
                    "In die Zwischenablage kopiert",
                    resultText,
                    "calculate"
                )
            }
                }    }

    // --- Query Logic ---
    function query(searchText) {
        const trimmedText = searchText.trim()
        var results = []

        if (trimmedText.length > 2 && /^[\d\s\(\)\+\-\*\/\.]+$/.test(trimmedText)) {
            try {
                const result = eval(trimmedText)

                if (typeof result === 'number' && isFinite(result)) {
                    // Create a self-contained Action instance for this specific result.
                    var actionInstance = actionFactory.createObject(root, { "resultText": String(result) });

                    results.push({
                        "name": "" + result,
                        "priority": 100,
                        "icon": {
                            "type": "fontIcon",
                            "source": "calculate",
                            "fontFamily": "Material Symbols Rounded"
                        },
                        "genericName": "Ergebnis von: " + trimmedText,
                        "entryObject": actionInstance
                    })
                }
            } catch (e) {
                // Invalid expression, do nothing.
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