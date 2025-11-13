import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

M3Slider {
    Layout.fillWidth: true
    icon: "brightness_6"
    from: 0.0
    to: 1.0
    value: BrightnessService.currentBrightness
    onValueChanged: BrightnessService.setBrightness(value)
}
