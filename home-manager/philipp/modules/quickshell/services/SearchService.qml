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
    property int readyProviders: 0
    property bool allProvidersReady: false

    function registerProvider(provider) {
        console.log(`[SearchService] Registering provider: ${provider}`)
        providers.push(provider)
        provider.resultsReady.connect(handleProviderResults)

        provider.ready.connect(function() {
            if (allProvidersReady) return;
            readyProviders++;
            console.log(`[SearchService] Provider ready. ${readyProviders}/${providers.length}`)
            if (readyProviders === providers.length) {
                allProvidersReady = true;
                console.log(">>>> [SearchService] All providers ready. Triggering initial population.")
                onSearchTextChanged()
            }
        })
    }

    function unregisterProvider(provider) {
        console.log(`[SearchService] Unregistering provider: ${provider}`)
        const index = providers.indexOf(provider);
        if (index > -1) {
            providers.splice(index, 1);
        }
    }

    // --- Internal State ---
    property var pendingResults: []
    property int activeQueries: 0
    property int searchGeneration: 0

    // --- Logic ---
    onSearchTextChanged: {
        if (!allProvidersReady) {
            console.log("[SearchService] onSearchTextChanged ignored: Not all providers are ready.")
            return;
        }

        searchGeneration++
        console.log(`>>>> [SearchService] STARTING search generation ${searchGeneration} for text: "${searchText}"`)
        pendingResults = []
        results.clear()

        if (providers.length === 0) {
            console.log("[SearchService] No providers registered, aborting search.")
            return;
        }

        activeQueries = providers.length
        for (var i = 0; i < providers.length; i++) {
            console.log(`[SearchService] Querying provider ${providers[i]} for generation ${searchGeneration}`)
            providers[i].query(searchText, searchGeneration)
        }
    }

    function handleProviderResults(providerResults, generation) {
        console.log(`[SearchService] Received ${providerResults.length} results for generation ${generation}. Current generation is ${searchGeneration}.`)
        if (generation !== searchGeneration) {
            console.log(`[SearchService] Discarding stale results for generation ${generation}.`)
            // This is not an error, just an old request finishing, but we need to decrement the counter.
            activeQueries--
            console.log(`[SearchService] Stale results handled. Active queries remaining: ${activeQueries}`)
            return;
        }

        pendingResults = pendingResults.concat(providerResults)
        activeQueries--
        console.log(`[SearchService] Handled results. Active queries remaining: ${activeQueries}`)
        if (activeQueries === 0) {
            console.log(">>>> [SearchService] All providers finished for generation " + generation + ". Processing results.")
            processAndDisplayResults()
        }
    }

    function processAndDisplayResults() {
        console.log(`[SearchService] Processing ${pendingResults.length} pending results.`)
        if (pendingResults.length === 0) {
            console.log("[SearchService] No pending results to process.")
            return;
        }

        let highestPriority = -1;
        for (var i = 0; i < pendingResults.length; i++) {
            if (pendingResults[i].priority > highestPriority) {
                highestPriority = pendingResults[i].priority;
            }
        }
        console.log(`[SearchService] Found highest priority: ${highestPriority}.`)

        var finalResults = []
        for (var i = 0; i < pendingResults.length; i++) {
            if (pendingResults[i].priority === highestPriority) {
                finalResults.push(pendingResults[i])
            }
        }

        console.log(`[SearchService] Appending ${finalResults.length} final results to model.`)
        for (var i = 0; i < finalResults.length; i++) {
            results.append(finalResults[i])
        }

        pendingResults = [] // Clear for next search
    }
}
