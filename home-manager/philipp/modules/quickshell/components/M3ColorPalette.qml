// home-manager/philipp/modules/quickshell/Colors.qml

pragma Singleton
import QtQuick

// Material 3 Color Scheme - Alle Eigenschaften mit dem "m3"-Präfix

QtObject {
    id: m3Colors

    // =================================================================
    // A) COLOR ROLES (DARK SCHEME)
    // =================================================================

    // --- ACCENT COLORS (Primary / Secondary / Tertiary) ---

    readonly property color m3Primary: "#A9D291"
    readonly property color m3SurfaceTint: "#A9D291"
    readonly property color m3OnPrimary: "#173807"
    readonly property color m3PrimaryContainer: "#2D4F1D"
    readonly property color m3OnPrimaryContainer: "#C5EFAB"

    readonly property color m3Secondary: "#BDCBB0"
    readonly property color m3OnSecondary: "#283421"
    readonly property color m3SecondaryContainer: "#3E4A36"
    readonly property color m3OnSecondaryContainer: "#D8E7CB"

    readonly property color m3Tertiary: "#A0CFD0"
    readonly property color m3OnTertiary: "#003738"
    readonly property color m3TertiaryContainer: "#1E4E4F"
    readonly property color m3OnTertiaryContainer: "#BBEBEC"

    // --- ERROR COLORS ---

    readonly property color m3Error: "#FFB4AB"
    readonly property color m3OnError: "#690005"
    readonly property color m3ErrorContainer: "#93000A"
    readonly property color m3OnErrorContainer: "#FFDAD6"

    // --- NEUTRAL COLORS (Surfaces / Background / Text) ---

    readonly property color m3Background: "#11140F"
    readonly property color m3OnBackground: "#E1E4D9"
    readonly property color m3Surface: "#11140F"
    readonly property color m3OnSurface: "#E1E4D9"

    readonly property color m3SurfaceVariant: "#43483E"
    readonly property color m3OnSurfaceVariant: "#C3C8BB"

    readonly property color m3Outline: "#8D9286"
    readonly property color m3OutlineVariant: "#43483E"

    readonly property color m3Shadow: "#000000"
    readonly property color m3Scrim: "#000000"

    // --- INVERSE & FIXED COLORS ---

    readonly property color m3InverseSurface: "#E1E4D9"
    readonly property color m3InverseOnSurface: "#2E312B"
    readonly property color m3InversePrimary: "#446732"

    readonly property color m3PrimaryFixed: "#C5EFAB"
    readonly property color m3OnPrimaryFixed: "#072100"
    readonly property color m3FixedDimPrimary: "#A9D291"
    readonly property color m3OnPrimaryFixedVariant: "#2D4F1D"

    readonly property color m3SecondaryFixed: "#D8E7CB"
    readonly property color m3OnSecondaryFixed: "#131F0D"
    readonly property color m3FixedDimSecondary: "#BDCBB0"
    readonly property color m3OnSecondaryFixedVariant: "#3E4A36"

    readonly property color m3TertiaryFixed: "#BBEBEC"
    readonly property color m3OnTertiaryFixed: "#002020"
    readonly property color m3FixedDimTertiary: "#A0CFD0"
    readonly property color m3OnTertiaryFixedVariant: "#1E4E4F"

    // --- SURFACE CONTAINERS ---
    
    readonly property color m3SurfaceDim: "#11140F"
    readonly property color m3SurfaceBright: "#373A33"
    readonly property color m3SurfaceContainerLowest: "#0C0F0A"
    readonly property color m3SurfaceContainerLow: "#191D16"
    readonly property color m3SurfaceContainer: "#1D211A"
    readonly property color m3SurfaceContainerHigh: "#282B24"
    readonly property color m3SurfaceContainerHighest: "#32362F"


    // =================================================================
    // B) TONAL PALETTES (ROHE FARBDATEN)
    // =================================================================

    readonly property QtObject m3Palettes: QtObject { // M3-Präfix

        readonly property QtObject m3Primary: QtObject { // M3-Präfix
            readonly property color m3Tone0: "#000000" // M3-Präfix
            readonly property color m3Tone5: "#041501"
            readonly property color m3Tone10: "#0E2006"
            readonly property color m3Tone15: "#182A0F"
            readonly property color m3Tone20: "#223518"
            readonly property color m3Tone25: "#2D4123"
            readonly property color m3Tone30: "#384C2D"
            readonly property color m3Tone35: "#445838"
            readonly property color m3Tone40: "#4F6443"
            readonly property color m3Tone50: "#687D5A"
            readonly property color m3Tone60: "#819772"
            readonly property color m3Tone70: "#9BB28B"
            readonly property color m3Tone80: "#B6CEA5"
            readonly property color m3Tone90: "#D2EAC0"
            readonly property color m3Tone95: "#E0F8CD"
            readonly property color m3Tone98: "#EEFFDE"
            readonly property color m3Tone99: "#F7FFEC"
            readonly property color m3Tone100: "#FFFFFF"
        }

        readonly property QtObject m3Secondary: QtObject {
            readonly property color m3Tone0: "#000000"
            readonly property color m3Tone5: "#0E120B"
            readonly property color m3Tone10: "#181D15"
            readonly property color m3Tone15: "#22271F"
            readonly property color m3Tone20: "#2D3229"
            readonly property color m3Tone25: "#383D34"
            readonly property color m3Tone30: "#43483F"
            readonly property color m3Tone35: "#4F544A"
            readonly property color m3Tone40: "#5B6056"
            readonly property color m3Tone50: "#74796E"
            readonly property color m3Tone60: "#8D9287"
            readonly property color m3Tone70: "#A8ADA1"
            readonly property color m3Tone80: "#C4C8BB"
            readonly property color m3Tone90: "#E0E4D7"
            readonly property color m3Tone95: "#EEF2E5"
            readonly property color m3Tone98: "#F7FBED"
            readonly property color m3Tone99: "#FAFEF0"
            readonly property color m3Tone100: "#FFFFFF"
        }

        readonly property QtObject m3Tertiary: QtObject {
            readonly property color m3Tone0: "#000000"
            readonly property color m3Tone5: "#041314"
            readonly property color m3Tone10: "#0E1E1E"
            readonly property color m3Tone15: "#192829"
            readonly property color m3Tone20: "#233333"
            readonly property color m3Tone25: "#2E3E3E"
            readonly property color m3Tone30: "#3A4A4A"
            readonly property color m3Tone35: "#455556"
            readonly property color m3Tone40: "#516162"
            readonly property color m3Tone50: "#697A7A"
            readonly property color m3Tone60: "#839494"
            readonly property color m3Tone70: "#9DAFAE"
            readonly property color m3Tone80: "#B8CACA"
            readonly property color m3Tone90: "#D4E6E6"
            readonly property color m3Tone95: "#E2F4F4"
            readonly property color m3Tone98: "#EBFDFD"
            readonly property color m3Tone99: "#F1FFFF"
            readonly property color m3Tone100: "#FFFFFF"
        }

        readonly property QtObject m3Neutral: QtObject {
            readonly property color m3Tone0: "#000000"
            readonly property color m3Tone5: "#11110F"
            readonly property color m3Tone10: "#1B1C1A"
            readonly property color m3Tone15: "#262624"
            readonly property color m3Tone20: "#30302E"
            readonly property color m3Tone25: "#3B3B39"
            readonly property color m3Tone30: "#474744"
            readonly property color m3Tone35: "#535250"
            readonly property color m3Tone40: "#5F5E5C"
            readonly property color m3Tone50: "#787774"
            readonly property color m3Tone60: "#92918E"
            readonly property color m3Tone70: "#ACABA8"
            readonly property color m3Tone80: "#C8C6C3"
            readonly property color m3Tone90: "#E4E2DF"
            readonly property color m3Tone95: "#F3F0ED"
            readonly property color m3Tone98: "#FBF9F5"
            readonly property color m3Tone99: "#FEFCF8"
            readonly property color m3Tone100: "#FFFFFF"
        }

        readonly property QtObject m3NeutralVariant: QtObject {
            readonly property color m3Tone0: "#000000"
            readonly property color m3Tone5: "#10110E"
            readonly property color m3Tone10: "#1A1C18"
            readonly property color m3Tone15: "#252622"
            readonly property color m3Tone20: "#2F312D"
            readonly property color m3Tone25: "#3A3C37"
            readonly property color m3Tone30: "#464743"
            readonly property color m3Tone35: "#51534E"
            readonly property color m3Tone40: "#5D5F5A"
            readonly property color m3Tone50: "#767872"
            readonly property color m3Tone60: "#90918B"
            readonly property color m3Tone70: "#ABACA6"
            readonly property color m3Tone80: "#C7C7C1"
            readonly property color m3Tone90: "#E3E3DC"
            readonly property color m3Tone95: "#F1F1EA"
            readonly property color m3Tone98: "#FAFAF3"
            readonly property color m3Tone99: "#FDFDF6"
            readonly property color m3Tone100: "#FFFFFF"
        }
    }
}
