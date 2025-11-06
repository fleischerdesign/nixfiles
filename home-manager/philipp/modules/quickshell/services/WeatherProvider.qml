import QtQuick
import qs.services

Item {
    id: root

    signal resultsReady(var resultsArray, int generation)
    signal ready

    Component.onCompleted: {
        SearchService.registerProvider(root)
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
            "entryObject": Qt.createQmlObject('import QtQuick; QtObject { function execute() {} }', root)
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

    function query(searchText, generation) {
        const trimmedText = searchText.trim().toLowerCase();
        const parts = trimmedText.split(/\s+/);

        if (parts[0] !== "wetter") {
            resultsReady([], generation);
            return;
        }

        let location = (parts.length === 1) ? "Neubrandenburg" : parts.slice(1).join(" ");

        // Call the service and provide a callback function to handle the result.
        WeatherService.getWeatherFor(location, function(data) {
            // This callback will be executed when the data is ready.
            // The 'generation' variable is available here because of closure.
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