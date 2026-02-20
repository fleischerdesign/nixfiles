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
    property bool shouldBeVisible: StateManager.activePanel === "audio"

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
        onTriggered: audioPanelModal.visible = false
    }

    Rectangle {
        id: contentRectangle
        width: 320
        height: Math.min(600, mainLayout.implicitHeight + 32)
        
        // Position: Bottom Right
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: 70
        anchors.rightMargin: 70 
        
        // Ensure all pipewire nodes are tracked for property access
        PwObjectTracker {
            objects: Pipewire.nodes
        }

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
                text: "Audio"
                color: FrameTheme.foreground
                font.family: FrameTheme.fontFamily
                font.pixelSize: 16
                font.weight: Font.Bold
            }
            
            // --- MASTER VOLUME ---
            GNSlider {
                Layout.fillWidth: true
                value: AudioService.volume
                active: !AudioService.muted
                icon: AudioService.muted ? "volume_off" : "volume_up"
                label: "Master"
                onMoved: (val) => AudioService.setVolume(val)
                onIconClicked: AudioService.toggleMute()
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
                        visible: modelData && !modelData.isStream && modelData.isSink && modelData.audio
                        height: visible ? 40 : 0
                        
                        PwObjectTracker {
                            objects: [modelData]
                        }

                        FrameButton {
                            anchors.fill: parent
                            anchors.margins: 2
                            variant: Pipewire.defaultAudioSink === modelData ? FrameButton.Variant.Default : FrameButton.Variant.Ghost
                            centerContent: false

                            Text {
                                text: "speaker"
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
                            
                            Text {
                                visible: Pipewire.defaultAudioSink === modelData
                                text: "check"
                                font.family: "Material Symbols Rounded"
                                color: FrameTheme.foreground
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
                    text: "Applications" 
                    color: FrameTheme.mutedForeground
                    font.pixelSize: 12
                }
                
                ListView {
                    id: appsListView
                    Layout.fillWidth: true
                    implicitHeight: Math.min(300, contentItem.childrenRect.height)
                    model: Pipewire.nodes
                    interactive: true
                    clip: true
                    
                    delegate: Item {
                        width: appsListView.width
                        visible: modelData && modelData.isStream && modelData.audio
                        height: visible ? 50 : 0
                        
                        PwObjectTracker {
                            objects: [modelData]
                        }

                        GNSlider {
                            anchors.fill: parent
                            anchors.margins: 4
                            value: (modelData && modelData.audio) ? modelData.audio.volume : 0
                            label: {
                                if (!modelData) return "";
                                const p = modelData.properties;
                                return (p && (p["application.name"] || p["media.name"])) || modelData.description || modelData.name || "App";
                            }
                            onMoved: (val) => {
                                if (modelData && modelData.audio) {
                                    modelData.audio.volume = val
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: appsListView.count === 0
                    text: "No active apps"
                    color: FrameTheme.mutedForeground
                    font.pixelSize: 11
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                }
            }
        }
    }
}
