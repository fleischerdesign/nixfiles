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
        } else {
            BluetoothService.stopDiscovery()
            hideDelayTimer.start()
        }
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
            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: FrameTheme.radius
                color: FrameTheme.secondary
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10
                    
                    Text {
                        text: "bluetooth"
                        font.family: "Material Symbols Rounded"
                        color: FrameTheme.foreground
                        font.pixelSize: 20
                    }
                    
                    Text {
                        text: "Bluetooth"
                        color: FrameTheme.foreground
                        font.family: FrameTheme.fontFamily
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }
                    
                    // Toggle Switch
                    Rectangle {
                        width: 40
                        height: 20
                        radius: 10
                        color: BluetoothService.enabled ? FrameTheme.foreground : FrameTheme.muted
                        
                        Rectangle {
                            x: BluetoothService.enabled ? 22 : 2
                            y: 2
                            width: 16
                            height: 16
                            radius: 8
                            color: BluetoothService.enabled ? FrameTheme.background : FrameTheme.foreground
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: BluetoothService.togglePower()
                        }
                    }
                }
            }
            
            Rectangle { Layout.fillWidth: true; height: 1; color: FrameTheme.border }

            // --- DEVICE LIST ---
            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                visible: BluetoothService.enabled
                
                Text { 
                    text: "Paired Devices" 
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
                            text: modelData.iconName === "audio-headset" ? "headphones" : "bluetooth"
                            font.family: "Material Symbols Rounded"
                            color: FrameTheme.foreground
                        }
                        
                        // Name
                        Text {
                            text: modelData.name || modelData.address
                            color: FrameTheme.foreground
                            font.family: FrameTheme.fontFamily
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font.weight: modelData.connected ? Font.Bold : Font.Normal
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
