import QtQuick
import qs.services
import qs.services.search as Search

BaseProvider {
    id: root

    function createResultFromData(weatherData, location) {
        const current = weatherData.current_condition[0];
        const area = weatherData.nearest_area[0];
        const weatherDesc = current.weatherDesc[0].value;

        return {
            "name": `Wetter für ${area.areaName[0].value}, ${area.country[0].value}`,
            "priority": 90,
            "icon": {
                "type": "fontIcon",
                "source": getIconForWeatherDesc(weatherDesc),
                "fontFamily": "Material Symbols Rounded"
            },
            "genericName": `${weatherDesc}, ${current.temp_C}°C (Gefühlt ${current.FeelsLikeC}°C)`,
            "actionObject": {
                "type": "url",
                "url": (() => {
                    console.log("DEBUG: Location in createResultFromData: " + location);
                    const url = "https://www.google.com/search?q=wetter+" + encodeURIComponent(location);
                    console.log("DEBUG: Constructed URL (Google Weather): " + url);
                    return url;
                })()
            },
        };
    }

    function getIconForWeatherDesc(weatherDesc) {
        const desc = weatherDesc.toLowerCase();
        if (desc.includes("sunny") || desc.includes("clear")) return "light_mode";
        if (desc.includes("partly cloudy")) return "partly_cloudy";
        if (desc.includes("cloudy") || desc.includes("overcast")) return "cloud";
        if (desc.includes("mist") || desc.includes("fog")) return "foggy";
        if (desc.includes("patchy rain") || desc.includes("light rain") || desc.includes("drizzle")) return "rainy";
        if (desc.includes("rain") || desc.includes("shower")) return "rainy";
        if (desc.includes("thunder")) return "thunderstorm";
        if (desc.includes("snow") || desc.includes("sleet") || desc.includes("blizzard")) return "weather_snowy";
        return "device_thermostat";
    }

    property var metadata: ({ "debounce": 300, "trigger": "wetter" })

    function query(searchText, generation) {
        const trimmedText = searchText.trim().toLowerCase();
        const parts = trimmedText.split(/\s+/);

        // The Search.SearchService already ensures this provider is only called when the
        // search text starts with "wetter". We can safely parse the location.
        const location = parts.length <= 1 ? "Neubrandenburg" : parts.slice(1).join(" ");

        // Call the service and provide a callback function to handle the result.
        WeatherService.getWeatherFor(location, function(data) {
            // This callback will be executed when the data is ready.
            if (data) {
                const result = createResultFromData(data, location);
                resultsReady([result], generation);
            } else {
                // The fetch failed or returned no data.
                resultsReady([], generation);
            }
        });
    }
}