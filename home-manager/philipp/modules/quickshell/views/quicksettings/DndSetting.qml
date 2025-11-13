import qs.components
import qs.core

QuickSettingButton {
    icon: StateManager.dndEnabled ? "notifications_off" : "notifications"
    label: "Nicht stören"
    toggled: StateManager.dndEnabled
    onClicked: StateManager.dndEnabled = !StateManager.dndEnabled
}
