import QtQuick
import qs.services.search as Search

Item {
    id: root
    objectName: "searchProvider"

    // --- Public API for Search.SearchService ---
    // Signal emitted when search results are available.
    signal resultsReady(var resultsArray, int generation)

    // Signal emitted when the provider is ready for queries.
    signal ready

    // --- Optional configuration for the SearchService ---
    // Concrete providers can override this with their specific metadata.
    property var metadata: ({})

    // --- Main query function ---
    // This function must be implemented by concrete provider instances.
    // It is called by the SearchService to perform a search.
    function query(searchText, generation) {
        // Default implementation does nothing.
        console.warn("[BaseProvider] query() not implemented by concrete provider.")
    }

    // --- Lifecycle Management ---
    // Providers are now owned and registered directly by SearchService.
    // Self-registration is no longer needed.
}
