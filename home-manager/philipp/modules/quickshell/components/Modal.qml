import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components

PanelWindow {
    id: modal

    property Item contentItem: null
    property bool closeOnClickOutside: true

    signal backgroundClicked()

    color: "transparent"

    mask: Region {
        item: bottomBarArea
        intersection: Region.Intersection.Xor
    }

    Rectangle {
        id: bottomBarArea
        width: parent.width
        height: 65
        anchors.bottom: parent.bottom
        visible: false
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.layer: WlrLayershell.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Keys.onEscapePressed: {
        backgroundClicked()
    }

    MouseArea {
        anchors.fill: parent
        enabled: modal.visible

        onClicked: (mouse) => {
            if (contentItem) {
                const localPos = mapToItem(contentItem, mouse.x, mouse.y)
                if (localPos.x < 0 || localPos.x > contentItem.width || localPos.y < 0 || localPos.y > contentItem.height) {
                    if (closeOnClickOutside) {
                        backgroundClicked()
                    }
                }
            } else {
                if (closeOnClickOutside) {
                    backgroundClicked()
                }
            }
        }
    }
}
