import QtQuick

// Reusable Button Component with Android-Style Ripple
// Supports 'filled' and 'text' styles.
Rectangle {
    id: button

    // --- Style & Content ---
    property bool filled: true
    property color filledColor: M3ColorPalette.m3SurfaceContainer
    property color contentColor: M3ColorPalette.m3OnSurface
    property color rippleColor: button.contentColor
    default property alias content: contentItem.data

    // --- State Layer (Hover/Focus Background) ---
    property color stateColor: button.contentColor
    property real baseOpacity: 0.0
    property real hoverOpacity: 0.08

    // --- Sizing ---
    property bool fixedWidth: false
    width: fixedWidth ? 55 : Math.max(55, contentItem.implicitWidth + 40)
    height: 55
    radius: 15
    clip: true

    // --- Behavior ---
    signal clicked

    // --- Implementation ---
    color: button.filled ? button.filledColor : "transparent"

    Behavior on color {
        ColorAnimation {
            duration: 150
        }
    }

    Item {
        id: contentItem
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
        anchors.centerIn: parent
        z: 3
    }
    HoverHandler {
        id: hoverHandler
    }

    M3StateLayer {
        z: 1
        stateColor: button.stateColor
        isHovered: hoverHandler.hovered
        baseOpacity: button.baseOpacity
        hoverOpacity: button.hoverOpacity
    }
    RippleEffect {
        rippleColor: button.rippleColor
        parentRadius: button.radius
        onClicked: button.clicked()
    }
}
