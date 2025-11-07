pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Widgets

// This singleton service coordinates search queries across multiple providers.
// It is completely headless and knows nothing about what it is searching for.
Item {
    id: root

    // Public API
    property string searchText: ""
    readonly property ListModel results: ListModel {}

    // Provider Management
    property var providers: ({})
    property int readyProviders: 0
    property bool allProvidersReady: false

    function registerProvider(provider) {
        console.log(`[SearchService] Registering provider: ${provider}`)
        const providerId = provider.toString()
        const metadata = provider.metadata || {}
        var debounceTimer = null

        if (metadata.debounce > 0) {
            debounceTimer = Qt.createQmlObject(`import QtQuick; Timer { interval: ${metadata.debounce} }`, root)
            debounceTimer.triggered.connect(function() {
                console.log(`[SearchService] Debounce timer triggered for provider ${providerId}`)
                queryProvider(providerId, searchText, searchGeneration)
            })
        }

        providers[providerId] = {
            "instance": provider,
            "metadata": metadata,
            "debounceTimer": debounceTimer
        }

        provider.resultsReady.connect(handleProviderResults)

        provider.ready.connect(function() {
            if (allProvidersReady) return;
            readyProviders++;
            console.log(`[SearchService] Provider ready. ${readyProviders}/${Object.keys(providers).length}`)
            if (readyProviders === Object.keys(providers).length) {
                allProvidersReady = true;
                console.log(">>>> [SearchService] All providers ready. Triggering initial population.")
                onSearchTextChanged()
            }
        })
    }

    function unregisterProvider(provider) {
        const providerId = provider.toString()
        console.log(`[SearchService] Unregistering provider: ${providerId}`)
        if (providers[providerId]) {
            if (providers[providerId].debounceTimer) {
                providers[providerId].debounceTimer.destroy()
            }
            delete providers[providerId]
        }
    }

    // Internal State
    property var pendingResults: []
    property int activeQueries: 0
    property int searchGeneration: 0

    // Logic 
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
        activeQueries = 0 // Reset before counting

        const providerIds = Object.keys(providers)
        if (providerIds.length === 0) {
            searchInProgress = false
            return;
        }

        const trimmedText = searchText.trim()

        for (var i = 0; i < providerIds.length; i++) {
            const providerId = providerIds[i]
            const providerData = providers[providerId]

            if (shouldQueryProvider(providerData, trimmedText)) {
                activeQueries++
                
                if (providerData.debounceTimer) {
                    // Stop old timer, then restart
                    providerData.debounceTimer.stop()
                    providerData.debounceTimer.restart()
                } else {
                    queryProvider(providerId, searchText, searchGeneration)
                }
            }
        }

        console.log(`[SearchService] Active queries for generation ${searchGeneration}: ${activeQueries}`)

        if (activeQueries === 0) {
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
        
        console.log(`[SearchService] Querying provider ${providerId} for generation ${generation}`)
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
        console.log(`[SearchService] Received ${providerResults.length} results for generation ${generation}. Current generation is ${searchGeneration}.`)
        
        // Ignore stale results
        if (generation !== searchGeneration) {
            console.log(`[SearchService] Discarding stale results for generation ${generation}.`)
            return;
        }

        pendingResults = pendingResults.concat(providerResults)
        activeQueries = Math.max(0, activeQueries - 1)
        console.log(`[SearchService] Handled results. Active queries remaining: ${activeQueries}`)
        
        if (activeQueries < 0) {
            console.error(`[SearchService] ERROR: activeQueries is negative! Resetting to 0.`)
            activeQueries = 0
        }
        
        if (activeQueries === 0) {
            searchInProgress = false
            console.log(`[SearchService] All queries complete for generation ${searchGeneration}.`)
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