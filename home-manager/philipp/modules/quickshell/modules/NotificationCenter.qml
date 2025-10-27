import QtQuick
import QtQuick.Layouts
import qs.components
import qs.modules
import qs.services
import qs.core

Modal {
    id: notificationCenterModal

    property bool shouldBeVisible: false

    contentItem: contentRectangle
    visible: false
    onBackgroundClicked: {
        StateManager.notificationCenterOpened = false;
    }

    Connections {
        target: StateManager
        function onNotificationCenterOpenedChanged() {
            shouldBeVisible = StateManager.notificationCenterOpened;
        }
    }

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            visible = true
            NotificationService.dismissAll();
        } else {
            // A short delay to allow the closing animation to finish
            var timer = Qt.createQmlObject("import QtQuick; Timer {interval: 200; onTriggered: { notificationCenterModal.visible = false; } }", notificationCenterModal);
            timer.start();
        }
    }

    Rectangle {
        id: contentRectangle
        width: 400
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
            bottomMargin: 65 + 10
            topMargin: 10
            rightMargin: shouldBeVisible ? 10 : -width
        }
        
        Behavior on anchors.rightMargin {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }
        
        radius: 15
        color: ColorService.palette.m3SurfaceContainer
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 10
            
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
