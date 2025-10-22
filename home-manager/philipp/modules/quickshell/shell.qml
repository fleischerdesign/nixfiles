import Quickshell
import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import QtQuick.Layouts

ShellRoot {
    VolumeOSD {}
    BrightnessOSD {}
    Notifications {}

 PanelWindow {
    id: notificationCenter
    anchors {
        right: true
        bottom: true
        top: true
    }
    margins.bottom: 65 + 10
    margins.right: StateManager.notificationCenterOpened ? 10 : -implicitWidth+1
    margins.top: 10
    exclusiveZone: 0
    color: "transparent"
    implicitWidth: 400
    visible: true
    
    Rectangle {
        anchors.fill: parent
        radius: 15
        color: M3ColorPalette.m3SurfaceContainer
        opacity: StateManager.notificationCenterOpened ? 1.0 : 0.0
        
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
            visible: parent.opacity > 0
            
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
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    fixedWidth: true
		    color: M3ColorPalette.m3Primary
		    onColor: M3ColorPalette.m3OnPrimary
                    
                    Text {
                        text: "delete_sweep"
                        color: M3ColorPalette.m3OnPrimary
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 20
                        anchors.centerIn: parent
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            const notifications = StateManager.notificationServer.trackedNotifications.values;
                            for (let i = notifications.length - 1; i >= 0; i--) {
                                notifications[i].dismiss();
                            }
                        }
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
                
                delegate: NotificationItem {
                    width: notificationList.width
                    notification: modelData
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
    
    Behavior on margins.right {
        NumberAnimation {
            duration: 200
            easing.type: Easing.InOutQuad
        }
    }
}

    WlSessionLock {
        id: sessionLocker
        // Surface wird dynamisch basierend auf locked-Status erstellt
        surface: sessionLocker.locked ? lockSurfaceComponent : null
        
        Component {
            id: lockSurfaceComponent
            WlSessionLockSurface {
                color: "transparent"
                Lockscreen {
                    id: lockScreenComponent
                    anchors.fill: parent
                    
                    onUnlocked: {
                        sessionLocker.locked = false;
                    }
                }
            }
        }
    }
    
    IpcHandler {
        target: "lockscreen"
        function lock(): void {
            sessionLocker.locked = true;
        }
    }
    
    BottomBar {
        id: bottomBarWindow
    }
}
