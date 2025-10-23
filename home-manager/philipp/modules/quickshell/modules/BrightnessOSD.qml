import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules

Scope {
    id: root

    property real currentBrightness: 0.0
    property int maxBrightness: 1


    IpcHandler {
        id: brightness
        target: "brightness"

        function setBrightness(value: real): void {
            let brightnessValue = Math.round(value * 100);
            setBrightnessProcess.command = ["brightnessctl", "set", brightnessValue + "%"];
            setBrightnessProcess.running = true;
            root.currentBrightness = value;
            osd.shouldShow = true;
            hideTimer.restart();
        }

        function getBrightness(): real {
            getBrightnessProcess.running = true;
            return root.currentBrightness;
        }

        function increaseBrightness(step: real): void {
            let newBrightness = root.currentBrightness + step;
            if (newBrightness > 1.0) {
                newBrightness = 1.0;
            }
            setBrightness(newBrightness);
        }

        function decreaseBrightness(step: real): void {
            let newBrightness = root.currentBrightness - step;
            if (newBrightness < 0.0) {
                newBrightness = 0.0;
            }
            setBrightness(newBrightness);
        }
    }

    Process {
        id: setBrightnessProcess
        onExited: (exitCode) => {
            if (exitCode !== 0) {
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
                    // We need max brightness to calculate percentage
                    const onMaxBrightnessExited = (exitCode) => {
                        if (exitCode === 0 && getMaxBrightnessProcess.stdout.text.trim()) {
                            const maxValue = parseInt(getMaxBrightnessProcess.stdout.text.trim(), 10);
                            if (maxValue > 0) {
                                root.maxBrightness = maxValue;
                                root.currentBrightness = currentValue / root.maxBrightness;
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

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: osd.shouldShow = false
    }

    GenericOSD {
        id: osd
        value: root.currentBrightness
        icon: {
            if (root.currentBrightness > 0.7) return "brightness_high";
            if (root.currentBrightness > 0.3) return "brightness_medium";
            return "brightness_low";
        }
    }

    Component.onCompleted: {
        brightness.getBrightness();
    }
}
