import QtQuick
import QtQuick.Controls.Basic
import qs.services

Item {
    id: root

    // --- Public API ---
    property real value
    property alias from: slider.from
    property alias to: slider.to
    property alias stepSize: slider.stepSize
    property alias pressed: slider.pressed
    property alias position: slider.position

    // Unsere benutzerdefinierten Eigenschaften
    property bool toggled: true
    property string icon: ""
    signal iconClicked()

    // Dynamische Icon-Farbe basierend auf dem 'toggled'-Zustand
    readonly property color iconColor: toggled ? ColorService.palette.m3OnPrimary : ColorService.palette.m3OnSurfaceVariant

    // --- Interne Logik ---
    // Diese Eigenschaft steuert die visuelle Position des Sliders.
    // Wenn 'toggled' false ist (d.h. stummgeschaltet), ist die Position 0.
    readonly property real displayPosition: toggled ? slider.position : 0

    onValueChanged: {
        if (!slider.pressed) {
            slider.value = value
        }
    }

    Component.onCompleted: {
        slider.value = value // Initialisiert den internen Slider-Wert
    }

    // --- Visuals and Children ---
    implicitHeight: 40

    // Das eigentliche Slider-Steuerelement, das Logik und Zustand bereitstellt.
    Slider {
        id: slider
        anchors.fill: parent
        stepSize: 0.05
        wheelEnabled: true
        handle: null

        // Wenn sich der Wert des internen Sliders ändert (z.B. durch Benutzerinteraktion),
        // aktualisieren wir die öffentliche 'value'-Eigenschaft, was das Signal auslöst.
        onValueChanged: {
            root.value = value
        }

        background: Rectangle {
            id: backgroundTrack
            width: slider.width
            height: 40
            radius: 15
            color: ColorService.palette.m3SurfaceContainerHighest
            anchors.verticalCenter: parent.verticalCenter

            // Die Breite des Fortschrittsbalkens wird jetzt durch 'displayPosition' gesteuert.
            Rectangle {
                id: progressBar
                width: backgroundTrack.width * root.displayPosition
                height: parent.height
                radius: 15
                color: ColorService.palette.m3Primary
            }
        }
    }

    // Das Icon ist ein Geschwister des Sliders und liegt darüber.
    Text {
        id: iconText
        visible: root.icon !== ""
        text: root.icon
        font.family: "Material Symbols Rounded"
        font.pixelSize: 20
        color: root.iconColor

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 10

        MouseArea {
            anchors.fill: parent
            onClicked: root.iconClicked()
        }
    }
}