import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls.Basic
import Quickshell
import qs.components
import qs.services
import qs.core

Modal {
    id: bluetoothPanelModal
    property bool shouldBeVisible: StateManager.activePanel === "bluetooth"

    contentItem: contentRectangle
    visible: false
    
    onBackgroundClicked: StateManager.activePanel = ""

    function toggle() {
        StateManager.togglePanel("bluetooth")
    }

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            visible = true
            BluetoothService.startDiscovery()
            discoveryTimeoutTimer.start()
        } else {
            BluetoothService.stopDiscovery()
            discoveryTimeoutTimer.stop()
            hideDelayTimer.start()
        }
    }
    
    Timer {
        id: discoveryTimeoutTimer
        interval: 15000 // 15 seconds discovery timeout
        onTriggered: BluetoothService.stopDiscovery()
    }
    
    Timer {
        id: hideDelayTimer
        interval: 200
        onTriggered: bluetoothPanelModal.visible = false
    }

    Rectangle {
        id: contentRectangle
        width: 320
        height: Math.min(600, mainLayout.implicitHeight + 32)
        
        // Position: Bottom Right, align with bluetooth icon (left of wifi)
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: 70
        anchors.rightMargin: 220 
        
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
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Bluetooth"
                    color: FrameTheme.foreground
                    font.family: FrameTheme.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }
                
                Text {
                    text: "sync"
                    font.family: "Material Symbols Rounded"
                    color: FrameTheme.mutedForeground
                    visible: BluetoothService.discovering
                    RotationAnimator on rotation {
                        from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: visible
                    }
                }
            }
            
            // --- TOGGLE ---
            GNToggle {
                Layout.fillWidth: true
                checked: BluetoothService.enabled
                icon: "bluetooth"
                label: "Bluetooth"
                onToggled: BluetoothService.togglePower()
            }
            
            Rectangle { Layout.fillWidth: true; height: 1; color: FrameTheme.border }

            // --- DEVICE LIST ---
            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                visible: BluetoothService.enabled
                
                Text { 
                    text: "Devices" 
                    color: FrameTheme.mutedForeground 
                    font.pixelSize: 12
                }
                
                ListView {
                    Layout.fillWidth: true
                    implicitHeight: Math.min(300, contentItem.childrenRect.height)
                    clip: true
                    model: BluetoothService.knownDevices
                    
                    delegate: FrameButton {
                        width: ListView.view.width
                        centerContent: false
                        variant: modelData.connected ? FrameButton.Variant.Secondary : FrameButton.Variant.Ghost
                        implicitHeight: 40
                        
                        // Device Icon (Generic)
                        Text {
                            text: {
                                if (modelData.iconName === "audio-headset" || modelData.iconName === "audio-card") return "headphones"
                                if (modelData.iconName === "input-keyboard") return "keyboard"
                                if (modelData.iconName === "input-mouse") return "mouse"
                                return "bluetooth"
                            }
                            font.family: "Material Symbols Rounded"
                            color: FrameTheme.foreground
                        }
                        
                        // Name & Battery Info
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            
                            Text {
                                text: modelData.name || modelData.address
                                color: FrameTheme.foreground
                                font.family: FrameTheme.fontFamily
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                font.weight: modelData.connected ? Font.Bold : Font.Normal
                            }
                            
                            // Battery Indicator
                            RowLayout {
                                spacing: 4
                                visible: modelData.batteryAvailable
                                
                                Text {
                                    text: {
                                        const b = modelData.battery;
                                        if (b > 0.8) return "battery_full";
                                        if (b > 0.5) return "battery_5_bar";
                                        if (b > 0.2) return "battery_2_bar";
                                        return "battery_alert";
                                    }
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 12
                                    color: modelData.battery <= 0.2 ? FrameTheme.destructive : FrameTheme.mutedForeground
                                }
                                
                                Text {
                                    text: Math.round(modelData.battery * 100) + "%"
                                    color: FrameTheme.mutedForeground
                                    font.family: FrameTheme.fontFamily
                                    font.pixelSize: 10
                                }
                            }
                        }
                        
                        // Connected Check
                        Text {
                            text: "check"
                            visible: modelData.connected
                            font.family: "Material Symbols Rounded"
                            color: FrameTheme.foreground
                        }
                        
                        onClicked: {
                            if (modelData.connected) BluetoothService.disconnectFromDevice(modelData)
                            else BluetoothService.connectToDevice(modelData)
                        }
                    }
                }
                
                Text {
                    visible: BluetoothService.knownDevices && BluetoothService.knownDevices.length === 0
                    text: "No devices found"
                    color: FrameTheme.mutedForeground
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 16
                    Layout.bottomMargin: 16
                }
            }
            
            Text {
                visible: !BluetoothService.enabled
                text: "Bluetooth is turned off"
                color: FrameTheme.mutedForeground
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
