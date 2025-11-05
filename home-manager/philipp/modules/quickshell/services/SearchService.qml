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

    // --- Logic ---
    onSearchTextChanged: {
        // Clear previous results and query all registered providers.
        results.clear()

        // When search text is cleared, we still want to query providers
        // so they can provide default results (e.g., all apps).
        for (var i = 0; i < providers.length; i++) {
            providers[i].query(searchText)
        }
    }

    function handleProviderResults(providerResults) {
        // This function is connected to the resultsReady signal of each provider.
        // A real implementation might sort or rank results from different providers.
        // For now, we just append them as they come in.
        for (var i = 0; i < providerResults.length; i++) {
            results.append(providerResults[i])
        }
    }
}
