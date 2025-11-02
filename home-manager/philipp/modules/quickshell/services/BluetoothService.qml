pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth

Singleton {
    id: root

    // --- Read-only Properties for Status ---

    // True if the default adapter is enabled.
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false

    // The number of currently connected Bluetooth devices.
    readonly property int connectedDeviceCount: Bluetooth.devices.count

    // True if at least one device is connected.
    readonly property bool devicesConnected: connectedDeviceCount > 0


    // --- Direct API Access ---

    // Exposes the default adapter object for advanced interactions.
    readonly property var defaultAdapter: Bluetooth.defaultAdapter

    // Exposes the live-updating list of connected devices.
    readonly property var devices: Bluetooth.devices


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
}
