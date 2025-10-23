import QtQuick
import Quickshell

PanelWindow {
    id: interceptorWindow

    // Expose a signal that parent components can listen to.
    signal clicked()
    color: "transparent"

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    margins.bottom: 65

    MouseArea {
        anchors.fill: parent
        onClicked: {
            interceptorWindow.clicked()
        }
    }
}
