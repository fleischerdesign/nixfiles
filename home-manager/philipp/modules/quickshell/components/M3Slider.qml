import QtQuick
import QtQuick.Controls.Basic
import qs.services

Item {
    id: root

    // --- Public API ---
    // We alias all the relevant properties from the internal Slider.
    // This makes our component behave just like a regular Slider from the outside.
    property alias value: slider.value
    property alias from: slider.from
    property alias to: slider.to
    property alias stepSize: slider.stepSize
    property alias pressed: slider.pressed
    property alias position: slider.position

    // Our custom properties
    property bool toggled: true
    property string icon: ""
    signal iconClicked()

    // --- Internal Logic ---
    readonly property real displayPosition: toggled ? slider.position : 0

    // --- Visuals and Children ---
    implicitHeight: 40

    // The actual Slider control, providing logic and state.
    // It's mostly transparent to input where the icon is.
    Slider {
        id: slider
        anchors.fill: parent
        stepSize: 0.05
        wheelEnabled: true
        handle: null

        background: Rectangle {
            id: backgroundTrack
            width: slider.width
            height: 30
            radius: 15
            color: ColorService.palette.m3SurfaceContainerHighest
            anchors.verticalCenter: parent.verticalCenter

            // The progress bar's width is driven by our custom displayPosition.
            Rectangle {
                id: progressBar
                width: backgroundTrack.width * root.displayPosition
                height: parent.height
                radius: 15
                color: ColorService.palette.m3Primary
            }
        }
    }

    // The Icon is a sibling to the Slider, layered on top.
    // This is crucial to separate its input handling from the Slider's.
    Text {
        id: iconText
        visible: root.icon !== ""
        text: root.icon
        font.family: "Material Symbols Rounded"
        font.pixelSize: 20
        color: ColorService.palette.m3OnPrimary
        
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 10

        // This MouseArea only covers the icon. Its clicks will not be seen by the Slider.
        MouseArea {
            anchors.fill: parent
            onClicked: root.iconClicked()
        }
    }
}