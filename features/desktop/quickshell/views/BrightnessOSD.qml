import QtQuick
import Quickshell
import qs.services
import qs.components

Scope {
    id: root

    Connections {
        target: BrightnessService
        function onCurrentBrightnessChanged() {
            osd.shouldShow = true;
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: osd.shouldShow = false
    }

    OSD {
        id: osd
        value: BrightnessService.currentBrightness
        icon: {
            if (BrightnessService.currentBrightness > 0.7) return "brightness_high";
            if (BrightnessService.currentBrightness > 0.3) return "brightness_medium";
            return "brightness_low";
        }
    }
}
