pragma Singleton
import QtQuick
import Quickshell.Services.Notifications
import Quickshell
import Quickshell.Io // Import Process component

// REINE Business Logic - keine UI-Abhängigkeiten
Singleton {
    id: root
    
    // === PUBLIC API ===
    readonly property alias activePopups: popupsModel
    readonly property int popupCount: popupsModel.count
    readonly property NotificationServer server: notificationServer
    
    signal popupAdded(var notification)
    signal popupDismissed(var notification)
    signal popupRemoved(var notification)

    function send(summary, body, icon) {
        notifyProcess.command = [
            "notify-send",
            "-a", "Quickshell",
            "-i", icon,
            summary,
            body
        ]
        notifyProcess.running = true
    }
    
    // === CONFIGURATION ===
    property int autoHideDelay: 5000  // ms
    property int exitAnimationDuration: 250  // ms
    
    // === DATA MODEL ===
    ListModel {
        id: popupsModel
    }
    
    // === INTERNAL COMPONENTS ===
    NotificationServer {
        id: notificationServer
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        persistenceSupported: true
        keepOnReload: false
        
        onNotification: function(notification) { root.handleNotification(notification) }
    }

    Process {
        id: notifyProcess
    }
    
    // === PRIVATE STATE ===
    property var autoHideTimers: ({})
    
    // === PUBLIC METHODS (for existing notifications) ===
    
    function dismiss(notification) {
        console.log("[NotificationService] Dismiss:", notification.summary);
        
        for (let i = 0; i < popupsModel.count; i++) {
            const item = popupsModel.get(i);
            if (item.notification === notification) {
                // Markiere als dismissing
                popupsModel.setProperty(i, "dismissing", true);
                root.popupDismissed(notification);
                
                // Stoppe Auto-Hide Timer
                stopAutoHideTimer(notification);
                
                // Entferne nach Animation
                scheduleRemoval(notification, root.exitAnimationDuration);
                break;
            }
        }
    }
    
    function dismissAll() {
        console.log("[NotificationService] Dismiss all");
        const notifications = [];
        for (let i = 0; i < popupsModel.count; i++) {
            notifications.push(popupsModel.get(i).notification);
        }
        for (let notification of notifications) {
            dismiss(notification);
        }
    }
    
    function pauseAutoHide(notification) {
        if (autoHideTimers[notification]) {
            autoHideTimers[notification].stop();
        }
    }
    
    function resumeAutoHide(notification) {
        if (autoHideTimers[notification]) {
            autoHideTimers[notification].restart();
        }
    }
    
    function getPopupState(notification) {
        for (let i = 0; i < popupsModel.count; i++) {
            if (popupsModel.get(i).notification === notification) {
                return popupsModel.get(i);
            }
        }
        return null;
    }
    
    // === PRIVATE METHODS ===
    
    function handleNotification(notification) {
        console.log("[NotificationService] Received:", notification.summary);
        
        // Markiere als tracked für NotificationCenter
        notification.tracked = true;
        
        // Füge zum Popup-Model hinzu
        popupsModel.append({
            "notification": notification,
            "dismissing": false,
            "timestamp": Date.now()
        });
        
        root.popupAdded(notification);
        
        // Starte Auto-Hide Timer (außer für resident notifications)
        if (!notification.resident) {
            startAutoHideTimer(notification);
        }
    }
    
    function remove(notification) {
        for (let i = 0; i < popupsModel.count; i++) {
            if (popupsModel.get(i).notification === notification) {
                popupsModel.remove(i);
                root.popupRemoved(notification);
                
                // Cleanup
                stopAutoHideTimer(notification);
                break;
            }
        }
    }
    
    function startAutoHideTimer(notification) {
        const timer = Qt.createQmlObject(`
            import QtQuick
            Timer {
                interval: ${root.autoHideDelay}
                repeat: false
                running: true
            }
        `, root);
        
        timer.triggered.connect(() => {
            dismiss(notification);
            timer.destroy();
            delete autoHideTimers[notification];
        });
        
        autoHideTimers[notification] = timer;
    }
    
    function stopAutoHideTimer(notification) {
        if (autoHideTimers[notification]) {
            autoHideTimers[notification].stop();
            autoHideTimers[notification].destroy();
            delete autoHideTimers[notification];
        }
    }
    
    function scheduleRemoval(notification, delay) {
        const timer = Qt.createQmlObject(`
            import QtQuick
            Timer {
                interval: ${delay}
                repeat: false
                running: true
            }
        `, root);
        
        timer.triggered.connect(() => {
            remove(notification);
            timer.destroy();
        });
    }
}