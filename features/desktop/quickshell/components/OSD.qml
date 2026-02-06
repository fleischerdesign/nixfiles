import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components
import qs.core

// OSD.qml - Frame Shell Edition
Scope {
    id: root
    
    // Public API
    property bool shouldShow: false
    property real value: 0.0
    property string icon: "circle"
    property color barColor: FrameTheme.foreground
    
    PanelWindow {
        id: osdContainer
        
        // Position: Bottom centered area
        anchors {
            bottom: true
            left: true
            right: true
        }
        implicitHeight: 200 
        color: "transparent"
        
        // Ensure it's above other layers
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0
        mask: Region {} 

        Rectangle {
            id: osdContent
            width: 220
            height: 48
            
            // Adaptive Positioning Logic
            readonly property bool barActive: StateManager.bottomBarHovered || StateManager.appLauncherOpened || StateManager.notificationCenterOpened
            readonly property int targetMargin: barActive ? 80 : 20
            
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.shouldShow ? targetMargin : (targetMargin - 20)
            
            // Visuals
            color: FrameTheme.popover
            radius: FrameTheme.radius
            border.width: FrameTheme.borderWidth
            border.color: FrameTheme.border
            
            // Animation
            opacity: root.shouldShow ? 1.0 : 0.0
            
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Behavior on anchors.bottomMargin { 
                NumberAnimation { duration: 250; easing.type: Easing.OutExpo } 
            }

            // Shadow
            RectangularShadow {
                width: parent.width; height: parent.height
                y: 4; z: -1
                color: Qt.rgba(0, 0, 0, 0.3); blur: 16; radius: parent.radius
            }

            RowLayout {
                anchors.centerIn: parent
                width: parent.width - 32 // Keep horizontal padding
                spacing: 12
                
                // Icon
                Text {
                    text: root.icon
                    color: FrameTheme.foreground
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 20
                    Layout.alignment: Qt.AlignVCenter // Fix alignment
                }
                
                // Horizontal Bar
                Rectangle {
                    Layout.fillWidth: true
                    height: 6
                    radius: 3
                    color: FrameTheme.secondary 
                    Layout.alignment: Qt.AlignVCenter // Fix alignment
                    
                    Rectangle {
                        height: parent.height
                        width: parent.width * Math.max(0, Math.min(1, root.value))
                        radius: parent.radius
                        color: FrameTheme.foreground
                        
                        Behavior on width {
                            NumberAnimation { duration: 50; easing.type: Easing.OutQuad } 
                        }
                    }
                }
                
                // Value Text (Optional, 0-100%)
                Text {
                    text: Math.round(root.value * 100) + "%"
                    color: FrameTheme.mutedForeground
                    font.family: FrameTheme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    Layout.preferredWidth: 30
                    horizontalAlignment: Text.AlignRight
                    Layout.alignment: Qt.AlignVCenter // Fix alignment
                }
            }
        }
    }
}