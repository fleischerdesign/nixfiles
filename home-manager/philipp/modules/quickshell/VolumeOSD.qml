import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets

Scope {
    id: root
    
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }
    
    Connections {
        target: Pipewire.defaultAudioSink?.audio
        function onVolumeChanged() {
            root.shouldShowOsd = true;
            hideTimer.restart();
        }
        
        function onMutedChanged() {
            root.shouldShowOsd = true;
            hideTimer.restart();
        }
    }
    
    property bool shouldShowOsd: false
    
    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: root.shouldShowOsd = false
    }
    
    PanelWindow {
        id: osdContainer
        anchors {
            right: true
            // Vertikal zentriert
            top: true
            bottom: true
        }
        margins.right: 0  // KEINE Margin, damit nichts abgeschnitten wird
        width: 60 + 20  // Breite + Slide-Distanz + extra Padding
        height: 300
        color: "transparent"
	mask: Region {}
	exclusiveZone: 0
        
        Rectangle {
            id: osdContent
            width: 60
            height: 300
            // Vertikal zentriert im Container
            anchors.verticalCenter: parent.verticalCenter
            
            // Slide-Animation - startet von rechts außerhalb
            x: shouldShowOsd ? 10 : (parent.width)  // 10px Abstand vom Rand wenn sichtbar
            
            Behavior on x {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }
            
            opacity: shouldShowOsd ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }
            
            radius: 13
            color: "#000000"
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 10
                
                Rectangle {
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignHCenter
                    width: 10
                    radius: 5
                    color: "#50ffffff"
                    
                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
			height: Pipewire.defaultAudioSink?.audio.muted ? 0 : parent.height * (Pipewire.defaultAudioSink?.audio.volume ?? 0)
                        radius: parent.radius
                        color: "#ffffff"
                        
                        Behavior on height {
                            NumberAnimation { 
                                duration: 100
                                easing.type: Easing.OutQuad
                            }
                        }
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                    }
                }
                
                Text {
                    text: {
                        if (Pipewire.defaultAudioSink?.audio.muted) return "no_sound"
                        let vol = Pipewire.defaultAudioSink?.audio.volume ?? 0
                        if (vol > 0.0) return "volume_up"
                        return "volume_off"
                    }
                    color: "white"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 24
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
