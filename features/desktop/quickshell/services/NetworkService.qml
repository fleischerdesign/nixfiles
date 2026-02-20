pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- Properties ---
    property bool wifiEnabled: false
    property var wifiNetworks: []
    property bool ethernetConnected: false
    property bool isScanning: false

    // --- Methods ---
    function refresh() {
        // This will be called to update the network state
        getWifiRadioStateProcess.running = true;
        getEthernetStateProcess.running = true;
        
        // Only refresh the list if we're not already doing a full hardware scan
        // If a scan is in progress, listNetworksProcess will be started when it finishes.
        if (!isScanning) {
            listNetworksProcess.running = true;
        }
    }

    function scan() {
        // This will trigger a new hardware scan for networks
        if (!isScanning && wifiEnabled) {
            isScanning = true;
            scanProcess.running = true;
        }
    }

    function toggleWifi() {
        const command = wifiEnabled ? "off" : "on";
        toggleWifiProcess.command = ["nmcli", "radio", "wifi", command];
        toggleWifiProcess.running = true;
    }

    function connect(ssid) {
        console.log("NetworkService: Connecting to " + ssid);
        connectProcess.command = ["nmcli", "dev", "wifi", "connect", ssid];
        connectProcess.running = true;
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
                // Use a timer or debounce if this is too frequent
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
                console.error("NetworkService: Failed to get WiFi radio state.");
            }
        }
    }

    // Process to get the Ethernet connection state
    Process {
        id: getEthernetStateProcess
        command: ["nmcli", "-t", "-f", "TYPE,STATE", "d", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let output = this.text.trim();
                let isConnected = false;
                if (output) {
                    const lines = output.split('\n');
                    for (const line of lines) {
                        const parts = line.split(':');
                        if (parts.length >= 2 && parts[0] === 'ethernet' && parts[1] === 'connected') {
                            isConnected = true;
                            break;
                        }
                    }
                }
                root.ethernetConnected = isConnected;
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.error("NetworkService: Failed to get Ethernet state.");
            }
        }
    }

    // Process to scan for networks (expensive, called by scan())
    Process {
        id: scanProcess
        command: ["nmcli", "dev", "wifi", "rescan"]
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.warn("NetworkService: WiFi scan command failed.");
            }
            // When scan is done, get the list
            listNetworksProcess.running = true;
        }
    }

    // Process to list the networks found (called by refresh() or scanProcess)
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
                        if (parts.length >= 3) {
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
                root.isScanning = false; 
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.error("NetworkService: Failed to list WiFi networks.");
            }
            root.isScanning = false;
        }
    }

    Process {
        id: toggleWifiProcess
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.error("NetworkService: Failed to toggle WiFi state.");
            }
            // Refresh state after command execution
            root.refresh();
        }
    }

    Process {
        id: connectProcess
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.error("NetworkService: Connection attempt failed. (Exit Code: " + exitCode + ")");
            } else {
                console.log("NetworkService: Connected successfully.");
                root.refresh();
            }
        }
    }

    // Initial refresh on component completion
    Component.onCompleted: {
        refresh();
    }
}
