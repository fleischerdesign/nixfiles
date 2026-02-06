import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls.Basic
import Quickshell
import qs.components
import qs.services
import qs.core

Modal {
    id: networkPanelModal
    property bool shouldBeVisible: false

    contentItem: contentRectangle
    visible: false
    
    onBackgroundClicked: networkPanelModal.visible = false

    function toggle() {
        visible = !visible
        if (visible) NetworkService.scan() // Trigger Scan on open
    }

    Rectangle {
        id: contentRectangle
        width: 320
        height: Math.min(600, mainLayout.implicitHeight + 32)
        
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: 70
        anchors.rightMargin: 170
        
        radius: FrameTheme.radius
        color: FrameTheme.popover
        border.width: FrameTheme.borderWidth
        border.color: FrameTheme.border
        
        opacity: networkPanelModal.visible ? 1 : 0
        transform: Translate {
            y: networkPanelModal.visible ? 0 : 10
            Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
        }
        Behavior on opacity { NumberAnimation { duration: 200 } }

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
                    text: "Network"
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
                    visible: NetworkService.isScanning
                    RotationAnimator on rotation {
                        from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: visible
                    }
                }
            }
            
            // --- WIFI TOGGLE ---
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
                        text: "wifi"
                        font.family: "Material Symbols Rounded"
                        color: FrameTheme.foreground
                        font.pixelSize: 20
                    }
                    
                    Text {
                        text: "Wi-Fi"
                        color: FrameTheme.foreground
                        font.family: FrameTheme.fontFamily
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }
                    
                    Rectangle {
                        width: 40
                        height: 20
                        radius: 10
                        color: NetworkService.wifiEnabled ? FrameTheme.foreground : FrameTheme.muted
                        
                        Rectangle {
                            x: NetworkService.wifiEnabled ? 22 : 2
                            y: 2
                            width: 16
                            height: 16
                            radius: 8
                            color: NetworkService.wifiEnabled ? FrameTheme.background : FrameTheme.foreground
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: NetworkService.toggleWifi()
                        }
                    }
                }
            }
            
            Rectangle { Layout.fillWidth: true; height: 1; color: FrameTheme.border }

            // --- NETWORKS LIST ---
            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                visible: NetworkService.wifiEnabled
                
                Text { 
                    text: "Available Networks" 
                    color: FrameTheme.mutedForeground 
                    font.pixelSize: 12
                }
                
                ListView {
                    Layout.fillWidth: true
                    implicitHeight: Math.min(300, contentItem.childrenRect.height)
                    clip: true
                    model: NetworkService.wifiNetworks
                    
                    delegate: FrameButton {
                        width: ListView.view.width
                        centerContent: false
                        variant: modelData.inUse ? FrameButton.Variant.Secondary : FrameButton.Variant.Ghost
                        implicitHeight: 40
                        
                        // Signal Icon
                        Text {
                            text: {
                                const s = modelData.signal
                                if (s >= 75) return "wifi"
                                if (s >= 50) return "wifi_2_bar"
                                return "wifi_1_bar"
                            }
                            font.family: "Material Symbols Rounded"
                            color: FrameTheme.foreground
                        }
                        
                        Text {
                            text: modelData.ssid || "Hidden Network"
                            color: FrameTheme.foreground
                            font.family: FrameTheme.fontFamily
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font.weight: modelData.inUse ? Font.Bold : Font.Normal
                        }
                        
                        Text {
                            text: "check"
                            visible: modelData.inUse
                            font.family: "Material Symbols Rounded"
                            color: FrameTheme.foreground
                        }
                        
                        onClicked: {
                            if (!modelData.inUse) {
                                NetworkService.connect(modelData.ssid)
                            }
                        }
                    }
                }
            }
            
            Text {
                visible: !NetworkService.wifiEnabled
                text: "Wi-Fi is turned off"
                color: FrameTheme.mutedForeground
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
