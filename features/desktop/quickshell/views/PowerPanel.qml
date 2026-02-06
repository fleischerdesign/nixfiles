import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Services.UPower
import qs.components
import qs.services
import qs.core

Modal {
    id: powerPanelModal
    property bool shouldBeVisible: StateManager.activePanel === "power"

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
        onTriggered: powerPanelModal.visible = false
    }

    Rectangle {
        id: contentRectangle
        width: 320
        implicitHeight: mainLayout.implicitHeight + 32
        
        // Position: Bottom Right, offset for battery icon
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: 70
        anchors.rightMargin: 120 // Offset further left than audio panel
        
        // Frame Style
        radius: FrameTheme.radius
        color: FrameTheme.popover
        border.width: FrameTheme.borderWidth
        border.color: FrameTheme.border
        
        // Animation
        opacity: shouldBeVisible ? 1 : 0
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
            id: mainLayout
            anchors.fill: parent
            anchors.margins: 16
            spacing: 16

            // --- HEADER ---
            Text {
                text: "Power & Energy"
                color: FrameTheme.foreground
                font.family: FrameTheme.fontFamily
                font.pixelSize: 16
                font.weight: Font.Bold
            }
            
            // --- BATTERY STATUS ---
            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                visible: UPower.displayDevice.isPresent
                
                RowLayout {
                    Layout.fillWidth: true
                    
                    // Icon
                    Text {
                        text: {
                            if (UPower.displayDevice.state === UPowerDeviceState.Charging) return "battery_charging_full"
                            const p = UPower.displayDevice.percentage
                            if (p > 0.9) return "battery_full"
                            if (p > 0.6) return "battery_5_bar"
                            if (p > 0.3) return "battery_3_bar"
                            return "battery_1_bar"
                        }
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 24
                        color: FrameTheme.foreground
                    }
                    
                    // Percentage
                    Text {
                        text: Math.round(UPower.displayDevice.percentage * 100) + "%"
                        color: FrameTheme.foreground
                        font.pixelSize: 24
                        font.weight: Font.Bold
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    // Time Remaining
                    Text {
                        text: {
                            const sec = (UPower.displayDevice.state === UPowerDeviceState.Charging) 
                                ? UPower.displayDevice.timeToFull 
                                : UPower.displayDevice.timeToEmpty;
                            
                            if (sec <= 0) return UPower.displayDevice.state === UPowerDeviceState.FullyCharged ? "Charged" : "Estimating..."
                            
                            const h = Math.floor(sec / 3600)
                            const m = Math.floor((sec % 3600) / 60)
                            return (h > 0 ? h + "h " : "") + m + "m"
                        }
                        color: FrameTheme.mutedForeground
                        font.pixelSize: 13
                    }
                }
                
                // Progress Bar
                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: FrameTheme.secondary
                    
                    Rectangle {
                        height: parent.height
                        width: parent.width * UPower.displayDevice.percentage
                        radius: 4
                        color: {
                            if (UPower.displayDevice.state === UPowerDeviceState.Charging) return "#22c55e" // Green
                            if (UPower.displayDevice.percentage < 0.2) return FrameTheme.destructive
                            return FrameTheme.foreground
                        }
                    }
                }
            }
            
            Rectangle { Layout.fillWidth: true; height: 1; color: FrameTheme.border; visible: UPower.displayDevice.isPresent }
            
            // --- POWER PROFILES ---
            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                
                Text { 
                    text: "Performance Profile" 
                    color: FrameTheme.mutedForeground 
                    font.pixelSize: 12
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    // Helper Component for Profile Button
                    component ProfileButton : FrameButton {
                        Layout.fillWidth: true
                        property var profileValue
                        variant: PowerProfiles.profile === profileValue ? FrameButton.Variant.Default : FrameButton.Variant.Outline
                        onClicked: PowerProfiles.profile = profileValue
                    }
                    
                    ProfileButton {
                        text: "Saver"
                        icon: "eco"
                        profileValue: PowerProfile.PowerSaver
                    }
                    
                    ProfileButton {
                        text: "Balanced"
                        icon: "balance"
                        profileValue: PowerProfile.Balanced
                    }
                    
                    ProfileButton {
                        text: "Perf"
                        icon: "bolt"
                        profileValue: PowerProfile.Performance
                        enabled: PowerProfiles.hasPerformanceProfile
                        opacity: enabled ? 1 : 0.5
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: FrameTheme.border }

            // --- BRIGHTNESS ---
            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                visible: BrightnessService.available
                
                Text { 
                    text: "Brightness" 
                    color: FrameTheme.mutedForeground 
                    font.pixelSize: 12
                }
                
                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    
                    Text { 
                        text: {
                            if (BrightnessService.currentBrightness > 0.7) return "brightness_high";
                            if (BrightnessService.currentBrightness > 0.3) return "brightness_medium";
                            return "brightness_low";
                        }
                        font.family: "Material Symbols Rounded"
                        color: FrameTheme.mutedForeground
                        font.pixelSize: 18
                    }
                    
                    // Slider
                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: FrameTheme.secondary
                        
                        Rectangle {
                            height: parent.height
                            width: parent.width * BrightnessService.currentBrightness
                            radius: 3
                            color: FrameTheme.foreground
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onPressed: (mouse) => update(mouse)
                            onPositionChanged: (mouse) => update(mouse)
                            function update(mouse) {
                                BrightnessService.setBrightness(mouse.x / width)
                            }
                        }
                    }
                    
                    Text { 
                        text: Math.round(BrightnessService.currentBrightness * 100) + "%" 
                        color: FrameTheme.foreground 
                        font.pixelSize: 12
                        Layout.preferredWidth: 30
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }
}
