import QtQuick
import QtQuick.Layouts
import qs.services
import qs.core
import qs.components

// WorkspaceIndicator.qml - Libadwaita Dots & Lines
RowLayout {
    id: root
    spacing: 6
    
    Repeater {
        model: WorkspaceService.workspaces
        
        delegate: Rectangle {
            id: dot
            implicitWidth: modelData.is_active ? 18 : 6
            implicitHeight: 6
            radius: 3
            
            // Color logic: Primary blue when active, muted when not
            color: {
                if (modelData.is_urgent) return FrameTheme.destructive;
                if (modelData.is_active) return FrameTheme.primary;
                return FrameTheme.mutedForeground;
            }
            
            // Smooth transition for size and color
            Behavior on implicitWidth { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
            Behavior on color { ColorAnimation { duration: 200 } }
            
            MouseArea {
                anchors.fill: parent
                onClicked: WorkspaceService.focusWorkspace(modelData.idx)
            }
        }
    }
}