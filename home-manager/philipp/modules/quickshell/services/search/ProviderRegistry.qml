// services/search/ProviderRegistry.qml
pragma Singleton
import QtQuick
import Quickshell
import qs.services.search.providers
import Qt.labs.folderlistmodel 2.15

Singleton {
    id: root

    // --- Properties ---
    property var providerLoaders: ({})
    property bool allProvidersLoaded: false
    property bool _loadRequested: false

    // --- Dynamic Provider Discovery ---

    // 1. Find all provider QML files
    FolderListModel {
        id: providerFilesModel
        folder: Qt.resolvedUrl("providers/")
        nameFilters: ["*Provider.qml"]
        showDirs: false
    }

    // 2. For each file, create a LazyLoader instance
    Instantiator {
        model: providerFilesModel

        delegate: LazyLoader {
            source: filePath

            Component.onCompleted: {
                const baseName = providerFilesModel.get(index, "fileBaseName");

                // Exclude the base provider itself by simply not adding it to the map.
                if (baseName === "BaseProvider") {
                    return;
                }

                const providerName = baseName.replace("Provider", "").toLowerCase();
                root.providerLoaders[providerName] = this;

                // Check if this is the last expected provider to be instantiated
                const expectedCount = providerFilesModel.count - 1; // -1 for BaseProvider
                if (Object.keys(root.providerLoaders).length === expectedCount) {
                    console.log(`[ProviderRegistry] All ${expectedCount} providers instantiated.`);
                    // If loading was already requested, trigger it now.
                    if (root._loadRequested) {
                        root._activateAllProviders();
                    }
                }
            }
        }
    }

    // --- Private Functions ---
    function _activateAllProviders() {
        if (allProvidersLoaded) return;

        console.log("[ProviderRegistry] Activating all providers...");
        for (const name in providerLoaders) {
            providerLoaders[name].loading = true;
        }

        allProvidersLoaded = true;
        console.log(`[ProviderRegistry] All ${Object.keys(providerLoaders).length} providers are loading in the background.`);
    }

    // --- Public API ---
    function ensureProvidersLoaded() {
        if (allProvidersLoaded) return;
        _loadRequested = true;

        // If discovery and instantiation is already complete, trigger activation now.
        const expectedCount = providerFilesModel.count > 0 ? providerFilesModel.count - 1 : 0;
        if (expectedCount > 0 && Object.keys(providerLoaders).length === expectedCount) {
            _activateAllProviders();
        }
    }

    function loadProvider(name) {
        const loader = providerLoaders[name];
        if (!loader) {
            console.error(`[ProviderRegistry] Unknown provider: ${name}`);
            return null;
        }
        const instance = loader.item;
        if (!instance) {
            console.error(`[ProviderRegistry] Failed to instantiate ${name}.`);
            return null;
        }
        return instance;
    }

    function unloadProvider(name) {
        const loader = providerLoaders[name];
        if (loader && loader.active) {
            loader.active = false;
            console.log(`[ProviderRegistry] Unloaded provider: ${name}`);
        }
    }
}