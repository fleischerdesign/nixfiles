import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import "." // Access FrameTheme if in same folder

Rectangle {
    id: root

    // ========================================
    // PUBLIC API
    // ========================================
    
    enum Variant {
        Default,    // Solid Black (Primary)
        Destructive,// Solid Red
        Outline,    // White with Border
        Secondary,  // Light Gray
        Ghost,      // Transparent, Hover only
        Link        // Text only
    }
    
    property int variant: FrameButton.Variant.Default
    
    // Optional: Icon / Text shortcuts
    property string text: ""
    property string icon: "" 
    
    default property alias content: contentContainer.data
    
    property bool enabled: true
    property bool showBadge: false // New property
    signal clicked()
    
    // ========================================
    // LAYOUT & STYLE
    // ========================================
    
    implicitWidth: Math.max(40, contentContainer.width + (text !== "" ? 32 : 16))
    implicitHeight: 40
    
    radius: FrameTheme.radius
    
    // --- Colors based on Variant ---
    readonly property color baseColor: {
        switch (root.variant) {
            case FrameButton.Variant.Default: return FrameTheme.primary;
            case FrameButton.Variant.Destructive: return FrameTheme.destructive;
            case FrameButton.Variant.Outline: return "transparent";
            case FrameButton.Variant.Secondary: return FrameTheme.secondary;
            case FrameButton.Variant.Ghost: return hoverHandler.hovered ? FrameTheme.accent : "transparent";
            case FrameButton.Variant.Link: return "transparent";
            default: return FrameTheme.primary;
        }
    }
    
    readonly property color contentColor: {
        switch (root.variant) {
            case FrameButton.Variant.Default: return FrameTheme.primaryForeground;
            case FrameButton.Variant.Destructive: return FrameTheme.destructiveForeground;
            case FrameButton.Variant.Outline: return FrameTheme.foreground;
            case FrameButton.Variant.Secondary: return FrameTheme.secondaryForeground;
            case FrameButton.Variant.Ghost: return FrameTheme.foreground;
            case FrameButton.Variant.Link: return FrameTheme.primary;
            default: return FrameTheme.primaryForeground;
        }
    }
    
    readonly property color borderColor: {
        if (root.variant === FrameButton.Variant.Outline) return FrameTheme.border;
        return "transparent";
    }

    // --- Visual Implementation ---
    color: baseColor
    border.width: root.variant === FrameButton.Variant.Outline ? FrameTheme.borderWidth : 0
    border.color: borderColor
    
    opacity: enabled ? 1.0 : 0.5
    
    Behavior on color { ColorAnimation { duration: 150 } }

    // ========================================
    // CONTENT
    // ========================================
    
    RowLayout {
        id: contentContainer
        anchors.centerIn: parent
        spacing: 8
        
        // Internal Label logic if 'text' or 'icon' properties are used
        Text {
            visible: root.icon !== ""
            text: root.icon
            font.family: "Material Symbols Rounded"
            font.pixelSize: 18
            color: root.contentColor
        }
        
        Text {
            visible: root.text !== ""
            text: root.text
            font.family: FrameTheme.fontFamily
            font.pixelSize: FrameTheme.fontSizeBase
            font.weight: Font.Medium
            color: root.contentColor
        }
    }

    // ========================================
    // INTERACTION
    // ========================================
    
    HoverHandler {
        id: hoverHandler
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }
    
    TapHandler {
        id: tapHandler
        enabled: root.enabled
        onTapped: root.clicked()
        onPressedChanged: {
            if (pressed) {
                root.scale = 0.96
            } else {
                root.scale = 1.0
            }
        }
    }
    
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }

    // Built-in Badge
    Rectangle {
        width: 8
        height: 8
        radius: 4
        color: FrameTheme.destructive
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 4
        anchors.rightMargin: 4
        visible: root.showBadge
        
        // Cutout border
        border.width: 1
        border.color: FrameTheme.background
    }
}
