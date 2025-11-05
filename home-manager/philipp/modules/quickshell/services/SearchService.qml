pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Widgets

// This singleton service coordinates search queries across multiple providers.
// It is completely headless and knows nothing about what it is searching for.
QtObject {
    id: root

    // --- Public API ---
    property string searchText: ""
    readonly property ListModel results: ListModel {}

    // --- Provider Management ---
    property var providers: []

    function registerProvider(provider) {
        console.log("[SearchService] Registering provider: " + provider)
        providers.push(provider)
        provider.resultsReady.connect(handleProviderResults)

        // When the provider is ready, trigger an initial query.
        provider.ready.connect(function() {
            console.log("[SearchService] Provider " + provider + " is ready. Triggering initial query.")
            provider.query(searchText)
        })
    }

    function unregisterProvider(provider) {
        console.log("[SearchService] Unregistering provider: " + provider)
        const index = providers.indexOf(provider);
        if (index > -1) {
            providers.splice(index, 1);
        }
    }

    // --- Internal State ---
    property var pendingResults: []
    property int activeQueries: 0

    // --- Logic ---
    onSearchTextChanged: {
        pendingResults = []
        results.clear()

        if (providers.length === 0) return;

        activeQueries = providers.length
        for (var i = 0; i < providers.length; i++) {
            providers[i].query(searchText)
        }
    }

    function handleProviderResults(providerResults) {
        pendingResults = pendingResults.concat(providerResults)
        activeQueries--

        if (activeQueries === 0) {
            processAndDisplayResults()
        }
    }

    function processAndDisplayResults() {
        if (pendingResults.length === 0) {
            return;
        }

        // 1. Find the highest priority among all pending results.
        let highestPriority = -1;
        for (var i = 0; i < pendingResults.length; i++) {
            if (pendingResults[i].priority > highestPriority) {
                highestPriority = pendingResults[i].priority;
            }
        }

        // 2. Filter for results with the highest priority.
        for (var i = 0; i < pendingResults.length; i++) {
            if (pendingResults[i].priority === highestPriority) {
                results.append(pendingResults[i])
            }
        }

        pendingResults = [] // Clear for next search
    }
}