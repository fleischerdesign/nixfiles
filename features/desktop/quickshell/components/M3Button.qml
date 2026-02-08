// home-manager/philipp/modules/quickshell/components/M3Button.qml
// Material 3 Button Component - Simple Container Approach

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import QtQuick.Effects

Rectangle {
    id: root

    // ========================================
    // PUBLIC API
    // ========================================
    
    // --- M3 Button Styles ---
    enum Style {
        Filled,
        FilledTonal,
        Elevated,
        Outlined,
        Text
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
    property bool shadowEnabled: style === M3Button.Style.Elevated
    
    // --- Content Container ---
    default property alias content: contentContainer.data
    
    // --- Sizing ---
    implicitWidth: Math.max(55, contentContainer.width + 40)
    implicitHeight: 40
    
    radius: FrameTheme.radius
    clip: false
    
    RectangularShadow {
        anchors.fill: root
        visible: root.shadowEnabled && root.enabled
        color: Qt.rgba(0, 0, 0, 0.1)
        blur: 10
        radius: FrameTheme.radius
        antialiasing: true
        cached: true
        z: -1
    }
    
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
    
    readonly property color autoBackgroundColor: {
        if (style === M3Button.Style.Text || style === M3Button.Style.Outlined) {
            return "transparent";
        }
        
        if (style === M3Button.Style.Elevated) {
            return FrameTheme.secondary;
        }
        
        const isTonal = style === M3Button.Style.FilledTonal;
        
        switch (colorRole) {
            case M3Button.ColorRole.Primary:
                return FrameTheme.primary;
            case M3Button.ColorRole.Secondary:
                return FrameTheme.secondary;
            case M3Button.ColorRole.Tertiary:
                return FrameTheme.accent;
            case M3Button.ColorRole.Error:
                return FrameTheme.destructive;
            case M3Button.ColorRole.Surface:
            default:
                return FrameTheme.card;
        }
    }
    
    readonly property color autoContentColor: {
        if (style === M3Button.Style.Text || style === M3Button.Style.Outlined) {
            switch (colorRole) {
                case M3Button.ColorRole.Primary:
                    return FrameTheme.primary;
                case M3Button.ColorRole.Secondary:
                    return FrameTheme.secondaryForeground;
                case M3Button.ColorRole.Tertiary:
                    return FrameTheme.accent;
                case M3Button.ColorRole.Error:
                    return FrameTheme.destructive;
                default:
                    return FrameTheme.foreground;
            }
        }
        
        if (style === M3Button.Style.Elevated) {
            return FrameTheme.primary;
        }
        
        switch (colorRole) {
            case M3Button.ColorRole.Primary:
                return FrameTheme.primaryForeground;
            case M3Button.ColorRole.Secondary:
                return FrameTheme.secondaryForeground;
            case M3Button.ColorRole.Tertiary:
                return FrameTheme.accentForeground;
            case M3Button.ColorRole.Error:
                return FrameTheme.destructiveForeground;
            case M3Button.ColorRole.Surface:
            default:
                return FrameTheme.foreground;
        }
    }
    
    // ========================================
    // VISUAL IMPLEMENTATION
    // ========================================
    
    color: autoBackgroundColor
    border.width: style === M3Button.Style.Outlined ? 1 : 0
    border.color: FrameTheme.border
    
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }
    
    // ========================================
    // CONTENT CONTAINER
    // ========================================
    
    RowLayout {
        id: contentContainer
        anchors.centerIn: parent
        z: 3
        // Content goes here via default property
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

        onLongPressed: root.longPressed()
    }
    
    // ========================================
    // M3 STATE LAYER
    // ========================================
    
    M3StateLayer {
        z: 1
        colorRole: {
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
