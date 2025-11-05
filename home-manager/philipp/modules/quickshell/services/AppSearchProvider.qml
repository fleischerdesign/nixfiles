import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services

// This component's job is to load all applications and provide them to the SearchService.
Item {
    id: root

    // --- Public API for SearchService ---
    signal resultsReady(var resultsArray)
    signal ready

    function query(searchText) {
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
        resultsReady(filteredResults)
    }

    // --- Internal data loading ---
    Timer {
        id: readyTimer
        interval: 50 // A short delay to ensure the Repeater has finished.
        onTriggered: root.ready()
    }

    ListModel {
        id: allAppsModel
        onCountChanged: readyTimer.restart()
    }

    Component.onCompleted: {
        // Register this component as a search provider in the central service.
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