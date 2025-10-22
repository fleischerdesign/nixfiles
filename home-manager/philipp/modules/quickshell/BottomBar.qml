import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Quickshell.Io

PanelWindow {
    id: bottomBarWindow
    property bool isOpen: false
    
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
                    if (!hovered) {
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
                        color: "#99000000"
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
                
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    iconText: "home"
                    fixedWidth: true
                }
                
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    iconText: "apps"
                    fixedWidth: true
                }
                
                Item {
                    Layout.fillWidth: true
                }
                
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    iconSize: 12
                    iconFamily: "Roboto"
                    fixedWidth: true
                    
                    Component.onCompleted: {
                        const now = new Date();
                        const hours = String(now.getHours()).padStart(2, '0');
                        const minutes = String(now.getMinutes()).padStart(2, '0');
                        iconText = hours + "\n" + minutes;
                    }
                    
                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        onTriggered: {
                            const now = new Date();
                            const hours = String(now.getHours()).padStart(2, '0');
                            const minutes = String(now.getMinutes()).padStart(2, '0');
                            parent.iconText = hours + "\n" + minutes;
                        }
                    }
                }
                
                RippleButton {
                    id: batteryButton
                    Layout.alignment: Qt.AlignVCenter
                    visible: UPower.displayDevice && UPower.displayDevice.type === 2
                    iconFamily: "Material Symbols Outlined"
                    iconSize: 20
                    fixedWidth: true
                    iconText: {
                        if (!UPower.displayDevice || !UPower.displayDevice.ready) {
                            return "battery_unknown";
                        }
                        const percent = Math.round(UPower.displayDevice.percentage * 100);
                        const charging = UPower.displayDevice.state === 1;
                        if (charging)
                            return "battery_android_bolt";
                        if (percent > 87)
                            return "battery_android_full";
                        if (percent > 75)
                            return "battery_android_6";
                        if (percent > 62)
                            return "battery_android_5";
                        if (percent > 50)
                            return "battery_android_4";
                        if (percent > 37)
                            return "battery_android_3";
                        if (percent > 25)
                            return "battery_android_2";
                        if (percent > 12.5)
                            return "battery_android_1";
                        return "battery_android_0";
                    }
                }
                
                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    iconText: "clarify"
                    fixedWidth: true
                }
            }
        }
    }
}
