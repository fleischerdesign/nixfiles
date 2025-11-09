import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services.search as Search

// This component's job is to load all applications and provide them to the Search.SearchService.
BaseProvider {
    id: root

    property bool isReady: false

    function fuzzyMatch(search, text) {
        let score = 0
        let searchPos = 0
        
        for (let i = 0; i < text.length && searchPos < search.length; i++) {
            if (text[i].toLowerCase() === search[searchPos].toLowerCase()) { // Case-insensitive match
                score += (100 - i) // Earlier matches = higher score
                searchPos++
            }
        }
        
        return searchPos === search.length ? score : 0
    }

    function query(searchText, generation) {
        if (!isReady) {
            console.warn("[AppSearchProvider] Not ready yet, returning empty results.")
            resultsReady([], generation)
            return
        }

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
                const score = fuzzyMatch(currentSearchText, entry.searchableString)
                if (score > 0) {
                    var newEntry = {};
                    for (var key in entry) {
                        newEntry[key] = entry[key];
                    }
                    newEntry.priority = 100 + score;
                    newEntry.matchQuality = score;
                    filteredResults.push(newEntry);
                }
            }
            // Sort by priority (descending) after fuzzy matching
            filteredResults.sort((a, b) => b.priority - a.priority)
        }
        console.log(`[AppSearchProvider] Sending ${filteredResults.length} results for generation ${generation}`)
        resultsReady(filteredResults, generation)
    }

    // --- Internal data loading ---
    Timer {
        id: readyTimer
        interval: 50 // A short delay to ensure the Repeater has finished.
        onTriggered: {
            console.log("[AppSearchProvider] Ready timer triggered. Provider is now ready.")
            root.isReady = true
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
        // We must register the provider here because we override the base onCompleted.
        // We do NOT call ready() here. The readyTimer will do that once the model is loaded.
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

                const name = modelData.name || ""
                const genericName = modelData.genericName || ""
                const searchable = (name + " " + genericName + " " + keywordString).toLowerCase()

                allAppsModel.append({
                    "name": modelData.name,
                    "priority": 100,
                    "icon": {
                        "type": "image",
                        "source": modelData.icon
                    },
                    "genericName": modelData.genericName,
                    "keywords": keywordString,
                    "actionObject": {
                        "type": "launchApp",
                        "appEntry": modelData
                    },
                    "searchableString": searchable
                })
            }
        }
    }
}