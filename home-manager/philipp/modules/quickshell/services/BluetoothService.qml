pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth

Singleton {
    id: root

    // --- Read-only Properties for Status ---

    // True if the default adapter is enabled.
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false

    // True if the adapter is scanning for new devices
    readonly property bool discovering: Bluetooth.defaultAdapter?.discovering ?? false

    // The number of currently connected Bluetooth devices.
    readonly property int connectedDeviceCount: Bluetooth.devices?.count ?? 0

    // True if at least one device is connected.
    readonly property bool devicesConnected: connectedDeviceCount > 0


    // --- Direct API Access ---

    // Exposes the default adapter object for advanced interactions.
    readonly property var defaultAdapter: Bluetooth.defaultAdapter

    // Exposes the live-updating list of connected devices.
    readonly property var devices: Bluetooth.devices

    // Exposes the live-updating list of all known devices for the default adapter.
    readonly property var knownDevices: Bluetooth.defaultAdapter?.devices


    // --- Control Methods ---

    /**
     * Toggles the power state of the default Bluetooth adapter.
     */
    function togglePower() {
        if (Bluetooth.defaultAdapter) {
            Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
        }
    }

    /**
     * Enables the default Bluetooth adapter.
     */
    function enable() {
        if (Bluetooth.defaultAdapter) {
            Bluetooth.defaultAdapter.enabled = true;
        }
    }

    /**
     * Disables the default Bluetooth adapter.
     */
    function disable() {
        if (Bluetooth.defaultAdapter) {
            Bluetooth.defaultAdapter.enabled = false;
        }
    }

    /**
     * Starts scanning for new Bluetooth devices.
     */
    function startDiscovery() {
        if (Bluetooth.defaultAdapter) {
            Bluetooth.defaultAdapter.discovering = true;
        }
    }

    /**
     * Stops scanning for new Bluetooth devices.
     */
    function stopDiscovery() {
        if (Bluetooth.defaultAdapter) {
            Bluetooth.defaultAdapter.discovering = false;
        }
    }


    // --- Device Control Methods ---

    /**
     * Connects to a specific Bluetooth device.
     * @param device The BluetoothDevice object to connect to.
     */
    function connectToDevice(device) {
        if (device && typeof device.connect === 'function') {
            device.connect();
        }
    }

    /**
     * Disconnects from a specific Bluetooth device.
     * @param device The BluetoothDevice object to disconnect from.
     */
    function disconnectFromDevice(device) {
        if (device && typeof device.disconnect === 'function') {
            device.disconnect();
        }
    }

    /**
     * Forgets a specific Bluetooth device (unpairs).
     * @param device The BluetoothDevice object to forget.
     */
    function forgetDevice(device) {
        if (device && typeof device.forget === 'function') {
            device.forget();
        }
    }
}
