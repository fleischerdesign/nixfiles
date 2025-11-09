pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Widgets
import "./providers" as Providers

// This singleton service coordinates search queries across multiple providers.
// It is now self-contained and owns its providers.
Item {
    id: root

    // --- Provider Declaration ---
    property var appSearchProvider: Providers.AppSearchProvider {}
    property var calculatorProvider: Providers.CalculatorProvider {}
    property var fileSearchProvider: Providers.FileSearchProvider {}
    property var systemActionProvider: Providers.SystemActionProvider {}
    property var weatherProvider: Providers.WeatherProvider {}
    property var webSearchProvider: Providers.WebSearchProvider {}

    // --- Public API ---
    property string searchText: ""
    readonly property ListModel results: ListModel {}

    // --- Provider Management ---
    property var providers: ({})

    Component.onCompleted: {
        for (const prop in this) {
            const provider = this[prop];

            // Check if the property is a valid search provider
            if (provider && provider.objectName === "searchProvider") {
                const providerId = provider.toString();
                const metadata = provider.metadata || {};
                var debounceTimer = null;

                if (metadata.debounce > 0) {
                    debounceTimer = Qt.createQmlObject(`import QtQuick; Timer { interval: ${metadata.debounce} }`, root);
                    debounceTimer.triggered.connect(function() {
                        console.log(`[SearchService] Debounce timer triggered for provider ${providerId}`);
                        queryProvider(providerId, searchText, searchGeneration);
                    });
                }

                providers[providerId] = {
                    "instance": provider,
                    "metadata": metadata,
                    "debounceTimer": debounceTimer
                };

                provider.resultsReady.connect(handleProviderResults);
            }
        }
        console.log(`[SearchService] All ${Object.keys(providers).length} self-owned providers are configured via introspection.`);
    }

    // Internal State
    property var pendingResults: []
    property int activeQueries: 0
    property int searchGeneration: 0

    // Logic 
    property bool searchInProgress: false

    onSearchTextChanged: {
        searchGeneration++
        searchInProgress = true
        console.log(`>>>> [SearchService] STARTING search generation ${searchGeneration} for text: "${searchText}"`)

        pendingResults = []
        results.clear()

        // Stop all running debounce timers to prevent stale queries from firing.
        const providerIds = Object.keys(providers)
        for (var i = 0; i < providerIds.length; i++) {
            const providerData = providers[providerIds[i]]
            if (providerData.debounceTimer && providerData.debounceTimer.running) {
                providerData.debounceTimer.stop()
            }
        }

        activeQueries = 0 // Reset active query counter for the new generation.

        if (providerIds.length === 0) {
            searchInProgress = false
            return;
        }

        const trimmedText = searchText.trim()
        var providersWillQuery = 0

        for (i = 0; i < providerIds.length; i++) {
            const providerId = providerIds[i]
            const providerData = providers[providerId]

            if (shouldQueryProvider(providerData, trimmedText)) {
                providersWillQuery++
                if (providerData.debounceTimer) {
                    providerData.debounceTimer.restart()
                } else {
                    // Query non-debounced providers immediately.
                    queryProvider(providerId, searchText, searchGeneration)
                }
            }
        }

        console.log(`[SearchService] Providers that will query for generation ${searchGeneration}: ${providersWillQuery}`)

        // If no providers are going to run for this text, the search is already over.
        if (providersWillQuery === 0) {
            searchInProgress = false
            console.log(`[SearchService] No providers matched criteria. Search complete.`)
        }
    }

    function queryProvider(providerId, text, generation) {
        const providerData = providers[providerId]
        if (!providerData) {
            console.warn(`[SearchService] Provider ${providerId} not found`)
            return
        }

        // A query is now officially active.
        activeQueries++
        console.log(`[SearchService] Querying provider ${providerId} for generation ${generation} (active queries: ${activeQueries})`)
        providerData.instance.query(text, generation)
    }

    function shouldQueryProvider(providerData, trimmedText) {
        const metadata = providerData.metadata

        if (metadata.minLength && trimmedText.length < metadata.minLength) {
            return false
        }

        if (metadata.trigger) {
            if (!trimmedText.toLowerCase().startsWith(metadata.trigger)) {
                return false
            }
        }
        
        if (metadata.regex) {
            const regex = new RegExp(metadata.regex, 'i')
            if (!regex.test(trimmedText)) {
                return false
            }
        }

        return true
    }

    function handleProviderResults(providerResults, generation) {
        // Ignore stale results from a previous search generation.
        if (generation !== searchGeneration) {
            console.log(`[SearchService] Discarding stale results for generation ${generation}.`)
            return;
        }

        console.log(`[SearchService] Received ${providerResults.length} results for generation ${generation}.`)
        pendingResults = pendingResults.concat(providerResults)
        activeQueries = Math.max(0, activeQueries - 1)
        console.log(`[SearchService] Handled results. Active queries remaining: ${activeQueries}`)

        if (activeQueries < 0) {
            console.error(`[SearchService] ERROR: activeQueries is negative! Resetting to 0.`)
            activeQueries = 0
        }

        // Only process the final list when all providers have returned their results.
        if (activeQueries === 0) {
            searchInProgress = false
            console.log(`[SearchService] All queries complete for generation ${searchGeneration}.`)
            processAndDisplayResults()
        }
    }

    function processAndDisplayResults() {
        console.log(`[SearchService] Processing ${pendingResults.length} final results.`)

        // Sort all collected results by priority, descending.
        pendingResults.sort((a, b) => b.priority - a.priority)

        results.clear();

        console.log(`[SearchService] Appending ${pendingResults.length} sorted results to model.`);
        for (let i = 0; i < pendingResults.length; i++) {
            results.append(pendingResults[i]);
        }
    }

    function cancelSearch() {
        console.log(`[SearchService] Cancelling search generation ${searchGeneration}`)
        searchGeneration++  // Invalidate all running queries
        pendingResults = []
        activeQueries = 0
        searchInProgress = false
        
        // Stop all debounce timers
        const providerIds = Object.keys(providers)
        for (var i = 0; i < providerIds.length; i++) {
            const providerData = providers[providerIds[i]]
            if (providerData.debounceTimer && providerData.debounceTimer.running) {
                providerData.debounceTimer.stop()
            }
        }
    }
}