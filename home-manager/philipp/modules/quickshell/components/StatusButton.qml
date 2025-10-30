import QtQuick
import QtQuick.Layouts
import qs.core // Für StateManager
import qs.components
import qs.components.status
import qs.services
import Quickshell.Services.UPower // Import für Batterie-Service

M3Button {
    id: root

    property bool notificationCenterOpened: StateManager.notificationCenterOpened

    style: notificationCenterOpened
        ? M3Button.Style.Filled
        : M3Button.Style.FilledTonal
    colorRole: notificationCenterOpened
        ? M3Button.ColorRole.Primary
        : M3Button.ColorRole.Surface
    
    implicitHeight: 55

    Connections {
        target: StateManager
        function onNotificationCenterOpenedChanged() {
            root.notificationCenterOpened = StateManager.notificationCenterOpened;
        }
    }

    readonly property color _iconColor: root.notificationCenterOpened ? ColorService.palette.m3OnPrimary : ColorService.palette.m3OnSurface

    RowLayout {
        id: statusIcons
        spacing: 8

        WifiIcon {
            iconColor: root._iconColor
        }

        VolumeIcon {
            iconColor: root._iconColor
        }

        BatteryIcon {
            iconColor: root._iconColor
        }
    }
}
