pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- Public API ---
    readonly property bool enabled: p_enabled
    property int temperature: 4000

    // --- Private State ---
    property bool p_enabled: false

    // --- Public Methods ---
    function toggle() {
        if (p_enabled) {
            // If it's enabled, try to stop it.
            stopNightlightProcess.running = true;
        } else {
            // If it's disabled, try to start it.
            startNightlightProcess.command = ["wlsunset", "-t", root.temperature.toString()];
            startNightlightProcess.running = true;
        }
    }

    // --- Internal Processes ---

    Process {
        id: startNightlightProcess
        // wlsunset is a long-running process. We update the state as soon as it starts.
        onRunningChanged: {
            if (running) {
                p_enabled = true;
            }
        }
        // This will be called if the process fails to start or is killed externally.
        onExited: (exitCode) => {
            // If the process exits, it's no longer enabled.
            // This handles both startup errors and external kills.
            if (p_enabled) {
                p_enabled = false;
            }
            if (exitCode !== 0) {
                console.warn("NightlightService: wlsunset process exited with code: " + exitCode);
            }
        }
    }

    Process {
        id: stopNightlightProcess
        command: ["pkill", "wlsunset"]
        // This process always exits.
        onExited: (exitCode) => {
            // If pkill runs, we assume wlsunset is stopped.
            // So, we should set p_enabled to false directly.
            p_enabled = false;
            if (exitCode > 1) { // 0 = killed, 1 = not found
                 console.error("NightlightService: pkill exited with error code " + exitCode);
            }
        }
    }

    Process {
        id: checkStatusProcess
        command: ["pgrep", "wlsunset"]
        onExited: (exitCode) => {
            // pgrep exits 0 if a process is found, 1 if not.
            p_enabled = (exitCode === 0);
        }
    }

    // --- Initialization ---
    Component.onCompleted: {
        checkStatusProcess.running = true;
    }
}