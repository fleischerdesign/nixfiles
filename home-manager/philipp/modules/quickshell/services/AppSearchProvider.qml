import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services

// This component's job is to load all applications and provide them to the SearchService.
Item {
    id: root

    signal resultsReady(var resultsArray, int generation)
    signal ready

    function query(searchText, generation) {
        console.log(`[AppSearchProvider] Received query for generation ${generation} with text: "${searchText}"`)
        var filteredResults = []
        const currentSearchText = searchText.toLowerCase()

        // When the search text is empty, provide all applications as results.
        if (currentSearchText === "") {
             for (var i = 0; i < allAppsModel.count; i++) {
                filteredResults.push(allAppsModel.get(i))
            }
        } else {
            for (var i = 0; i < allAppsModel.count; i++) {
                const entry = allAppsModel.get(i)
                const name = entry.name ? entry.name.toLowerCase() : ""
                const generic = entry.genericName ? entry.genericName.toLowerCase() : ""
                const keywords = entry.keywords ? entry.keywords.toLowerCase() : ""
                const searchableString = name + " " + generic + " " + keywords

                if (searchableString.includes(currentSearchText)) {
                    filteredResults.push(entry)
                }
            }
        }
        console.log(`[AppSearchProvider] Sending ${filteredResults.length} results for generation ${generation}`)
        resultsReady(filteredResults, generation)
    }

    // --- Internal data loading ---
    Timer {
        id: readyTimer
        interval: 50 // A short delay to ensure the Repeater has finished.
        onTriggered: {
            console.log("[AppSearchProvider] Ready timer triggered.")
            ready()
        }
    }

    ListModel {
        id: allAppsModel
        onCountChanged: {
            // console.log("[AppSearchProvider] allAppsModel count changed: " + count)
            readyTimer.restart()
        }
    }

    Component.onCompleted: {
        console.log("[AppSearchProvider] Component.onCompleted")
        SearchService.registerProvider(root)
    }

    Component.onDestruction: {
        SearchService.unregisterProvider(root)
    }

    // Use a Repeater to robustly load the application list from the C++ model.
    Repeater {
        model: DesktopEntries.applications
        delegate: Item {
            required property var modelData
            Component.onCompleted: {
                var keywordString = ""
                if (modelData.keywords && typeof modelData.keywords.length !== 'undefined') {
                    for (var i = 0; i < modelData.keywords.length; i++) {
                        keywordString += modelData.keywords[i] + " "
                    }
                }
                allAppsModel.append({
                    "name": modelData.name,
                    "priority": 100,
                    "icon": {
                        "type": "image",
                        "source": modelData.icon
                    },
                    "genericName": modelData.genericName,
                    "keywords": keywordString,
                    "entryObject": modelData
                })
            }
        }
    }
}