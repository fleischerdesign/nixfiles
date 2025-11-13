import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

M3Slider {
    Layout.fillWidth: true
    icon: AudioService.muted ? "volume_off" : "volume_up"
    from: 0.0
    to: 1.0
    value: AudioService.volume
    toggled: !AudioService.muted

    onValueChanged: {
        AudioService.setVolume(value)
        if (AudioService.muted && value > 0) {
            AudioService.toggleMute()
        }
    }
    onIconClicked: {
        AudioService.toggleMute()
    }
}
