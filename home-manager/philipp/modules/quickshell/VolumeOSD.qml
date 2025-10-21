import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Scope {
    id: root
    
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }
    
    Connections {
        target: Pipewire.defaultAudioSink?.audio
        
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
            if (Pipewire.defaultAudioSink?.audio.muted) return 0.0;
            return Pipewire.defaultAudioSink?.audio.volume ?? 0.0;
        }
        
        icon: {
            if (Pipewire.defaultAudioSink?.audio.muted) return "no_sound";
            let vol = Pipewire.defaultAudioSink?.audio.volume ?? 0;
            if (vol > 0.0) return "volume_up";
            return "volume_off";
        }
    }
}
