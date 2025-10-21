import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property real currentBrightness: 0.0
    property int maxBrightness: 1
    property bool errorLogged: false

    Process {
        id: maxBrightnessReader
        command: ["brightnessctl", "max"]

        stdout: StdioCollector {
            onStreamFinished: {
                let output = this.text.trim();
                if (output) {
                    let maxValue = parseInt(output, 10);
                    if (maxValue > 0) {
                        root.maxBrightness = maxValue;
                    }
                    console.log("Max brightness set to:", root.maxBrightness);
                    
                    currentBrightnessReader.running = true;
                    pollTimer.running = true;
                } else {
                     console.error("Error on 'brightnessctl max': No output");
                }
            }
        }

        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.error(`Error: 'brightnessctl max' exited with code: ${exitCode}`);
            }
        }
    }

    Process {
        id: currentBrightnessReader
        command: ["brightnessctl", "get"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.maxBrightness > 0) {
                    let output = this.text.trim();
                    if (output) {
                        let currentValue = parseInt(output, 10);
                        root.currentBrightness = currentValue / root.maxBrightness;
                    }
                }
            }
        }
    }

    Timer {
        id: pollTimer
        interval: 50
        repeat: true
        running: false
        property real lastBrightness: -1.0
        onTriggered: {
            currentBrightnessReader.running = true;
        }
    }

    onCurrentBrightnessChanged: {
        if (pollTimer.lastBrightness < 0.0) {
            pollTimer.lastBrightness = currentBrightness;
            return;
        }
        if (Math.abs(currentBrightness - pollTimer.lastBrightness) > 0.01) {
            console.log("Brightness change detected:", currentBrightness);
            osd.shouldShow = true;
            hideTimer.restart();
            pollTimer.lastBrightness = currentBrightness;
        }
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
        maxBrightnessReader.running = true;
    }
}
