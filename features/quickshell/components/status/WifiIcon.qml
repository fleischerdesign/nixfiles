import QtQuick
import qs.services

Text {
    property color iconColor: ColorService.palette.m3OnSurface

    readonly property var _currentNetwork: {
        if (!NetworkService.wifiEnabled) return null;
        for (const net of NetworkService.wifiNetworks) {
            if (net.inUse) return net;
        }
        return null;
    }

    text: {
        if (!_currentNetwork) {
            return "wifi_off";
        }
        if (_currentNetwork.signal >= 50) {
            return "wifi";
        }
        if (_currentNetwork.signal >= 25) {
            return "wifi_2_bar";
        }
        return "wifi_1_bar";
    }

    font.family: "Material Symbols Rounded"
    font.pixelSize: 18
    color: iconColor
}
