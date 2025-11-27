import qs.components
import qs.services

QuickSettingButton {
    icon: "night_sight_auto"
    label: "Nachtlicht"
    toggled: NightlightService.enabled
    onClicked: NightlightService.toggle()
}
