import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    // --- Public API ---
    property real value: 0.0
    property string icon: ""
    property string label: ""
    property bool active: true
    property color activeColor: FrameTheme.primary
    
    signal moved(real newValue)
    signal iconClicked()

    // --- Styling ---
    height: 44
    radius: FrameTheme.radius
    color: FrameTheme.secondary
    clip: true

    readonly property real displayValue: isNaN(root.value) ? 0.0 : root.value

    // Progress Fill
    Rectangle {
        id: fillRect
        height: parent.height
        width: parent.width * Math.max(0, Math.min(1, root.displayValue))
        radius: parent.radius
        color: root.active ? root.activeColor : FrameTheme.muted
        
        Behavior on width { 
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic } 
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12
        z: 1 // Ensure it sits above the main MouseArea for child interactions

        Text {
            id: iconText
            visible: root.icon !== ""
            text: root.icon
            font.family: "Material Symbols Rounded"
            font.pixelSize: 20
            color: root.active ? FrameTheme.primaryForeground : FrameTheme.mutedForeground
            
            TapHandler {
                onTapped: root.iconClicked()
            }
        }

        Text {
            visible: root.label !== ""
            text: root.label
            color: root.active ? FrameTheme.primaryForeground : FrameTheme.mutedForeground
            font.family: FrameTheme.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Item { 
            visible: root.label === ""
            Layout.fillWidth: true 
        }

        Text {
            text: Math.round(root.displayValue * 100) + "%"
            color: root.active ? FrameTheme.primaryForeground : FrameTheme.mutedForeground
            font.family: FrameTheme.fontFamily
            font.pixelSize: 12
            font.weight: Font.Bold
            opacity: 0.7
        }
    }

    MouseArea {
        anchors.fill: parent
        // Handle interaction, but don't block the icon if it has a specific click action
        onPressed: (mouse) => {
            if (mouse.x > (root.icon !== "" ? 40 : 0)) updateValue(mouse)
        }
        onPositionChanged: (mouse) => {
            if (mouse.x > (root.icon !== "" ? 40 : 0)) updateValue(mouse)
        }
        onWheel: (wheel) => {
            const step = wheel.angleDelta.y > 0 ? 0.02 : -0.02
            const newVal = Math.max(0, Math.min(1, root.value + step))
            root.moved(newVal)
        }
        function updateValue(mouse) {
            let newVal = Math.max(0, Math.min(1, mouse.x / width))
            root.moved(newVal)
        }
    }
}