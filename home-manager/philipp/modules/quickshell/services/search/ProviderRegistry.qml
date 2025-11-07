// services/search/ProviderRegistry.qml
pragma Singleton
import QtQuick
import Quickshell
import qs.services.search.providers as Providers

Singleton {
    id: root

    // Statically declare each provider as a property. This is the clean,
    // declarative, and syntactically valid way to instantiate them.
    property var appSearchProvider: Providers.AppSearchProvider {}
    property var calculatorProvider: Providers.CalculatorProvider {}
    property var fileSearchProvider: Providers.FileSearchProvider {}
    property var systemActionProvider: Providers.SystemActionProvider {}
    property var weatherProvider: Providers.WeatherProvider {}
    property var webSearchProvider: Providers.WebSearchProvider {}

    // The purpose of this singleton is to ensure providers are loaded.
    // By declaring them statically as properties, they are instantiated
    // when this singleton is first accessed. Their `Component.onCompleted`
    // handles registration with the SearchService automatically.

    function load() {
        // This function is a deliberate no-op.
        // Its purpose is to serve as a non-optimizable access point.
        // Calling this function from another component forces the QML engine
        // to instantiate this singleton, which in turn triggers the creation
        // of all static provider properties and their registration.
        // A simple property access like `var _ = Registry` might be optimized
        // away by the engine if the variable is unused. A function call is safer.
    }
}