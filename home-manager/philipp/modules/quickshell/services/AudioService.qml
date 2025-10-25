pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    // Expose read-only properties for volume and mute status.
    // Components should use the methods below to request changes.
    readonly property double volume: Pipewire.defaultAudioSink?.audio.volume ?? 0.0
    readonly property bool muted: Pipewire.defaultAudioSink?.audio.muted ?? false
    property double volumeStep: 0.05 // Configurable step for volume changes

    // Internal Pipewire Handling
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    // Methods for controlling audio
    function setVolume(newVolume) {
        if (Pipewire.defaultAudioSink?.audio) {
            // Clamp the volume between 0.0 and 1.0
            Pipewire.defaultAudioSink.audio.volume = Math.max(0.0, Math.min(1.0, newVolume));
        }
    }

    function increaseVolume() {
        setVolume(volume + volumeStep);
    }



    function decreaseVolume() {
        setVolume(volume - volumeStep);
    }

    function toggleMute() {
        if (Pipewire.defaultAudioSink?.audio) {
            Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted;
        }
    }
}
