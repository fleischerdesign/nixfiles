// home-manager/philipp/modules/quickshell/components/M3Button.qml
// Material 3 Button Component mit vollständiger State Layer Integration

import QtQuick
import qs.components
import qs.services

Rectangle {
    id: root

    // ========================================
    // PUBLIC API
    // ========================================
    
    // --- M3 Button Styles ---
    enum Style {
        Filled,        // Primärer Button mit voller Farbe
        FilledTonal,   // Sekundärer Button mit Container-Farbe
        Elevated,      // Button mit Elevation (Shadow)
        Outlined,      // Button mit Outline
        Text           // Text-only Button
    }
    
    property int style: M3Button.Style.Filled
    
    // --- M3 Color Roles ---
    enum ColorRole {
        Primary,
        Secondary,
        Tertiary,
        Surface,
        Error
    }
    
    property int colorRole: M3Button.ColorRole.Primary
    
    // --- Icon Support ---
    property string icon: ""
    property string iconFont: "Material Symbols Rounded"
    property int iconSize: 24
    property bool iconOnly: false
    
    // --- Content ---
    property alias text: labelText.text
    default property alias content: contentItem.data
    
    // --- Sizing ---
    property bool fixedWidth: false
    implicitWidth: {
        if (fixedWidth) return 55;
        if (iconOnly) return implicitHeight;
        return Math.max(55, contentItem.implicitWidth + (icon ? 48 : 40));
    }
    implicitHeight: 40  // M3 Standard Button Height
    
    // M3 Shape Token
    radius: 20  // M3 Full Corner Radius für Buttons
    clip: true
    
    // --- Enabled State ---
    property bool enabled: true
    opacity: enabled ? 1.0 : 0.38
    
    // --- Signals ---
    signal clicked()
    signal pressed()
    signal released()
    signal longPressed()
    
    // ========================================
    // PRIVATE PROPERTIES
    // ========================================
    
    // Automatische Farbberechnung basierend auf Style & Role
    readonly property color autoBackgroundColor: {
        // Transparent für Text und Outlined
        if (style === M3Button.Style.Text || style === M3Button.Style.Outlined) {
            return "transparent";
        }
        
        // Elevated nutzt Surface
        if (style === M3Button.Style.Elevated) {
            return ColorService.layer(ColorService.palette.m3SurfaceContainerLow, 1);
        }
        
        // Filled und FilledTonal
        const isTonal = style === M3Button.Style.FilledTonal;
        
        switch (colorRole) {
            case M3Button.ColorRole.Primary:
                return isTonal ? ColorService.palette.m3PrimaryContainer : ColorService.palette.m3Primary;
            case M3Button.ColorRole.Secondary:
                return isTonal ? ColorService.palette.m3SecondaryContainer : ColorService.palette.m3Secondary;
            case M3Button.ColorRole.Tertiary:
                return isTonal ? ColorService.palette.m3TertiaryContainer : ColorService.palette.m3Tertiary;
            case M3Button.ColorRole.Error:
                return isTonal ? ColorService.palette.m3ErrorContainer : ColorService.palette.m3Error;
            case M3Button.ColorRole.Surface:
            default:
                return ColorService.palette.m3SurfaceContainerHigh;
        }
    }
    
    readonly property color autoContentColor: {
        // Text und Outlined verwenden Akzentfarbe als Text
        if (style === M3Button.Style.Text || style === M3Button.Style.Outlined) {
            switch (colorRole) {
                case M3Button.ColorRole.Primary:
                    return ColorService.palette.m3Primary;
                case M3Button.ColorRole.Secondary:
                    return ColorService.palette.m3Secondary;
                case M3Button.ColorRole.Tertiary:
                    return ColorService.palette.m3Tertiary;
                case M3Button.ColorRole.Error:
                    return ColorService.palette.m3Error;
                default:
                    return ColorService.palette.m3OnSurface;
            }
        }
        
        // Elevated nutzt Primary als Text
        if (style === M3Button.Style.Elevated) {
            return ColorService.palette.m3Primary;
        }
        
        // Filled und FilledTonal
        const isTonal = style === M3Button.Style.FilledTonal;
        
        switch (colorRole) {
            case M3Button.ColorRole.Primary:
                return isTonal ? ColorService.palette.m3OnPrimaryContainer : ColorService.palette.m3OnPrimary;
            case M3Button.ColorRole.Secondary:
                return isTonal ? ColorService.palette.m3OnSecondaryContainer : ColorService.palette.m3OnSecondary;
            case M3Button.ColorRole.Tertiary:
                return isTonal ? ColorService.palette.m3OnTertiaryContainer : ColorService.palette.m3OnTertiary;
            case M3Button.ColorRole.Error:
                return isTonal ? ColorService.palette.m3OnErrorContainer : ColorService.palette.m3OnError;
            case M3Button.ColorRole.Surface:
            default:
                return ColorService.palette.m3OnSurface;
        }
    }
    
    // ========================================
    // VISUAL IMPLEMENTATION
    // ========================================
    
    color: autoBackgroundColor
    
    // Outline für Outlined Style
    border.width: style === M3Button.Style.Outlined ? 1 : 0
    border.color: ColorService.palette.m3Outline
    
    // Elevation Shadow für Elevated Style
    
    // Smooth Transitions
    Behavior on color {
        ColorAnimation { duration: 150 }
    }
    
    Behavior on border.color {
        ColorAnimation { duration: 150 }
    }
    
    // ========================================
    // CONTENT LAYOUT
    // ========================================
    
    Item {
        id: contentItem
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
        anchors.centerIn: parent
        z: 3
        
        Row {
            id: contentRow
            visible: (root.text !== "" || root.icon !== "") && contentItem.children.length === 1
            spacing: 8
            
            // Icon
            Text {
                id: iconText
                visible: root.icon !== ""
                text: root.icon
                font.family: root.iconFont
                font.pixelSize: root.iconSize
                color: root.autoContentColor
                anchors.verticalCenter: parent.verticalCenter
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
            
            // Label
            Text {
                id: labelText
                visible: !root.iconOnly && text !== ""
                font.pixelSize: 14
                font.weight: Font.Medium
                font.family: "Roboto"
                color: root.autoContentColor
                anchors.verticalCenter: parent.verticalCenter
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
        }
    }
    
    // ========================================
    // INTERACTION HANDLERS
    // ========================================
    
    HoverHandler {
        id: hoverHandler
        enabled: root.enabled
    }
    
    TapHandler {
        id: tapHandler
        enabled: root.enabled

        onPressedChanged: {
            if (pressed) {
                rippleEffect.trigger(tapHandler.point.pressPosition.x, tapHandler.point.pressPosition.y);
                root.pressed();
            } else {
                root.released();
                root.clicked();
            }
        }

        // onTapped: root.clicked()

        onLongPressed: root.longPressed()
    }
    
    // ========================================
    // M3 STATE LAYER
    // ========================================
    
    M3StateLayer {
        z: 1
        colorRole: {
            // State Layer nutzt immer "On"-Farbe des Buttons
            if (root.style === M3Button.Style.Text || 
                root.style === M3Button.Style.Outlined ||
                root.style === M3Button.Style.Elevated) {
                return M3StateLayer.ColorRole.Surface;
            }
            
            switch (root.colorRole) {
                case M3Button.ColorRole.Primary:
                    return root.style === M3Button.Style.FilledTonal 
                        ? M3StateLayer.ColorRole.Primary 
                        : M3StateLayer.ColorRole.Primary;
                case M3Button.ColorRole.Secondary:
                    return M3StateLayer.ColorRole.Secondary;
                case M3Button.ColorRole.Tertiary:
                    return M3StateLayer.ColorRole.Tertiary;
                case M3Button.ColorRole.Error:
                    return M3StateLayer.ColorRole.Error;
                default:
                    return M3StateLayer.ColorRole.Surface;
            }
        }
        
        customStateColor: root.autoContentColor
        isHovered: hoverHandler.hovered && root.enabled
        isPressed: tapHandler.pressed && root.enabled
    }
    
    // ========================================
    // M3 RIPPLE EFFECT
    // ========================================
    
    RippleEffect {
        id: rippleEffect
        z: 2
        enabled: root.enabled
        rippleColor: root.autoContentColor
        parentRadius: root.radius
    }
}

// Hilfsmethode für DropShadow (falls nicht verfügbar)
// In QML benötigt man normalerweise: import QtGraphicalEffects 1.15
// Falls nicht verfügbar, kann man das layer.effect weglassen
