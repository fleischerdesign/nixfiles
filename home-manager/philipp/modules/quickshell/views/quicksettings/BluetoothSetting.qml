import qs.components
import qs.services

QuickSettingButton {
    icon: "bluetooth"
    label: "Bluetooth"
    toggled: BluetoothService.enabled
    onClicked: BluetoothService.togglePower()
}
