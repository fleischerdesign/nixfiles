import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.components
import qs.modules
import qs.core
import qs.services

PanelWindow {
    id: notificationCenter

    // This property is controlled by shell.qml
    property bool shouldBeVisible: false

    // Initial visual properties
    implicitWidth: 400
    color: "transparent"
    visible: false // Initially invisible
    exclusiveZone: 0
    anchors {
        right: true
        bottom: true
        top: true
    }
    margins.bottom: 65 + 10
    margins.top: 10
    // margins.right is now controlled by the state machine

    // The visible content
    Rectangle {
        id: contentRectangle
        anchors.fill: parent
        radius: 15
        color: Colors.palette.m3SurfaceContainer
        // opacity is now controlled by the state machine

    // State Machine
    state: "CLOSED"

    states: [
        State {
            name: "OPEN"
            when: shouldBeVisible
            PropertyChanges { target: notificationCenter; visible: true }
            PropertyChanges { target: notificationCenter; margins.right: 10 }
            PropertyChanges { target: contentRectangle; opacity: 1.0 }
        },
        State {
            name: "CLOSED"
            when: !shouldBeVisible
            // Property values for the closed state are set by the exit transition
        }
    ]

    transitions: [
        Transition { // To OPEN state
            from: "CLOSED"; to: "OPEN"
            ParallelAnimation {
                NumberAnimation { target: notificationCenter; property: "margins.right"; duration: 200; easing.type: Easing.InOutQuad }
                NumberAnimation { target: contentRectangle; property: "opacity"; duration: 200; easing.type: Easing.InOutQuad }
            }
        },
        Transition { // To CLOSED state
            from: "OPEN"; to: "CLOSED"
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation { target: notificationCenter; property: "margins.right"; to: -notificationCenter.implicitWidth + 1; duration: 200; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: contentRectangle; property: "opacity"; to: 0.0; duration: 200; easing.type: Easing.InOutQuad }
                }
                // After animation, set window to invisible
                PropertyAction { target: notificationCenter; property: "visible"; value: false }
            }
        }
    ]

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 10
            visible: contentRectangle.opacity > 0
            
            // Header
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
		  colorRole: RippleButton.ColorRole.Error
                    onClicked: {
                        const notifications = StateManager.notificationServer.trackedNotifications.values;
                        for (let i = notifications.length - 1; i >= 0; i--) {
                            notifications[i].dismiss();
                        }
                    }

                    Text {
                        text: "delete_sweep"
                        color: parent.contentColor
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 20
                        anchors.centerIn: parent
                    }
                }
            }
            
            // Notification List
            ListView {
                id: notificationList
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                clip: true
                model: StateManager.notificationServer.trackedNotifications
                
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
