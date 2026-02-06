import QtQuick
import QtQuick.Layouts
import qs.services
import qs.core

// WorkspaceIndicator.qml - Minimalist Niri Workspaces
RowLayout {
    id: root
    spacing: 6
    
    Repeater {
        model: WorkspaceService.workspaces
        
        delegate: Rectangle {
            id: dot
            implicitWidth: modelData.is_active ? 20 : 6
            implicitHeight: 6
            radius: 3
            
            // Color logic
            color: {
                if (modelData.is_urgent) return FrameTheme.destructive;
                if (modelData.is_active) return FrameTheme.foreground;
                return FrameTheme.muted;
            }
            
            // Smooth transition for size and color
            Behavior on implicitWidth { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
            Behavior on color { ColorAnimation { duration: 200 } }
            
            // Interaction
            MouseArea {
                anchors.fill: parent
                onClicked: WorkspaceService.focusWorkspace(modelData.idx)
            }
            
            // Optional: Tooltip or small indicator for windows count
            // (Could be added here later)
        }
    }
}
