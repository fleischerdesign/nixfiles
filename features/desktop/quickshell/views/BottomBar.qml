import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Services.UPower
import qs.core
import qs.components
import qs.components.status
import qs.services
import Quickshell.Wayland

PanelWindow {
    id: bottomBarWindow
    property bool isOpen: false
    
    onIsOpenChanged: StateManager.bottomBarHovered = isOpen

    WlrLayershell.layer: WlrLayer.Top

    signal appLauncherClicked()
    signal volumeClicked()
    signal powerClicked()
    signal wifiClicked()
    signal bluetoothClicked()
    signal notificationClicked()

    Connections {
        target: StateManager
        function onActivePanelChanged() {
            if (StateManager.activePanel !== "") {
                bottomBarWindow.isOpen = true;
            } else if (!windowHover.hovered) {
                closeTimer.start();
            }
        }
    }
    
    implicitHeight: isOpen ? 60 : (contentWrapper.y >= 40 ? 10 : 60) 
    anchors {
        left: true
        right: true
        bottom: true
    }
    exclusiveZone: 0
    color: "transparent"

    Timer {
        id: closeTimer
        interval: 300
        onTriggered: {
            if (StateManager.activePanel === "") {
                bottomBarWindow.isOpen = false;
            }
        }
    }
    
    HoverHandler {
        id: windowHover
        onHoveredChanged: {
            if (hovered) {
                closeTimer.stop();
                bottomBarWindow.isOpen = true;
            } else {
                closeTimer.start();
            }
        }
    }
    
    Item {
        id: clippingRect
        anchors.fill: parent
        clip: false
        
        Item {
            id: contentWrapper
            height: 50
            width: parent.width
            anchors.horizontalCenter: parent.horizontalCenter
            
            opacity: bottomBarWindow.isOpen ? 1 : 0
            y: bottomBarWindow.isOpen ? 0 : 50
            
            Behavior on y {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutExpo
                }
            }
            
            Behavior on opacity { NumberAnimation { duration: 200 } }
            
            MouseArea {
                anchors.fill: parent
                hoverEnabled: false
                propagateComposedEvents: true
                onPressed: (mouse) => mouse.accepted = false
            }

            // --- 1. Launcher Island (Left) ---
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                
                implicitWidth: 50
                implicitHeight: 50
                radius: FrameTheme.radius
                color: FrameTheme.popover
                
                RectangularShadow {
                    anchors.fill: parent
                    y: 4; z: -1
                    color: Qt.rgba(0, 0, 0, 0.3); blur: 15; radius: parent.radius
                }

                FrameButton {
                    anchors.centerIn: parent
                    variant: StateManager.appLauncherOpened ? FrameButton.Variant.Default : FrameButton.Variant.Ghost
                    icon: "apps"
                    onClicked: bottomBarWindow.appLauncherClicked()
                }
            }

            // --- 2. Clock Island (Center) ---
            Rectangle {
                id: clockIsland
                anchors.centerIn: parent
                
                implicitWidth: clockText.implicitWidth + 32
                implicitHeight: 50
                radius: FrameTheme.radius
                color: FrameTheme.popover
                
                RectangularShadow {
                    anchors.fill: parent
                    y: 4; z: -1
                    color: Qt.rgba(0, 0, 0, 0.3); blur: 15; radius: parent.radius
                }

                Text {
                    id: clockText
                    anchors.centerIn: parent
                    color: FrameTheme.foreground
                    font.family: FrameTheme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    
                    Component.onCompleted: updateTime()
                    function updateTime() {
                        const now = new Date();
                        const timeStr = now.toLocaleTimeString(Qt.locale(), "hh:mm");
                        const dateStr = now.toLocaleDateString(Qt.locale(), "ddd, d. MMM");
                        clockText.text = dateStr + "   " + timeStr;
                    }
                    Timer {
                        interval: 1000; running: true; repeat: true
                        onTriggered: parent.updateTime()
                    }
                }
            }

            // --- 2b. Workspace Island (Left of Clock) ---
            Rectangle {
                anchors.right: clockIsland.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                
                implicitWidth: workspaceIndicator.implicitWidth + 24
                implicitHeight: 50
                radius: FrameTheme.radius
                color: FrameTheme.popover
                
                RectangularShadow {
                    anchors.fill: parent
                    y: 4; z: -1
                    color: Qt.rgba(0, 0, 0, 0.3); blur: 15; radius: parent.radius
                }

                WorkspaceIndicator {
                    id: workspaceIndicator
                    anchors.centerIn: parent
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: StateManager.togglePanel("workspaces")
                    onWheel: (wheel) => {
                        if (wheel.angleDelta.y > 0) WorkspaceService.focusPrevious();
                        else WorkspaceService.focusNext();
                    }
                }
            }

            // --- 3. Status Island (Right) ---
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                
                implicitWidth: statusLayout.implicitWidth + 24
                implicitHeight: 50
                radius: FrameTheme.radius
                color: FrameTheme.popover
                
                RectangularShadow {
                    anchors.fill: parent
                    y: 4; z: -1
                    color: Qt.rgba(0, 0, 0, 0.3); blur: 15; radius: parent.radius
                }

                RowLayout {
                    id: statusLayout
                    anchors.centerIn: parent
                    spacing: 2
                    
                    FrameButton {
                        variant: FrameButton.Variant.Ghost
                        implicitWidth: 36
                        content: BluetoothIcon { iconColor: FrameTheme.foreground }
                        onClicked: bottomBarWindow.bluetoothClicked()
                    }
                    
                    FrameButton {
                        variant: FrameButton.Variant.Ghost
                        implicitWidth: 36
                        content: WifiIcon { iconColor: FrameTheme.foreground }
                        onClicked: bottomBarWindow.wifiClicked()
                    }
                    
                    FrameButton {
                        variant: FrameButton.Variant.Ghost
                        implicitWidth: 36
                        content: VolumeIcon { iconColor: FrameTheme.foreground }
                        onClicked: bottomBarWindow.volumeClicked()
                    }
                    
                    FrameButton {
                        visible: UPower.displayDevice && UPower.displayDevice.type === 2
                        variant: FrameButton.Variant.Ghost
                        implicitWidth: 36
                        content: BatteryIcon { iconColor: FrameTheme.foreground }
                        onClicked: bottomBarWindow.powerClicked()
                    }
                    
                    Rectangle {
                        width: 1
                        Layout.fillHeight: true
                        Layout.topMargin: 12
                        Layout.bottomMargin: 12
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        color: FrameTheme.border
                    }

                    FrameButton {
                        variant: FrameButton.Variant.Ghost
                        implicitWidth: 36
                        icon: "notifications"
                        showBadge: NotificationService.server.trackedNotifications.values.length > 0
                        onClicked: bottomBarWindow.notificationClicked()
                    }
                }
            }
        }
    }
}