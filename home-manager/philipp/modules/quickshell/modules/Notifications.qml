import Quickshell
import QtQuick
import qs.core

Scope {
    id: root

    property var activePopups: []

    Connections {
        target: StateManager.notificationServer

        function onNotification(notification) {
            console.log("Notification received:", notification.summary);
            notification.tracked = true;

            // Erstelle ein eigenes PanelWindow für diese Notification
            const windowComponent = Qt.createComponent("NotificationPopupWindow.qml");
            if (windowComponent.status === Component.Ready) {
                const popupWindow = windowComponent.createObject(root, {
                    notification: notification,
                    popupIndex: activePopups.length
                });

                if (popupWindow) {
                    console.log("Popup window created successfully");
                    activePopups.push(popupWindow);

                    // Cleanup on dismiss
                    popupWindow.dismissed.connect(() => {
                        const index = activePopups.indexOf(popupWindow);
                        if (index !== -1) {
                            activePopups.splice(index, 1);
                            // Update positions of remaining popups
                            for (let i = 0; i < activePopups.length; i++) {
                                activePopups[i].popupIndex = i;
                            }
                        }
                        popupWindow.destroy(300);
                    });
                } else {
                    console.error("Failed to create popup window");
                }
            } else if (windowComponent.status === Component.Error) {
                console.error("Component error:", windowComponent.errorString());
            }
        }
    }
}
