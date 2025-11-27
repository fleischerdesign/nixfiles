pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- Properties ---
    readonly property bool available: p_available
    readonly property real currentBrightness: p_currentBrightness
    readonly property int maxBrightness: p_maxBrightness
    property real brightnessStep: 0.05

    // --- Private Properties ---
    property bool p_available: false
    property real p_currentBrightness: 0.0
    property int p_maxBrightness: 1
    property string p_infoOutput: ""


    // --- IPC Handler for external calls (e.g., from Niri) ---
    IpcHandler {
        target: "brightness"

        function setBrightness(value: real): void {
            root.setBrightness(value);
        }

        function getBrightness(): real {
            return root.currentBrightness;
        }

        function increaseBrightness(step: real): void {
            root.setBrightness(root.p_currentBrightness + (step > 0 ? step : root.brightnessStep));
        }

        function decreaseBrightness(step: real): void {
            root.setBrightness(root.p_currentBrightness - (step > 0 ? step : root.brightnessStep));
        }
    }

    // --- Methods (Internal API) ---
    function setBrightness(value) {
        let clampedValue = Math.max(0.0, Math.min(1.0, value));
        let brightnessValue = Math.round(clampedValue * 100);
        setBrightnessProcess.command = ["brightnessctl", "set", brightnessValue + "%"];
        setBrightnessProcess.running = true;
    }

    function getBrightness() {
        getBrightnessProcess.running = true;
    }

    // Convenience methods for internal use
    function increaseBrightness() {
        setBrightness(p_currentBrightness + brightnessStep);
    }

    function decreaseBrightness() {
        setBrightness(p_currentBrightness - brightnessStep);
    }

    // --- Internal Processes ---
    Process {
        id: setBrightnessProcess
        onExited: (exitCode) => {
            if (exitCode === 0) {
                getBrightness();
            } else {
                console.error(`Error setting brightness: brightnessctl exited with code ${exitCode}`);
            }
        }
    }

    Process {
        id: getBrightnessProcess
        command: ["brightnessctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                let output = this.text.trim();
                if (output) {
                    let currentValue = parseInt(output, 10);
                    const onMaxBrightnessExited = (exitCode) => {
                        if (exitCode === 0 && getMaxBrightnessProcess.stdout.text.trim()) {
                            const maxValue = parseInt(getMaxBrightnessProcess.stdout.text.trim(), 10);
                            if (maxValue > 0) {
                                p_maxBrightness = maxValue;
                                p_currentBrightness = currentValue / p_maxBrightness;
                            }
                        }
                        getMaxBrightnessProcess.exited.disconnect(onMaxBrightnessExited);
                    };
                    getMaxBrightnessProcess.exited.connect(onMaxBrightnessExited);
                    getMaxBrightnessProcess.running = true;
                }
            }
        }
    }

    Process {
        id: getMaxBrightnessProcess
        command: ["brightnessctl", "max"]
        stdout: StdioCollector {}
    }

    Process {
        id: checkAvailabilityProcess
        command: ["brightnessctl", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                p_infoOutput = this.text;
            }
        }
        onExited: (exitCode) => {
            console.log("BrightnessService: checking availability. Exit code: " + exitCode);
            console.log("BrightnessService: brightnessctl info output: " + p_infoOutput);
            if (exitCode === 0 && p_infoOutput.includes("class 'backlight'")) {
                p_available = true;
                getBrightness();
            } else {
                p_available = false;
            }
        }
    }

    Component.onCompleted: {
        checkAvailabilityProcess.running = true;
    }
}
