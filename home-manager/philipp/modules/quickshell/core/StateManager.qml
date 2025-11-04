// StateManager.qml
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    property bool notificationCenterOpened: false
    property bool appLauncherOpened: false
    
    property NotificationServer notificationServer: NotificationServer {
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        persistenceSupported: true
        keepOnReload: false
    }
}
