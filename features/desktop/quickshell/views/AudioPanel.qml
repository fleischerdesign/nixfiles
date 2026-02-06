import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Services.Pipewire
import qs.components
import qs.services
import qs.core

Modal {
    id: audioPanelModal
    property bool shouldBeVisible: false

    contentItem: contentRectangle
    visible: false
    
    onBackgroundClicked: audioPanelModal.visible = false

    // Function to toggle visibility (called from BottomBar)
    function toggle() {
        visible = !visible
    }

    Rectangle {
        id: contentRectangle
        width: 320
        height: Math.min(600, mainLayout.implicitHeight + 32)
        
        // Position: Bottom Right, slightly offset to align with volume icon
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: 70
        anchors.rightMargin: 70 // Offset from right edge to align with volume button
        
        // Frame Style
        radius: FrameTheme.radius
        color: FrameTheme.popover
        border.width: FrameTheme.borderWidth
        border.color: FrameTheme.border
        
        // Animation
        opacity: audioPanelModal.visible ? 1 : 0
        transform: Translate {
            y: audioPanelModal.visible ? 0 : 10
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
                text: "Audio"
                color: FrameTheme.foreground
                font.family: FrameTheme.fontFamily
                font.pixelSize: 16
                font.weight: Font.Bold
            }
            
            // --- MASTER VOLUME ---
            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                
                RowLayout {
                    Layout.fillWidth: true
                    Text { 
                        text: "Master" 
                        color: FrameTheme.mutedForeground 
                        font.pixelSize: 12
                    }
                    Item { Layout.fillWidth: true }
                    Text { 
                        text: Math.round(AudioService.volume * 100) + "%" 
                        color: FrameTheme.foreground 
                        font.pixelSize: 12
                    }
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    FrameButton {
                        variant: FrameButton.Variant.Ghost
                        icon: AudioService.muted ? "volume_off" : "volume_up"
                        onClicked: AudioService.toggleMute()
                    }
                    
                    // Custom Slider (Rectangle based) because native Slider is hard to style perfectly
                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: FrameTheme.secondary
                        
                        Rectangle {
                            height: parent.height
                            width: parent.width * AudioService.volume
                            radius: 3
                            color: FrameTheme.foreground
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onPressed: (mouse) => updateVolume(mouse)
                            onPositionChanged: (mouse) => updateVolume(mouse)
                            function updateVolume(mouse) {
                                AudioService.setVolume(mouse.x / width)
                            }
                        }
                    }
                }
            }
            
            Rectangle { Layout.fillWidth: true; height: 1; color: FrameTheme.border }
            
            // --- OUTPUT DEVICES ---
            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                
                Text { 
                    text: "Output Devices" 
                    color: FrameTheme.mutedForeground 
                    font.pixelSize: 12
                }
                
                ListView {
                    Layout.fillWidth: true
                    implicitHeight: contentItem.childrenRect.height
                    model: Pipewire.nodes
                    interactive: false
                    
                    delegate: Item {
                        width: ListView.view.width
                        // Filter: !isStream && isSink && audio
                        visible: modelData && !modelData.isStream && modelData.isSink && modelData.audio
                        height: visible ? 40 : 0
                        
                        // Tracker to bind properties
                        PwObjectTracker {
                            objects: [modelData]
                        }

                        FrameButton {
                            anchors.fill: parent
                            anchors.margins: 2
                            variant: Pipewire.defaultAudioSink === modelData ? FrameButton.Variant.Secondary : FrameButton.Variant.Ghost
                            
                            // Content
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8
                                
                                Text {
                                    text: "speaker" // TODO: Detect icon based on media.class or properties
                                    font.family: "Material Symbols Rounded"
                                    color: FrameTheme.foreground
                                }
                                
                                Text {
                                    text: modelData.description || modelData.name || "Unknown Device"
                                    color: FrameTheme.foreground
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                // Checkmark
                                Text {
                                    visible: Pipewire.defaultAudioSink === modelData
                                    text: "check"
                                    font.family: "Material Symbols Rounded"
                                    color: FrameTheme.foreground
                                }
                            }
                            
                            onClicked: Pipewire.preferredDefaultAudioSink = modelData
                        }
                    }
                }
            }
            
            Rectangle { Layout.fillWidth: true; height: 1; color: FrameTheme.border }

            // --- APP MIXER ---
            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                
                Text { 
                    text: "Apps" 
                    color: FrameTheme.mutedForeground 
                    font.pixelSize: 12
                }
                
                ListView {
                    Layout.fillWidth: true
                    implicitHeight: Math.min(200, contentItem.childrenRect.height) // Max height with scroll
                    clip: true
                    model: Pipewire.nodes
                    interactive: true
                    
                    delegate: Item {
                        width: ListView.view.width
                        // Filter: isStream && !isSink && audio
                        visible: modelData && modelData.isStream && !modelData.isSink && modelData.audio
                        height: visible ? 50 : 0
                        
                        PwObjectTracker {
                            objects: [modelData]
                        }

                        RowLayout {
                            anchors.fill: parent
                            spacing: 8
                            
                            // App Icon / Name
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: modelData.name || "Unknown App"
                                    color: FrameTheme.foreground
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            
                            // Volume Slider
                            Rectangle {
                                Layout.preferredWidth: 80
                                height: 4
                                radius: 2
                                color: FrameTheme.secondary
                                
                                Rectangle {
                                    height: parent.height
                                    width: parent.width * (modelData.audio ? modelData.audio.volume : 0)
                                    radius: 2
                                    color: FrameTheme.foreground
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: (mouse) => updateAppVolume(mouse)
                                    onPositionChanged: (mouse) => updateAppVolume(mouse)
                                    function updateAppVolume(mouse) {
                                        if (modelData.audio) {
                                            modelData.audio.volume = Math.max(0, Math.min(1, mouse.x / width))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
