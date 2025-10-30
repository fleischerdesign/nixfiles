pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- Properties ---
    property bool wifiEnabled: false
    property var wifiNetworks: []
    property bool isScanning: false

    // --- Methods ---
    function refresh() {
        // This will be called to update the network state
        if (isScanning) return;
        getWifiRadioStateProcess.running = true;
        listNetworksProcess.running = true;
    }

    function scan() {
        // This will trigger a new hardware scan for networks
        if (!isScanning && wifiEnabled) {
            isScanning = true;
            scanProcess.running = true;
        }
    }

    // --- Internal Processes ---

    // Long-running process to monitor for any network changes
    Process {
        id: monitorProcess
        running: true
        command: ["nmcli", "monitor"]
        stdout: StdioCollector {
            waitForEnd: false
            onTextChanged: {
                // A change occurred, trigger a refresh
                console.log("NetworkService: Detected network change, refreshing...");
                root.refresh();
            }
        }
    }

    // Process to get the WiFi radio state (enabled/disabled)
    Process {
        id: getWifiRadioStateProcess
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiEnabled = (this.text.trim() === "enabled");
                if (!root.wifiEnabled) {
                    root.wifiNetworks = [];
                }
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.error("NetworkService: Failed to get WiFi radio state. Is nmcli installed and in PATH?");
            }
        }
    }

    // Process to scan for networks (expensive, called by scan())
    Process {
        id: scanProcess
        command: ["nmcli", "dev", "wifi", "rescan"]
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.warn("NetworkService: WiFi scan command failed. May require permissions.");
            }
            // When scan is done, refresh the list
            root.refresh();
        }
    }

    // Process to list the networks found (called by refresh())
    Process {
        id: listNetworksProcess
        command: ["nmcli", "-t", "-f", "SSID,SIGNAL,IN-USE", "dev", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let output = this.text.trim();
                let networks = [];
                if (output) {
                    const lines = output.split('\n');
                    for (const line of lines) {
                        const parts = line.split(':');
                        if (parts.length >= 2) {
                            networks.push({
                                ssid: parts[0],
                                signal: parseInt(parts[1], 10),
                                inUse: parts[2] === '*',
                            });
                        }
                    }
                }
                // Sort networks by signal strength (descending)
                networks.sort((a, b) => b.signal - a.signal);
                root.wifiNetworks = networks;
                root.isScanning = false; // Reset scanning state here
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.error("NetworkService: Failed to list WiFi networks.");
                root.isScanning = false;
            }
        }
    }

    // Initial refresh on component completion
    Component.onCompleted: {
        refresh();
    }
}
