import QtQuick
import qs.services

Text {
    property color iconColor: ColorService.palette.m3OnSurface

    font.family: "Material Symbols Rounded"
    font.pixelSize: 18
    color: iconColor

    text: {
        if (!BluetoothService.enabled) {
            return "bluetooth_disabled";
        }
        if (BluetoothService.devicesConnected) {
            return "bluetooth_connected";
        }
        return "bluetooth";
    }
}
