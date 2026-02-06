import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.components
import qs.services
import qs.core
import QtQuick.Controls.Basic
import Quickshell.Io
import qs.views

// NotificationCenter.qml - Frame Shell Edition
Modal {
    id: notificationCenterModal

    property bool shouldBeVisible: StateManager.activePanel === "notifications"

    contentItem: contentRectangle
    visible: false
    onBackgroundClicked: StateManager.activePanel = ""

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            visible = true
        } else {
            hideDelayTimer.start()
        }
    }
    
    Timer {
        id: hideDelayTimer
        interval: 200
        onTriggered: notificationCenterModal.visible = false
    }

    Rectangle {
        id: contentRectangle
        width: 400
        height: 500 // Max height

        anchors {
            bottom: parent.bottom
            right: parent.right
            rightMargin: 20
            bottomMargin: 70
        }
        
        // Visuals
        radius: FrameTheme.radius
        color: FrameTheme.background // Dark
        border.width: FrameTheme.borderWidth
        border.color: FrameTheme.border
        
        // Animation
        opacity: shouldBeVisible ? 1.0 : 0
        transform: Translate {
            y: shouldBeVisible ? 0 : 10
            Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
        }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Shadow
        RectangularShadow {
            width: parent.width; height: parent.height
            y: 4; z: -1
            color: Qt.rgba(0, 0, 0, 0.3); blur: 20; radius: parent.radius
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "Notifications"
                    color: FrameTheme.foreground
                    font.family: FrameTheme.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }

                FrameButton {
                    variant: FrameButton.Variant.Ghost
                    icon: "delete_sweep"
                    text: "Clear"
                    visible: notificationList.count > 0
                    onClicked: {
                        const notifications = NotificationService.server.trackedNotifications.values;
                        for (let i = notifications.length - 1; i >= 0; i--) {
                            notifications[i].dismiss();
                        }
                    }
                }
            }
            
            // Separator
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: FrameTheme.border
            }

            // List
            ListView {
                id: notificationList
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                clip: true
                model: NotificationService.server.trackedNotifications

                delegate: NotificationCard {
                    width: notificationList.width
                    notification: modelData
                    onDismissRequested: modelData.dismiss()
                    isInNotificationCenter: true
                }

                Text {
                    anchors.centerIn: parent
                    visible: notificationList.count === 0
                    text: "No new notifications"
                    color: FrameTheme.mutedForeground
                    font.family: FrameTheme.fontFamily
                    font.pixelSize: 14
                }
                
                ScrollBar.vertical: ScrollBar {
                    width: 4
                    active: notificationList.moving || notificationList.flickableItem.contentHeight > notificationList.height
                    background: Rectangle { color: "transparent" }
                    contentItem: Rectangle {
                        radius: 2
                        color: FrameTheme.mutedForeground
                        opacity: 0.5
                    }
                }
            }
        }
    }
}