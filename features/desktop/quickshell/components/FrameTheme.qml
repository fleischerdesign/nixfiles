pragma Singleton
import QtQuick

QtObject {
    // ========================================
    // FRAME SHELL THEME (Adwaita Inspired)
    // ========================================

    // --- Colors (Authentic Libadwaita Dark) ---
    readonly property color background: "#1e1e1e" // Deep background
    readonly property color foreground: "#ffffff" 
    
    readonly property color card: "#242424"       // Standard window background
    readonly property color cardForeground: "#ffffff"
    
    readonly property color popover: "#303030"    // Elevated surfaces (Panels/Islands)
    readonly property color popoverForeground: "#ffffff"
    
    readonly property color primary: "#3584e4"    // Adwaita Blue
    readonly property color primaryForeground: "#ffffff"
    
    readonly property color secondary: "#3c3c3c"  // Buttons on popover surfaces
    readonly property color secondaryForeground: "#ffffff"
    
    readonly property color muted: "#353535"
    readonly property color mutedForeground: "#9a9996" // Deemphasized text
    
    readonly property color accent: "#3584e4"
    readonly property color accentForeground: "#ffffff"
    
    readonly property color destructive: "#ed333b" // Adwaita Red
    readonly property color destructiveForeground: "#ffffff"

    readonly property color border: "#353535"     // Subtle border for elevation
    readonly property color input: "#242424"
    readonly property color ring: "#3584e4"

    // --- Layout ---
    readonly property real radius: 12
    readonly property real borderWidth: 1
    
    // --- Typography ---
    readonly property string fontFamily: "Cantarell, Inter, Roboto, sans-serif"
    readonly property real fontSizeBase: 14
    readonly property real fontSizeSmall: 12
    readonly property real fontSizeLarge: 16
}