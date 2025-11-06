pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    property var cache: ({})
    property int ttl: 30 * 60 * 1000 // 30 minutes
    property var _fetching: ({})

    // Main function to be called by providers.
    // It gets weather data for a location and executes the callback when data is ready.
    function getWeatherFor(location, callback) {
        const locationKey = location.toLowerCase();
        const cachedItem = cache[locationKey];

        // If we have fresh data, return it immediately via the callback.
        if (cachedItem && (Date.now() - cachedItem.timestamp < ttl)) {
            console.log(`[WeatherService] Returning fresh cache for ${locationKey} via callback.`);
            // Use Qt.callLater to ensure the callback is always called asynchronously
            Qt.callLater(callback, cachedItem.data);
            return;
        }

        // If a fetch is already in progress for this location, we can ignore the new request
        // as the pending one will eventually serve a result (which might be picked up by a future query).
        if (_fetching[locationKey]) {
            console.log(`[WeatherService] Fetch already in progress for ${locationKey}. Ignoring duplicate request.`);
            // To fulfill the contract, we should still call the callback, but with no data.
            Qt.callLater(callback, null);
            return;
        }

        _fetching[locationKey] = true;
        console.log(`[WeatherService] No fresh cache for ${locationKey}. Fetching...`);
        var xhr = new XMLHttpRequest();

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                let responseData = null;
                if (xhr.status === 200) {
                    try {
                        const response = JSON.parse(xhr.responseText);
                        responseData = response;

                        var newCache = Object.assign({}, root.cache);
                        newCache[locationKey] = {
                            "timestamp": Date.now(),
                            "data": response
                        };
                        root.cache = newCache;
                        console.log(`[WeatherService] Fetched and cached new weather for ${locationKey}.`);
                    } catch (e) {
                        console.log("[WeatherService] Error parsing JSON: " + e);
                    }
                } else {
                    console.log(`[WeatherService] Fetch failed for ${locationKey} with status: ` + xhr.statusText);
                }

                // Execute the callback with the result (or null on failure)
                callback(responseData);
                delete _fetching[locationKey];
            }
        }

        const url = `https://wttr.in/${encodeURIComponent(locationKey)}?format=j1`;
        xhr.open("GET", url);
        xhr.send();
    }
}
