// home-manager/philipp/modules/quickshell/M3StateLayer.qml

import QtQuick

Rectangle {
    id: root
    
    // 1. EINGABE: Die "On Color" des Basiselements (z.B. On Secondary Container)
    property color stateColor: "#FFFFFF" 
    
    // 2. EINGABE: Der aktuelle Status des übergeordneten Elements
    property bool isHovered: false

    // 3. EINGABE: Deckkraft für Ruhe- und Hover-Zustand
    property real baseOpacity: 0.0
    property real hoverOpacity: 0.08 // M3-Standard für Hover

    // Visuelle Implementierung des State Layers
    anchors.fill: parent
    radius: parent.radius
    color: root.stateColor

    // Steuert die Opazität basierend auf dem Hover-Status
    opacity: root.isHovered ? root.hoverOpacity : root.baseOpacity
    
    // M3-konforme Animation für den Übergang
    Behavior on opacity {
        NumberAnimation { duration: 150 }
    }
}
