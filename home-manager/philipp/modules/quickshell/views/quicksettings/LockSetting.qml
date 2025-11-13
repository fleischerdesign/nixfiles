import qs.components
import Quickshell.Io

QuickSettingButton {
    icon: "lock"
    label: "Sperren"
    onClicked: sessionLocker.locked = true
}
