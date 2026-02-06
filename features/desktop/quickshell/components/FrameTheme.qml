pragma Singleton
import QtQuick

QtObject {
    // ========================================
    // FRAME SHELL THEME (ShadCN Inspired)
    // ========================================

    // --- Colors (Zinc / Slate based - Dark Mode) ---
    readonly property color background: "#09090b" // Zinc-950
    readonly property color foreground: "#fafafa" // Zinc-50
    
    readonly property color card: "#09090b"
    readonly property color cardForeground: "#fafafa"
    
    readonly property color popover: "#09090b"
    readonly property color popoverForeground: "#fafafa"
    
    readonly property color primary: "#fafafa" // Inverted in dark mode
    readonly property color primaryForeground: "#18181b"
    
    readonly property color secondary: "#27272a" // Zinc-800
    readonly property color secondaryForeground: "#fafafa"
    
    readonly property color muted: "#27272a"
    readonly property color mutedForeground: "#a1a1aa"
    
    readonly property color accent: "#27272a"
    readonly property color accentForeground: "#fafafa"
    
    readonly property color destructive: "#7f1d1d"
    readonly property color destructiveForeground: "#fafafa"

    readonly property color border: "#27272a" // Zinc-800
    readonly property color input: "#27272a"
    readonly property color ring: "#d4d4d8"

    // --- Layout ---
    readonly property real radius: 6
    readonly property real borderWidth: 1
    
    // --- Typography ---
    readonly property string fontFamily: "Inter, Roboto, sans-serif"
    readonly property real fontSizeBase: 14
    readonly property real fontSizeSmall: 12
    readonly property real fontSizeLarge: 16
}