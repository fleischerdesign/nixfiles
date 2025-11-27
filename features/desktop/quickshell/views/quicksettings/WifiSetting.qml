import qs.components
import qs.services

QuickSettingButton {
    icon: "wifi"
    label: "WLAN"
    toggled: NetworkService.wifiEnabled
    onClicked: NetworkService.toggleWifi()
}
