pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
// import qs.config // Annahme: qs.config ist verfügbar oder wird später definiert
// import qs.utils // Annahme: qs.utils ist verfügbar oder wird später definiert
// import Caelestia // Caelestia-spezifische Imports werden hier nicht direkt übernommen, da es sich um ein externes Framework handelt
import Quickshell.Io

Singleton {
    id: root

    // --- Konfigurierbare Eigenschaften ---
    property bool showPreview: false // Für Vorschau-Modi, falls benötigt
    property string scheme: "default" // Aktuelles Farbschema
    property string flavour: "default" // Aktueller Farb-Flavour
    readonly property bool light: showPreview ? previewLight : currentLight
    property bool currentLight: false // Aktueller Hell/Dunkel-Modus (false = dunkel, true = hell)
    property bool previewLight: false // Hell/Dunkel-Modus für die Vorschau

    // --- Farbpaletten ---
    readonly property M3Palette palette: showPreview ? preview : current // Aktive Palette (Vorschau oder aktuell)
    readonly property M3TPalette tPalette: M3TPalette {} // Transparente Palette
    readonly property M3Palette current: M3Palette {} // Aktuelle Basis-Palette
    readonly property M3Palette preview: M3Palette {} // Vorschau-Palette

    // --- Transparenz und Wallpaper-Analyse (Annahmen für externe Abhängigkeiten) ---
    readonly property Transparency transparency: Transparency {}
    readonly property alias wallLuminance: analyser.luminance // Annahme: ImageAnalyser ist verfügbar

    // --- Hilfsfunktionen ---
    function getLuminance(c) {
        if (c.r == 0 && c.g == 0 && c.b == 0)
            return 0;
        return Math.sqrt(0.299 * (c.r ** 2) + 0.587 * (c.g ** 2) + 0.114 * (c.b ** 2));
    }

    function alterColour(c, a, layer) {
        const luminance = getLuminance(c);

        // Anpassung der Farbhelligkeit basierend auf Lichtmodus, Transparenz und Wallpaper-Luminanz
        // Die genauen Multiplikatoren können je nach gewünschtem Effekt angepasst werden
        const offset = (!light || layer == 1 ? 1 : -layer / 2) * (light ? 0.2 : 0.3) * (1 - transparency.base) * (1 + wallLuminance * (light ? (layer == 1 ? 3 : 1) : 2.5));
        const scale = (luminance + offset) / luminance;
        const r = Math.max(0, Math.min(1, c.r * scale));
        const g = Math.max(0, Math.min(1, c.g * scale));
        const b = Math.max(0, Math.min(1, c.b * scale));

        return Qt.rgba(r, g, b, a);
    }

    function layer(c, layer = 1) { // Standardwert für layer hinzugefügt
        if (!transparency.enabled)
            return c;

        // Wenn layer 0 ist, wird nur die Basistransparenz angewendet
        return layer === 0 ? Qt.alpha(c, transparency.base) : alterColour(c, transparency.layers, layer);
    }

    function on(c: color): color {
        // Ermittelt die "On"-Farbe (Textfarbe) basierend auf der Helligkeit der Eingabefarbe
        if (c.hslLightness < 0.5)
            return Qt.hsla(c.hslHue, c.hslSaturation, 0.9, 1); // Hellere Farbe für dunklen Hintergrund
        return Qt.hsla(c.hslHue, c.hslSaturation, 0.1, 1); // Dunklere Farbe für hellen Hintergrund
    }

    // --- Farbschema laden ---
    function load(data, isPreview) {
        const colours = isPreview ? preview : current;
        const theme = JSON.parse(data);

        const schemeName = (isPreview ? root.previewLight : root.currentLight) ? "light" : "dark";
        const schemeData = theme.schemes[schemeName];

        if (!isPreview) {
            root.scheme = "material"; // Placeholder name from the file
            root.flavour = schemeName;
        }

        for (const [name, colour] of Object.entries(schemeData)) {
            const propName = name.startsWith("term") ? name : `m3${name.charAt(0).toUpperCase() + name.slice(1)}`;
            if (colours.hasOwnProperty(propName)) {
                colours[propName] = colour;
            }
        }
    }

    // --- Modus setzen (externe Abhängigkeit) ---
    function setMode(mode: string): void {
        // Quickshell.execDetached(["caelestia", "scheme", "set", "--notify", "-m", mode]);
        console.log("setMode called with:", mode, " - external 'caelestia' executable not integrated.");
    }

    // --- Dateibetrachtung für Farbschema (Annahme für Pfad) ---
    FileView {
        // path: `${Paths.state}/scheme.json` // Annahme: Paths.state ist definiert
        path: "/etc/nixos/home-manager/philipp/modules/quickshell/material-theme.json" // Pfad zur material-theme.json im Root-Verzeichnis
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.load(text(), false)
    }

    // --- Bildanalyse für Wallpaper-Luminanz (Annahme für Wallpapers) ---
    QtObject {
        id: analyser
        property real luminance: 0.5 // Dummy-Wert, da ImageAnalyser nicht verfügbar ist
        // source: Wallpapers.current // Annahme: Wallpapers.current ist verfügbar
        // source: "" // Placeholder, muss an tatsächliche Wallpaper-Quelle angepasst werden
    }

    // --- Transparenz-Einstellungen (Annahme für Appearance) ---
    component Transparency: QtObject {
        // readonly property bool enabled: Appearance.transparency.enabled // Annahme: Appearance.transparency ist verfügbar
        readonly property bool enabled: true // Temporär auf true gesetzt
        // readonly property real base: Appearance.transparency.base - (root.light ? 0.1 : 0)
        readonly property real base: 0.8 - (root.light ? 0.1 : 0) // Temporärer Wert
        // readonly property real layers: Appearance.transparency.layers
        readonly property real layers: 0.08 // Temporärer Wert
    }

    // --- Material 3 Farbpalette (Basiswerte) ---
    component M3Palette: QtObject {
        // Hier werden die Standard-Material 3 Farben definiert.
        // Diese werden dann dynamisch angepasst.
        // Die Namen müssen mit denen im JSON-Schema übereinstimmen (ohne m3-Präfix im JSON, aber hier mit m3-Präfix und CamelCase)

        property color m3Primary: "#A9D291"
        property color m3SurfaceTint: "#A9D291"
        property color m3OnPrimary: "#173807"
        property color m3PrimaryContainer: "#2D4F1D"
        property color m3OnPrimaryContainer: "#C5EFAB"

        property color m3Secondary: "#BDCBB0"
        property color m3OnSecondary: "#283421"
        property color m3SecondaryContainer: "#3E4A36"
        property color m3OnSecondaryContainer: "#D8E7CB"

        property color m3Tertiary: "#A0CFD0"
        property color m3OnTertiary: "#003738"
        property color m3TertiaryContainer: "#1E4E4F"
        property color m3OnTertiaryContainer: "#BBEBEC"

        property color m3Error: "#FFB4AB"
        property color m3OnError: "#690005"
        property color m3ErrorContainer: "#93000A"
        property color m3OnErrorContainer: "#FFDAD6"

        property color m3Background: "#11140F"
        property color m3OnBackground: "#E1E4D9"
        property color m3Surface: "#11140F"
        property color m3OnSurface: "#E1E4D9"

        property color m3SurfaceVariant: "#43483E"
        property color m3OnSurfaceVariant: "#C3C8BB"

        property color m3Outline: "#8D9286"
        property color m3OutlineVariant: "#43483E"

        property color m3Shadow: "#000000"
        property color m3Scrim: "#000000"

        property color m3InverseSurface: "#E1E4D9"
        property color m3InverseOnSurface: "#2E312B"
        property color m3InversePrimary: "#446732"

        property color m3PrimaryFixed: "#C5EFAB"
        property color m3OnPrimaryFixed: "#072100"
        property color m3FixedDimPrimary: "#A9D291"
        property color m3OnPrimaryFixedVariant: "#2D4F1D"

        property color m3SecondaryFixed: "#D8E7CB"
        property color m3OnSecondaryFixed: "#131F0D"
        property color m3FixedDimSecondary: "#BDCBB0"
        property color m3OnSecondaryFixedVariant: "#3E4A36"

        property color m3TertiaryFixed: "#BBEBEC"
        property color m3OnTertiaryFixed: "#002020"
        property color m3FixedDimTertiary: "#A0CFD0"
        property color m3OnTertiaryFixedVariant: "#1E4E4F"

        property color m3SurfaceDim: "#11140F"
        property color m3SurfaceBright: "#373A33"
        property color m3SurfaceContainerLowest: "#0C0F0A"
        property color m3SurfaceContainerLow: "#191D16"
        property color m3SurfaceContainer: "#1D211A"
        property color m3SurfaceContainerHigh: "#282B24"
        property color m3SurfaceContainerHighest: "#32362F"

        // Zusätzliche Farben aus dem Caelestia-Beispiel, falls benötigt
        property color m3Success: "#B5CCBA"
        property color m3OnSuccess: "#213528"
        property color m3SuccessContainer: "#374B3E"
        property color m3OnSuccessContainer: "#D1E9D6"

        // Terminal-Farben, falls im Schema enthalten
        property color term0: "#000000"
        property color term1: "#FF0000"
        property color term2: "#00FF00"
        property color term3: "#FFFF00"
        property color term4: "#0000FF"
        property color term5: "#FF00FF"
        property color term6: "#00FFFF"
        property color term7: "#FFFFFF"
        property color term8: "#888888"
        property color term9: "#FF8888"
        property color term10: "#88FF88"
        property color term11: "#FFFF88"
        property color term12: "#8888FF"
        property color term13: "#FF88FF"
        property color term14: "#88FFFF"
        property color term15: "#CCCCCC"
    }

    // --- Material 3 Transparente Palette (wendet Layering an) ---
    component M3TPalette: QtObject {
        // Alle Farben der M3Palette werden hier durch die layer-Funktion geleitet
        // um Transparenz und dynamische Anpassungen zu erhalten.
        // Die Namen müssen exakt denen in M3Palette entsprechen.

        readonly property color m3Primary: root.layer(root.palette.m3Primary)
        readonly property color m3SurfaceTint: root.layer(root.palette.m3SurfaceTint)
        readonly property color m3OnPrimary: root.layer(root.palette.m3OnPrimary)
        readonly property color m3PrimaryContainer: root.layer(root.palette.m3PrimaryContainer)
        readonly property color m3OnPrimaryContainer: root.layer(root.palette.m3OnPrimaryContainer)

        readonly property color m3Secondary: root.layer(root.palette.m3Secondary)
        readonly property color m3OnSecondary: root.layer(root.palette.m3OnSecondary)
        readonly property color m3SecondaryContainer: root.layer(root.palette.m3SecondaryContainer)
        readonly property color m3OnSecondaryContainer: root.layer(root.palette.m3OnSecondaryContainer)

        readonly property color m3Tertiary: root.layer(root.palette.m3Tertiary)
        readonly property color m3OnTertiary: root.layer(root.palette.m3OnTertiary)
        readonly property color m3TertiaryContainer: root.layer(root.palette.m3TertiaryContainer)
        readonly property color m3OnTertiaryContainer: root.layer(root.palette.m3OnTertiaryContainer)

        readonly property color m3Error: root.layer(root.palette.m3Error)
        readonly property color m3OnError: root.layer(root.palette.m3OnError)
        readonly property color m3ErrorContainer: root.layer(root.palette.m3ErrorContainer)
        readonly property color m3OnErrorContainer: root.layer(root.palette.m3OnErrorContainer)

        readonly property color m3Background: root.layer(root.palette.m3Background, 0) // Hintergrund oft mit Basistransparenz
        readonly property color m3OnBackground: root.layer(root.palette.m3OnBackground)
        readonly property color m3Surface: root.layer(root.palette.m3Surface, 0) // Surface oft mit Basistransparenz
        readonly property color m3OnSurface: root.layer(root.palette.m3OnSurface)

        readonly property color m3SurfaceVariant: root.layer(root.palette.m3SurfaceVariant, 0)
        readonly property color m3OnSurfaceVariant: root.layer(root.palette.m3OnSurfaceVariant)

        readonly property color m3Outline: root.layer(root.palette.m3Outline)
        readonly property color m3OutlineVariant: root.layer(root.palette.m3OutlineVariant)

        readonly property color m3Shadow: root.layer(root.palette.m3Shadow)
        readonly property color m3Scrim: root.layer(root.palette.m3Scrim)

        readonly property color m3InverseSurface: root.layer(root.palette.m3InverseSurface, 0)
        readonly property color m3InverseOnSurface: root.layer(root.palette.m3InverseOnSurface)
        readonly property color m3InversePrimary: root.layer(root.palette.m3InversePrimary)

        readonly property color m3PrimaryFixed: root.layer(root.palette.m3PrimaryFixed)
        readonly property color m3OnPrimaryFixed: root.layer(root.palette.m3OnPrimaryFixed)
        readonly property color m3FixedDimPrimary: root.layer(root.palette.m3FixedDimPrimary)
        readonly property color m3OnPrimaryFixedVariant: root.layer(root.palette.m3OnPrimaryFixedVariant)

        readonly property color m3SecondaryFixed: root.layer(root.palette.m3SecondaryFixed)
        readonly property color m3OnSecondaryFixed: root.layer(root.palette.m3OnSecondaryFixed)
        readonly property color m3FixedDimSecondary: root.layer(root.palette.m3FixedDimSecondary)
        readonly property color m3OnSecondaryFixedVariant: root.layer(root.palette.m3OnSecondaryFixedVariant)

        readonly property color m3TertiaryFixed: root.layer(root.palette.m3TertiaryFixed)
        readonly property color m3OnTertiaryFixed: root.layer(root.palette.m3OnTertiaryFixed)
        readonly property color m3FixedDimTertiary: root.layer(root.palette.m3FixedDimTertiary)
        readonly property color m3OnTertiaryFixedVariant: root.layer(root.palette.m3OnTertiaryFixedVariant)

        readonly property color m3SurfaceDim: root.layer(root.palette.m3SurfaceDim, 0)
        readonly property color m3SurfaceBright: root.layer(root.palette.m3SurfaceBright, 0)
        readonly property color m3SurfaceContainerLowest: root.layer(root.palette.m3SurfaceContainerLowest)
        readonly property color m3SurfaceContainerLow: root.layer(root.palette.m3SurfaceContainerLow)
        readonly property color m3SurfaceContainer: root.layer(root.palette.m3SurfaceContainer)
        readonly property color m3SurfaceContainerHigh: root.layer(root.palette.m3SurfaceContainerHigh)
        readonly property color m3SurfaceContainerHighest: root.layer(root.palette.m3SurfaceContainerHighest)

        readonly property color m3Success: root.layer(root.palette.m3Success)
        readonly property color m3OnSuccess: root.layer(root.palette.m3OnSuccess)
        readonly property color m3SuccessContainer: root.layer(root.palette.m3SuccessContainer)
        readonly property color m3OnSuccessContainer: root.layer(root.palette.m3OnSuccessContainer)

        readonly property color term0: root.layer(root.palette.term0)
        readonly property color term1: root.layer(root.palette.term1)
        readonly property color term2: root.layer(root.palette.term2)
        readonly property color term3: root.layer(root.palette.term3)
        readonly property color term4: root.layer(root.palette.term4)
        readonly property color term5: root.layer(root.palette.term5)
        readonly property color term6: root.layer(root.palette.term6)
        readonly property color term7: root.layer(root.palette.term7)
        readonly property color term8: root.layer(root.palette.term8)
        readonly property color term9: root.layer(root.palette.term9)
        readonly property color term10: root.layer(root.palette.term10)
        readonly property color term11: root.layer(root.palette.term11)
        readonly property color term12: root.layer(root.palette.term12)
        readonly property color term13: root.layer(root.palette.term13)
        readonly property color term14: root.layer(root.palette.term14)
        readonly property color term15: root.layer(root.palette.term15)
    }
}
