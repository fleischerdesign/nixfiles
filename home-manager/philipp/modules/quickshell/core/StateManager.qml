// StateManager.qml
pragma Singleton
import QtQuick
import Quickshell.Services.Notifications

QtObject {
    property bool notificationCenterOpened: false
    
    property NotificationServer notificationServer: NotificationServer {
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        persistenceSupported: true
        keepOnReload: false
    }
}
