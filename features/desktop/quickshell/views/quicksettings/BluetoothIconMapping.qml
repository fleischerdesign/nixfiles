// views/quicksettings/BluetoothIconMapping.qml
pragma Singleton
import QtQuick

QtObject {
    function getMaterialIcon(apiIconName) {
        switch (apiIconName) {
            case "audio-headset":
                return "headset";
            case "audio-headphones":
                return "headphones";
            case "input-mouse":
                return "mouse";
            case "input-keyboard":
                return "keyboard";
            case "input-gaming":
                return "sports_esports";
            case "phone":
                return "smartphone";
            case "computer":
                return "computer";
            // Add more mappings here as they are discovered
            default:
                // Return a generic device icon
                return "devices";
        }
    }
}
