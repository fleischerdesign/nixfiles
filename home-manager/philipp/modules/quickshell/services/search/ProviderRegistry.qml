// services/search/ProviderRegistry.qml
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root
    
    // Mapping: Provider-Name → Component
    property var providerComponents: ({
        "app": Qt.createComponent("providers/AppSearchProvider.qml"),
        "calculator": Qt.createComponent("providers/CalculatorProvider.qml"),
        "web": Qt.createComponent("providers/WebSearchProvider.qml"),
        "file": Qt.createComponent("providers/FileSearchProvider.qml"),
        "system": Qt.createComponent("providers/SystemActionProvider.qml"),
        "weather": Qt.createComponent("providers/WeatherProvider.qml")
    })
    
    property var loadedProviders: ({})
    property bool allProvidersLoaded: false
    
    // Lade alle Provider (wird vom AppLauncher aufgerufen)
    function ensureProvidersLoaded() {
        if (allProvidersLoaded) return
        
        console.log("[ProviderRegistry] Loading all providers...")
        
        for (const name in providerComponents) {
            loadProvider(name)
        }
        
        allProvidersLoaded = true
        console.log(`[ProviderRegistry] Loaded ${Object.keys(loadedProviders).length} providers`)
    }
    
    // Lade einzelnen Provider
    function loadProvider(name) {
        if (loadedProviders[name]) return loadedProviders[name]
        
        const component = providerComponents[name]
        if (!component) {
            console.error(`[ProviderRegistry] Unknown provider: ${name}`)
            return null
        }
        
        if (component.status === Component.Error) {
            console.error(`[ProviderRegistry] Error loading ${name}:`, component.errorString())
            return null
        }
        
        const instance = component.createObject(root)
        if (!instance) {
            console.error(`[ProviderRegistry] Failed to instantiate ${name}`)
            return null
        }
        
        loadedProviders[name] = instance
        console.log(`[ProviderRegistry] Loaded provider: ${name}`)
        return instance
    }
    
    // Entlade Provider (z.B. bei niedrigem RAM)
    function unloadProvider(name) {
        if (!loadedProviders[name]) return
        
        loadedProviders[name].destroy()
        delete loadedProviders[name]
        console.log(`[ProviderRegistry] Unloaded provider: ${name}`)
    }
}