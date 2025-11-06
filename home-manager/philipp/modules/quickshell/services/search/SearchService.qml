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
                provider.query(searchText, searchGeneration)
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

        const providerIds = Object.keys(providers)
        if (providerIds.length === 0) {
            searchInProgress = false
            return;
        }

        activeQueries = providerIds.length
        const trimmedText = searchText.trim()

        for (var i = 0; i < providerIds.length; i++) {
            const providerId = providerIds[i]
            const providerData = providers[providerId]
            const provider = providerData.instance
            const metadata = providerData.metadata

            var shouldQuery = true;

            if (metadata.minLength && trimmedText.length < metadata.minLength) {
                shouldQuery = false;
            }

            if (shouldQuery && metadata.trigger) {
                if (!trimmedText.toLowerCase().startsWith(metadata.trigger)) {
                    shouldQuery = false
                }
            }
            
            if (shouldQuery && metadata.regex) {
                const regex = new RegExp(metadata.regex, 'i')
                if (!regex.test(trimmedText)) {
                    shouldQuery = false
                }
            }

            if (shouldQuery) {
                if (providerData.debounceTimer) {
                    providerData.debounceTimer.restart()
                } else {
                    provider.query(searchText, searchGeneration)
                }
            } else {
                activeQueries--
            }
        }

        if (activeQueries === 0) {
            searchInProgress = false
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
