// home-manager/philipp/modules/quickshell/components/M3StateLayer.qml

import QtQuick
import qs.services

Rectangle {
    id: root
    
    // EINGABEN: Die Rolle des übergeordneten Elements
    enum ColorRole {
        Primary,
        Secondary,
        Tertiary,
        Surface,
        SurfaceVariant,
        Error,
        Custom
    }
    
    property int colorRole: M3StateLayer.ColorRole.Surface
    property color customStateColor: "#FFFFFF" // Nur für Custom-Rolle
    
    // EINGABEN: Interaktionszustand
    property bool isHovered: false
    property bool isPressed: false
    property bool isFocused: false
    property bool isDragged: false
    
    // EINGABEN: Manuelle Opazitäts-Überschreibung (optional)
    property real customOpacity: -1.0 // -1 = Auto-Modus
    
    // PRIVATE: Automatische Opazitätsberechnung nach M3-Richtlinien
    readonly property real autoOpacity: {
        if (root.isDragged) return 0.16;
        if (root.isPressed) return 0.12;
        if (root.isFocused) return 0.12;
        if (root.isHovered) return 0.08;
        return 0.0;
    }
    
    // PRIVATE: Finale Opazität (Custom oder Auto)
    readonly property real finalOpacity: root.customOpacity >= 0 ? root.customOpacity : root.autoOpacity
    
    // PRIVATE: Automatische Farbauswahl basierend auf Rolle
    readonly property color autoStateColor: {
        switch (root.colorRole) {
            case M3StateLayer.ColorRole.Primary:
                return ColorService.palette.m3OnPrimary;
            case M3StateLayer.ColorRole.Secondary:
                return ColorService.palette.m3OnSecondary;
            case M3StateLayer.ColorRole.Tertiary:
                return ColorService.palette.m3OnTertiary;
            case M3StateLayer.ColorRole.Surface:
                return ColorService.palette.m3OnSurface;
            case M3StateLayer.ColorRole.SurfaceVariant:
                return ColorService.palette.m3OnSurfaceVariant;
            case M3StateLayer.ColorRole.Error:
                return ColorService.palette.m3OnError;
            case M3StateLayer.ColorRole.Custom:
                return root.customStateColor;
            default:
                return ColorService.palette.m3OnSurface;
        }
    }
    
    // Visuelle Implementierung
    anchors.fill: parent
    radius: parent.radius
    color: root.autoStateColor
    opacity: root.finalOpacity
    
    // M3-konforme Animationen
    Behavior on opacity {
        NumberAnimation {
            duration: root.isPressed ? 100 : 150
            easing.type: Easing.OutCubic
        }
    }
    
    Behavior on color {
        ColorAnimation {
            duration: 150
        }
    }
}
