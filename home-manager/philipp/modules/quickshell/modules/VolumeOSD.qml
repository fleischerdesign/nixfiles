import QtQuick
import Quickshell
import qs.services
import qs.modules

Scope {
    id: root

    Connections {
        target: AudioService

        function onVolumeChanged() {
            osd.shouldShow = true;
            hideTimer.restart();
        }

        function onMutedChanged() {
            osd.shouldShow = true;
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: osd.shouldShow = false
    }

    GenericOSD {
        id: osd

        value: {
            if (AudioService.muted) return 0.0;
            return AudioService.volume;
        }

        icon: {
            if (AudioService.muted) return "no_sound";
            if (AudioService.volume > 0.0) return "volume_up";
            return "volume_off";
        }
    }
}
