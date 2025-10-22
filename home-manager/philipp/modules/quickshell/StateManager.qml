import QtQuick

// StateManager.qml
// This pragma makes this QML file a singleton, so I can access it from anywhere.
pragma Singleton

// Using a QtObject because this is a non-visual element for state management.
QtObject {
    // Global state properties will be defined here.
    property bool notificationCenterOpened: false
}
