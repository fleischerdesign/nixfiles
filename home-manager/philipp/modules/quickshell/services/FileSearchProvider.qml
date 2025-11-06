import QtQuick
import qs.services
import qs.components
import Quickshell.Io

// This provider uses 'plocate' to quickly search for files system-wide.
Item {
    id: root

    // --- Public API for SearchService ---
    signal resultsReady(var resultsArray)
    signal ready // We are ready immediately

    // --- Component Factory ---
    Component {
        id: actionFactory
        Action {
            property string filePath

            Process {
                id: shellProcess
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
        stdout: StdioCollector {
            onStreamFinished: {
                var searchResults = []
                const paths = this.text.trim().split('\n');

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
                resultsReady(searchResults)
            }
        }
    }

    // --- Query Logic ---
    function query(searchText) {
        const trimmedText = searchText.trim()

        // Stop any previous search process
        if (searchProcess.running) {
            searchProcess.kill();
        }

        // Only search if the query is reasonably long
        if (trimmedText.length < 3) {
            resultsReady([]) // Return empty results
            return;
        }

        // Execute plocate
        searchProcess.command = ["plocate", "-i", "--limit", "10", "*" + trimmedText + "*"]
        searchProcess.running = true
    }

    // --- Lifecycle ---
    Component.onCompleted: {
        SearchService.registerProvider(root)
        // Emit ready immediately, as this provider is stateless until queried.
        ready()
    }

    Component.onDestruction: {
        SearchService.unregisterProvider(root)
    }
}
