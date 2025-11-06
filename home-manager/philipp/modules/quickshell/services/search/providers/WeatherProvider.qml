import QtQuick
import qs.services
import qs.services.search as Search

Item {
    id: root

    signal resultsReady(var resultsArray, int generation)
    signal ready

    Component.onCompleted: {
        Search.SearchService.registerProvider(root)
        ready()
    }

    function createResultFromData(weatherData) {
        const current = weatherData.current_condition[0];
        const area = weatherData.nearest_area[0];
        const weatherDesc = current.weatherDesc[0].value;

        return {
            "name": `Wetter für ${area.areaName[0].value}, ${area.country[0].value}`,
            "priority": 90,
            "icon": {
                "type": "fontIcon",
                "source": getIconForWeatherDesc(weatherDesc),
                "fontFamily": "monospace"
            },
            "genericName": `${weatherDesc}, ${current.temp_C}°C (Gefühlt ${current.FeelsLikeC}°C)`,
            "actionObject": {
                "type": "noAction"
            }
        };
    }

    function getIconForWeatherDesc(weatherDesc) {
        const desc = weatherDesc.toLowerCase();
        if (desc.includes("sunny") || desc.includes("clear")) return "☀️";
        if (desc.includes("partly cloudy")) return "⛅️";
        if (desc.includes("cloudy")) return "☁️";
        if (desc.includes("overcast")) return "☁️";
        if (desc.includes("mist") || desc.includes("fog")) return "🌫️";
        if (desc.includes("patchy rain") || desc.includes("light rain") || desc.includes("drizzle")) return "🌦️";
        if (desc.includes("rain") || desc.includes("shower")) return "🌧️";
        if (desc.includes("thunder")) return "⛈️";
        if (desc.includes("snow") || desc.includes("sleet") || desc.includes("blizzard")) return "❄️";
        return "🌡️";
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
                const result = createResultFromData(data);
                resultsReady([result], generation);
            } else {
                // The fetch failed or returned no data.
                resultsReady([], generation);
            }
        });
    }
}