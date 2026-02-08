import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    // --- Public API ---
    property bool checked: false
    property string icon: ""
    property string label: ""
    property color activeColor: FrameTheme.primary
    
    signal toggled()

    // --- Styling ---
    height: 44
    radius: FrameTheme.radius
    color: root.checked ? root.activeColor : FrameTheme.secondary
    
    Behavior on color { ColorAnimation { duration: 200 } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12

        Text {
            visible: root.icon !== ""
            text: root.icon
            font.family: "Material Symbols Rounded"
            font.pixelSize: 20
            color: root.checked ? FrameTheme.primaryForeground : FrameTheme.foreground
        }

        Text {
            text: root.label
            color: root.checked ? FrameTheme.primaryForeground : FrameTheme.foreground
            font.family: FrameTheme.fontFamily
            font.pixelSize: 14
            font.weight: Font.Medium
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        // Toggle Switch (Adwaita Style)
        Rectangle {
            width: 44
            height: 24
            radius: 12
            color: root.checked ? Qt.rgba(1, 1, 1, 0.3) : FrameTheme.muted
            
            Rectangle {
                x: root.checked ? 22 : 2
                y: 2
                width: 20
                height: 20
                radius: 10
                color: "white"
                
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggled()
    }
}
