// StateManager.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    property string activePanel: "" // "", "launcher", "notifications", "audio", "power", "network", "bluetooth"
    
    // Read-only aliases for backward compatibility in components
    readonly property bool appLauncherOpened: activePanel === "launcher"
    readonly property bool notificationCenterOpened: activePanel === "notifications"
    
    property bool bottomBarHovered: false 
    property int notificationCount: 0 
    property bool dndEnabled: false
    
    function togglePanel(name) {
        if (activePanel === name) activePanel = "";
        else activePanel = name;
    }

    function closeAll() {
        activePanel = "";
    }

    property NotificationServer notificationServer: NotificationServer {
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        persistenceSupported: true
        keepOnReload: false
    }
}
