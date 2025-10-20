import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets

Scope {
    id: root

    // Bind the pipewire node so its volume will be tracked
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Connections {
        target: Pipewire.defaultAudioSink?.audio

        function onVolumeChanged() {
            root.shouldShowOsd = true;
            hideTimer.restart();
        }
    }

    property bool shouldShowOsd: false

    Timer {
        id: hideTimer
        interval: 1000
        onTriggered: root.shouldShowOsd = false
    }

    // The OSD window will be created and destroyed based on shouldShowOsd.
    // PanelWindow.visible could be set instead of using a loader, but using
    // a loader will reduce the memory overhead when the window isn't open.
    LazyLoader {
        active: root.shouldShowOsd

        PanelWindow {
            // Since the panel's screen is unset, it will be picked by the compositor
            // when the window is created. Most compositors pick the current active monitor.

            anchors {
                right: true
            }
            exclusiveZone: 0
	    margins.right: 10
            implicitWidth: 60
            implicitHeight: 300
            color: "transparent"

            // An empty click mask prevents the window from blocking mouse events.
            mask: Region {}

            Rectangle {
                anchors.fill: parent
                radius: 13
                height: 50
                color: "#80000000"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.left: parent.left
                    anchors.topMargin: 15
                    anchors.bottomMargin: 15

                    Rectangle {
                        // Stretches to fill all left-over space
                        Layout.fillHeight: true
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: 10
                        radius: 20
                        color: "#50ffffff"

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            implicitWidth: parent.width
                            implicitHeight: parent.height * (Pipewire.defaultAudioSink?.audio.volume ?? 0)
                            radius: parent.radius

                            Behavior on implicitHeight {
                                NumberAnimation { duration: 100 }
                            }
                        }
                    }

                    Text {
                        text: "clarify"
                        color: "white"
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 24
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }
}
