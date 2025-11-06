import QtQuick
import qs.services
import qs.components
import Quickshell.Io

// This provider uses 'plocate' to quickly search for files system-wide.
Item {
    id: root

    // --- Public API for SearchService ---
    signal resultsReady(var resultsArray, int generation)
    signal ready // We are ready immediately

    property int currentQueryGeneration: 0

    // --- Component Factory ---
    Component {
        id: actionFactory
        Action {
            property string filePath

            Process {
                id: shellProcess
                onExited: (exitCode) => {
                    if (exitCode !== 0) {
                        NotificationService.send(
                            "Fehler beim Öffnen des Ordners",
                            "Der Befehl 'xdg-open' konnte nicht ausgeführt werden.",
                            "dialog-error"
                        )
                    }
                }
            }

            onTriggered: {
                // Open the directory containing the file
                const lastSlash = filePath.lastIndexOf('/');
                const directory = (lastSlash > 0) ? filePath.substring(0, lastSlash) : "/";
                shellProcess.command = ["xdg-open", directory]
                shellProcess.running = true
            }
        }
    }

    // --- Internal Process for running plocate ---
    Process {
        id: searchProcess
        stdout: StdioCollector { id: stdioCollector }

        onExited: (exitCode) => {
            var searchResults = []
            if (exitCode === 0) {
                const paths = stdioCollector.text.trim().split('\n');
                for (var i = 0; i < paths.length; i++) {
                    const fullPath = paths[i];
                    if (fullPath === "") continue;
                    const lastSlash = fullPath.lastIndexOf('/');
                    const fileName = (lastSlash !== -1) ? fullPath.substring(lastSlash + 1) : fullPath;
                    var actionInstance = actionFactory.createObject(root, { "filePath": fullPath });
                    searchResults.push({
                        "name": fileName,
                        "priority": 50,
                        "icon": {
                            "type": "fontIcon",
                            "source": "draft", // Generic document icon
                            "fontFamily": "Material Symbols Rounded"
                        },
                        "genericName": fullPath,
                        "entryObject": actionInstance
                    })
                }
            } else {
                console.warn(`[FileSearchProvider] 'plocate' process exited with code ${exitCode}`)
            }
            console.log(`[FileSearchProvider] Sending ${searchResults.length} results for generation ${currentQueryGeneration}`)
            resultsReady(searchResults, currentQueryGeneration)
        }
    }

    // --- Query Logic ---
    function query(searchText, generation) {
        console.log(`[FileSearchProvider] Received query for generation ${generation} with text: "${searchText}"`)
        const trimmedText = searchText.trim()
        currentQueryGeneration = generation // Store the generation for this query

        // Stop any previous search process
        if (searchProcess.running) {
            searchProcess.kill();
        }

        // Only search if the query is reasonably long
        if (trimmedText.length < 3) {
            console.log("[FileSearchProvider] Search text too short, sending empty results.")
            resultsReady([], generation) // Return empty results for this generation
            return;
        }

        // Execute plocate
        console.log(`[FileSearchProvider] Starting plocate for generation ${generation}`)
        searchProcess.command = ["plocate", "-i", "--limit", "10", "*" + trimmedText + "*"]
        searchProcess.running = true
    }

    // --- Lifecycle ---
    Component.onCompleted: {
        console.log("[FileSearchProvider] Component.onCompleted")
        SearchService.registerProvider(root)
        ready()
    }

    Component.onDestruction: {
        SearchService.unregisterProvider(root)
    }
}
