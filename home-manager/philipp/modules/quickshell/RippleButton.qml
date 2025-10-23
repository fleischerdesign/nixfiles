import QtQuick

// Reusable Button Component with Android-Style Ripple
Rectangle {
    id: button
    width: fixedWidth ? 55 : Math.max(55, contentItem.implicitWidth + 40)
    height: 55
    radius: 15
    color: M3ColorPalette.m3SurfaceContainer
    property color onColor: "#E1E4D9"

    signal clicked
    property bool fixedWidth: false
    default property alias content: contentItem.data
    clip: true

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
        stateColor: M3ColorPalette.m3OnSurface
        isHovered: hoverHandler.hovered
    }
    RippleEffect {
        rippleColor: button.onColor
        parentRadius: button.radius
        onClicked: button.clicked()
    }
}