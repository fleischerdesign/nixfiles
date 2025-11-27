import QtQuick
import Quickshell.Services.UPower
import qs.services

Text {
    property color iconColor: ColorService.palette.m3OnSurface

    visible: UPower.displayDevice && UPower.displayDevice.type === 2
    font.family: "Material Symbols Rounded"
    font.pixelSize: 18
    color: iconColor

    text: {
        if (!UPower.displayDevice || !UPower.displayDevice.ready) {
            return "battery_unknown";
        }
        const percent = Math.round(UPower.displayDevice.percentage * 100);
        const charging = UPower.displayDevice.state === 1;
        
        if (charging)
            return "battery_charging_full";
        if (percent > 87)
            return "battery_full";
        if (percent > 75)
            return "battery_6_bar";
        if (percent > 62)
            return "battery_5_bar";
        if (percent > 50)
            return "battery_4_bar";
        if (percent > 37)
            return "battery_3_bar";
        if (percent > 25)
            return "battery_2_bar";
        if (percent > 12.5)
            return "battery_1_bar";
        return "battery_0_bar";
    }
}
