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
        width: 800
        height: 300
        
        // Position: Center Bottom
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 70
        
        // Frame Style
        radius: FrameTheme.radius
        color: FrameTheme.popover
        border.width: FrameTheme.borderWidth
        border.color: FrameTheme.border
        
        // Animation
        opacity: shouldBeVisible ? 1 : 0
        transform: Translate {
            y: shouldBeVisible ? 0 : 20
            Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
        }
        Behavior on opacity { NumberAnimation { duration: 250 } }

        // Shadow
        RectangularShadow {
            width: parent.width; height: parent.height
            y: 8; z: -1
            color: Qt.rgba(0, 0, 0, 0.4); blur: 30; radius: parent.radius
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 20

            Repeater {
                model: WorkspaceService.workspaces
                
                delegate: Rectangle {
                    id: workspaceCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: FrameTheme.radius
                    color: modelData.is_active ? FrameTheme.secondary : "transparent"
                    border.width: 1
                    border.color: modelData.is_active ? FrameTheme.ring : FrameTheme.border
                    
                    // Interaction
                    MouseArea {
                        anchors.fill: parent
                        onClicked: WorkspaceService.focusWorkspace(modelData.idx)
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        
                        Text {
                            text: "Workspace " + modelData.idx
                            color: modelData.is_active ? FrameTheme.foreground : FrameTheme.mutedForeground
                            font.family: FrameTheme.fontFamily
                            font.pixelSize: 12
                            font.weight: modelData.is_active ? Font.Bold : Font.Normal
                        }
                        
                        // Schematic Layout Preview
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            
                            // Map windows of this workspace
                            Repeater {
                                model: {
                                    const wsWindows = [];
                                    for (const win of WorkspaceService.windows) {
                                        if (win.workspace_id === modelData.id) wsWindows.push(win);
                                    }
                                    return wsWindows;
                                }
                                
                                delegate: Rectangle {
                                    // Calculate relative position/size
                                    // Note: Niri coordinates are absolute, we need to normalize
                                    // For simplicity: We use the layout data
                                    x: 0 // In Niri, windows are usually in columns
                                    width: parent.width * 0.8
                                    height: parent.height * 0.6
                                    anchors.centerIn: parent
                                    
                                    radius: 4
                                    color: modelData.is_focused ? FrameTheme.accent : FrameTheme.muted
                                    opacity: 0.8
                                    border.width: 1
                                    border.color: FrameTheme.border
                                    
                                    // App Icon
                                    IconImage {
                                        anchors.centerIn: parent
                                        width: 24; height: 24
                                        source: "image://icon/" + modelData.app_id
                                        visible: modelData.app_id !== null
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
