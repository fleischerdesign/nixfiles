import QtQuick
import QtQuick.Layouts
import qs.core // Für StateManager
import qs.components
import qs.services
import Quickshell.Services.UPower // Import für Batterie-Service

RippleButton {
    id: root

    property bool notificationCenterOpened: StateManager.notificationCenterOpened

    style: notificationCenterOpened
        ? RippleButton.Style.Filled
        : RippleButton.Style.FilledTonal
    colorRole: notificationCenterOpened
        ? RippleButton.ColorRole.Primary
        : RippleButton.ColorRole.Surface
    
    implicitHeight: 55

    Connections {
        target: StateManager
        function onNotificationCenterOpenedChanged() {
            root.notificationCenterOpened = StateManager.notificationCenterOpened;
        }
    }

    RowLayout {
        id: statusIcons
        anchors.centerIn: parent
        spacing: 8

        Text {
            text: "wifi" // Placeholder
            font.family: "Material Symbols Rounded"
            font.pixelSize: 18
            color: root.notificationCenterOpened ? ColorService.palette.m3OnPrimary : ColorService.palette.m3OnSurface
        }

        Text {
            text: AudioService.muted ? "volume_off" : "volume_up"
            font.family: "Material Symbols Rounded"
            font.pixelSize: 18
            color: root.notificationCenterOpened ? ColorService.palette.m3OnPrimary : ColorService.palette.m3OnSurface
        }

        // Batterie-Icon
        Text {
            visible: UPower.displayDevice && UPower.displayDevice.type === 2 // Sichtbarkeit nur für das Icon
            font.family: "Material Symbols Rounded"
            font.pixelSize: 18
            color: root.notificationCenterOpened ? ColorService.palette.m3OnPrimary : ColorService.palette.m3OnSurface
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
    }
}
