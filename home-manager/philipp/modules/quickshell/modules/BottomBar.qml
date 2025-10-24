import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.core
import qs.components
import qs.services

PanelWindow {
    id: bottomBarWindow
    property bool isOpen: false

    Connections {
        target: StateManager
        function onNotificationCenterOpenedChanged() {
            if (!StateManager.notificationCenterOpened && !barHover.hovered) {
                bottomBarWindow.isOpen = false;
            }
        }
    }
    
    // Dynamische Höhe: klein wenn geschlossen, groß wenn offen
    implicitHeight: isOpen ? 65 : (contentWrapper.y >= 55 ? 10 : 65) 
    anchors {
        left: true
        right: true
        bottom: true
    }
    exclusiveZone: 0
    color: "transparent"
    
    // HoverHandler für die Trigger-Zone
    HoverHandler {
        id: triggerHover
        onHoveredChanged: {
            if (hovered) {
                bottomBarWindow.isOpen = true;
            }
        }
    }
    
    // Content-Wrapper mit Clip
    Item {
        id: clippingRect
        anchors.fill: parent
        clip: true
        
        Item {
            id: contentWrapper
            height: 65
            width: parent.width
            opacity: bottomBarWindow.isOpen ? 1 : 0
            y: bottomBarWindow.isOpen ? 0 : 55
            
            Behavior on y {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.InOutQuad
                }
            }
            
            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }
            
            // HoverHandler für die geöffnete Bar
            HoverHandler {
                id: barHover
                onHoveredChanged: {
                    if (!hovered && !StateManager.notificationCenterOpened) {
                        bottomBarWindow.isOpen = false;
                    }
                }
            }
            
            // MouseArea nur für Event-Propagation zu Buttons
            MouseArea {
                anchors.fill: parent
                hoverEnabled: false
                propagateComposedEvents: true
                onPressed: function(mouse) {
                    mouse.accepted = false;
                }
            }
            
            // Shadow Gradient
            Rectangle {
                id: shadow
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: "#00000000"
                    }
                    GradientStop {
                        position: 1.0
                        color: "#88000000"
                    }
                }
            }
            
            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 10
                    rightMargin: 10
                    bottomMargin: 10
                }
                spacing: 10
                
                // App Launcher Button
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    style: RippleButton.Style.FilledTonal
                    colorRole: RippleButton.ColorRole.Surface
                    icon: "apps"
                    iconOnly: true
                    fixedWidth: true
                    implicitHeight: 55
                }
                
                Item {
                    Layout.fillWidth: true
                }
                
                // Clock Button
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    style: RippleButton.Style.FilledTonal
                    colorRole: RippleButton.ColorRole.Surface
                    fixedWidth: true
                    implicitHeight: 55
                    
                    // Custom content für zweizeilige Uhr
                    Text {
                        id: clockText
                        color: ColorService.palette.m3OnSurface
                        font.pixelSize: 12
                        font.family: "Roboto"
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        
                        Component.onCompleted: {
                            const now = new Date();
                            const hours = String(now.getHours()).padStart(2, '0');
                            const minutes = String(now.getMinutes()).padStart(2, '0');
                            clockText.text = hours + "\n" + minutes;
                        }
                        
                        Timer {
                            interval: 1000
                            running: true
                            repeat: true
                            onTriggered: {
                                const now = new Date();
                                const hours = String(now.getHours()).padStart(2, '0');
                                const minutes = String(now.getMinutes()).padStart(2, '0');
                                clockText.text = hours + "\n" + minutes;
                            }
                        }
                    }
                }
                
                // Battery Button
                RippleButton {
                    id: batteryButton
                    Layout.alignment: Qt.AlignVCenter
                    visible: UPower.displayDevice && UPower.displayDevice.type === 2
                    style: RippleButton.Style.FilledTonal
                    colorRole: RippleButton.ColorRole.Surface
                    fixedWidth: true
                    implicitHeight: 55
                    iconSize: 20
                    iconOnly: true
                    
                    icon: {
                        if (!UPower.displayDevice || !UPower.displayDevice.ready) {
                            return "battery_unknown";
                        }
                        const percent = Math.round(UPower.displayDevice.percentage * 100);
                        const charging = UPower.displayDevice.state === 1;
                        
                        if (charging)
                            return "battery_charging_full";
                        if (percent > 87)
                            return "battery_full";
                        if (percent > 75)
                            return "battery_6_bar";
                        if (percent > 62)
                            return "battery_5_bar";
                        if (percent > 50)
                            return "battery_4_bar";
                        if (percent > 37)
                            return "battery_3_bar";
                        if (percent > 25)
                            return "battery_2_bar";
                        if (percent > 12.5)
                            return "battery_1_bar";
                        return "battery_0_bar";
                    }
                }
                
                // Notification Center Button
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    style: StateManager.notificationCenterOpened 
                        ? RippleButton.Style.Filled 
                        : RippleButton.Style.FilledTonal
                    colorRole: StateManager.notificationCenterOpened 
                        ? RippleButton.ColorRole.Primary 
                        : RippleButton.ColorRole.Surface
                    icon: "notifications"
                    iconOnly: true
                    fixedWidth: true
                    implicitHeight: 55
                    
                    onClicked: {
                        StateManager.notificationCenterOpened = !StateManager.notificationCenterOpened
                    }
                }
            }
        }
    }
}
