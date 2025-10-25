import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.modules
import qs.services
import qs.core

PanelWindow {
    id: notificationCenter

    property bool shouldBeVisible: false
    property var interceptor: null

    Component {
        id: interceptorComponent
        ClickInterceptor {}
    }

    Connections {
        target: StateManager
        function onNotificationCenterOpenedChanged() {
            if (StateManager.notificationCenterOpened) {
                if (interceptor === null) {
                    interceptor = interceptorComponent.createObject(notificationCenter);
                    interceptor.clicked.connect(function() {
                        StateManager.notificationCenterOpened = false;
                    });

                    // Wait for the interceptor's window to actually be visible
                    // before showing the notification center. This ensures the NC
                    // is rendered on top of the interceptor.
                    var connection = interceptor.backingWindowVisibleChanged.connect(function() {
                        if (interceptor.backingWindowVisible) {
                            notificationCenter.shouldBeVisible = true;
                            // Disconnect to prevent this from firing again
                            interceptor.backingWindowVisibleChanged.disconnect(connection);
                        }
                    });

                    // Make the interceptor visible, which starts the process.
                    interceptor.visible = true;
                }
            } else {
                // Hide the notification center first
                notificationCenter.shouldBeVisible = false;

                // Then destroy the interceptor
                if (interceptor !== null) {
                    interceptor.destroy();
                    interceptor = null;
                }
            }
        }
    }

    implicitWidth: 400
    color: "transparent"
    visible: false
    anchors {
        right: true
        bottom: true
        top: true
    }
    margins.bottom: 65 + 10
    margins.top: 10
    margins.right: shouldBeVisible ? 10 : -implicitWidth + 1
    exclusiveZone: 0
    
    Behavior on margins.right {
        NumberAnimation {
            id: animation
            duration: 200
            easing.type: Easing.InOutQuad
            onRunningChanged: {
                if (!running && !shouldBeVisible) {
                    visible = false
                }
            }
        }
    }
    
    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            visible = true
            NotificationService.dismissAll();
        }
    }

    Rectangle {
        id: contentRectangle
        anchors.fill: parent
        radius: 15
        color: ColorService.palette.m3SurfaceContainer
        opacity: shouldBeVisible ? 1.0 : 0.0
        
        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 10
            visible: contentRectangle.opacity > 0
            
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                
                Text {
                    text: "Benachrichtigungen"
                    color: "white"
                    font.pixelSize: 18
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }
                
                RippleButton {
                    style: RippleButton.Style.Filled
                    colorRole: RippleButton.ColorRole.Primary
                    onClicked: {
                        const notifications = NotificationService.server.trackedNotifications.values;
                        for (let i = notifications.length - 1; i >= 0; i--) {
                            notifications[i].dismiss();
                        }
                    }

                    Text {
                        text: "delete_sweep"
                        color: parent.autoContentColor
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 20
                        anchors.centerIn: parent
                    }
                }
            }
            
            ListView {
                id: notificationList
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                clip: true
                model: NotificationService.server.trackedNotifications
                
                delegate: NotificationPopup {
                    width: notificationList.width
                    notification: modelData
                    onDismissRequested: modelData.dismiss()
                    isInNotificationCenter: true
                }
                
                Text {
                    anchors.centerIn: parent
                    visible: notificationList.count === 0
                    text: "Keine Benachrichtigungen"
                    color: "#888"
                    font.pixelSize: 14
                }
            }
        }
    }
}