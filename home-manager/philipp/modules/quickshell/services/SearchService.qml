pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Widgets

// This singleton service coordinates search queries across multiple providers.
// It is completely headless and knows nothing about what it is searching for.
Item {
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
    property bool searchInProgress: false

    onSearchTextChanged: {
        if (!allProvidersReady) {
            console.log("[SearchService] onSearchTextChanged ignored: Not all providers are ready.")
            return;
        }

        searchGeneration++
        searchInProgress = true
        console.log(`>>>> [SearchService] STARTING search generation ${searchGeneration} for text: "${searchText}"`)
        pendingResults = []
        results.clear()

        if (providers.length === 0) {
            console.log("[SearchService] No providers registered, aborting search.")
            searchInProgress = false
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
            return;
        }

        pendingResults = pendingResults.concat(providerResults)
        activeQueries--
        console.log(`[SearchService] Handled results. Active queries remaining: ${activeQueries}`)
        
        if (activeQueries === 0) {
            searchInProgress = false
        }

        processAndDisplayResults()
    }

    function processAndDisplayResults() {
        console.log(`[SearchService] Processing ${pendingResults.length} pending results.`)

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

        results.clear()

        console.log(`[SearchService] Appending ${finalResults.length} final results to model.`)
        for (var i = 0; i < finalResults.length; i++) {
            results.append(finalResults[i])
        }
    }
}
