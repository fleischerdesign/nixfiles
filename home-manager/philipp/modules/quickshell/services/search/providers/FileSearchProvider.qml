import QtQuick
import qs.services.search as Search
import qs.components
import Quickshell.Io

// This provider uses 'plocate' to quickly search for files system-wide.
Item {
    id: root

    // --- Public API for Search.SearchService ---
    signal resultsReady(var resultsArray, int generation)
    signal ready // We are ready immediately

    property int currentQueryGeneration: 0

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
                    const directory = (lastSlash > 0) ? fullPath.substring(0, lastSlash) : "/";
                    searchResults.push({
                        "name": fileName,
                        "priority": 50,
                        "icon": {
                            "type": "fontIcon",
                            "source": "draft", // Generic document icon
                            "fontFamily": "Material Symbols Rounded"
                        },
                        "genericName": fullPath,
                        "actionObject": {
                            "type": "command",
                            "command": ["xdg-open", directory]
                        }
                    })
                }
            } else {
                console.warn(`[FileSearchProvider] 'plocate' process exited with code ${exitCode}`)
            }
            console.log(`[FileSearchProvider] Sending ${searchResults.length} results for generation ${currentQueryGeneration}`)
            resultsReady(searchResults, currentQueryGeneration)
        }
    }

    property var metadata: ({ "minLength": 3 })

    // --- Query Logic ---
    function query(searchText, generation) {
        console.log(`[FileSearchProvider] Received query for generation ${generation} with text: "${searchText}"`)
        const trimmedText = searchText.trim()
        currentQueryGeneration = generation // Store the generation for this query

        // Stop any previous search process
        if (searchProcess.running) {
            searchProcess.kill();
        }

        // Execute plocate
        console.log(`[FileSearchProvider] Starting plocate for generation ${generation}`)
        searchProcess.command = ["plocate", "-i", "--limit", "10", "*" + trimmedText + "*"]
        searchProcess.running = true
    }

    // --- Lifecycle ---
    Component.onCompleted: {
        console.log("[FileSearchProvider] Component.onCompleted")
        Search.SearchService.registerProvider(root)
        ready()
    }

    Component.onDestruction: {
        Search.SearchService.unregisterProvider(root)
    }
}
