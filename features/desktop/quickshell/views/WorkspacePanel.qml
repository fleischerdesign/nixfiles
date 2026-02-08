import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Widgets
import qs.components
import qs.services
import qs.core

Modal {
    id: workspacesPanelModal
    property bool shouldBeVisible: StateManager.activePanel === "workspaces"

    contentItem: contentRectangle
    visible: false
    
    onBackgroundClicked: StateManager.activePanel = ""

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            visible = true
            WorkspaceService.refresh()
        } else {
            hideDelayTimer.start()
        }
    }
    
    Timer {
        id: hideDelayTimer
        interval: 200
        onTriggered: workspacesPanelModal.visible = false
    }

    Rectangle {
        id: contentRectangle
        width: Math.min(parent.width * 0.95, mainLayout.implicitWidth + 40)
        height: 240
        
        // Position: Bottom
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 80
        
        // Frame Style (Activities-like shelf)
        radius: 24
        color: Qt.rgba(0.12, 0.12, 0.12, 0.8) // Dark translucent
        
        // Animation
        opacity: shouldBeVisible ? 1 : 0
        scale: shouldBeVisible ? 1 : 0.95
        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: 250 } }

        // Shadow
        RectangularShadow {
            anchors.fill: parent
            y: 10; z: -1
            color: Qt.rgba(0, 0, 0, 0.5); blur: 40; radius: parent.radius
        }

        RowLayout {
            id: mainLayout
            height: parent.height - 40
            anchors.centerIn: parent
            spacing: 24

            Repeater {
                model: WorkspaceService.workspaces
                
                delegate: Rectangle {
                    id: workspaceCard
                    Layout.preferredWidth: 200
                    Layout.fillHeight: true
                    radius: 12
                    color: modelData.is_active ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    border.width: 2
                    border.color: modelData.is_active ? FrameTheme.primary : "transparent"
                    
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    // Interaction
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: WorkspaceService.focusWorkspace(modelData.idx)
                        onEntered: if (!modelData.is_active) workspaceCard.color = Qt.rgba(1, 1, 1, 0.05)
                        onExited: if (!modelData.is_active) workspaceCard.color = "transparent"
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12
                        
                        // Workspace Preview Area
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 6
                            color: "#1a1a1a" // Mini desktop background
                            clip: true
                            
                            // Schematic Windows
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                height: parent.height * 0.7
                                
                                Repeater {
                                    model: {
                                        const wsWindows = [];
                                        for (const win of WorkspaceService.windows) {
                                            if (win.workspace_id === modelData.id) wsWindows.push(win);
                                        }
                                        return wsWindows;
                                    }
                                    
                                    delegate: Rectangle {
                                        Layout.preferredWidth: 40
                                        Layout.fillHeight: true
                                        radius: 2
                                        color: modelData.is_focused ? FrameTheme.primary : "#333333"
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.1)
                                        
                                        IconImage {
                                            anchors.centerIn: parent
                                            width: 16; height: 16
                                            source: "image://icon/" + modelData.app_id
                                            visible: modelData.app_id !== null
                                            opacity: 0.8
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            text: "Workspace " + modelData.idx
                            Layout.alignment: Qt.AlignHCenter
                            color: modelData.is_active ? FrameTheme.foreground : FrameTheme.mutedForeground
                            font.family: FrameTheme.fontFamily
                            font.pixelSize: 11
                            font.weight: modelData.is_active ? Font.Bold : Font.Normal
                        }
                    }
                }
            }
        }
    }
}
