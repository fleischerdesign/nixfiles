import Quickshell
import QtQuick

PanelWindow {
    id: popupWindow
    
    property var notification
    property int popupIndex: 0
    property real slideProgress: 0
    
    signal dismissed()
    
    anchors {
        right: true
        top: true
    }
    margins.right: 10
    margins.top: 10 + (popupIndex * (popup.height + 10))
    
    width: 400
    height: popup.height
    color: "transparent"
    exclusiveZone: 0

    HoverHandler {
      id: popupWindowHover
    }

    Timer {
        id: autoHideTimer
        interval: 5000
        repeat: false
        running: !popupWindowHover.hovered && notification && !notification.resident
        onTriggered: popupWindow.startDismiss()
    }

    Behavior on margins.top {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutQuad
        }
    }
    
    function startDismiss() {
        slideOutAnimation.start();
    }
    
    NumberAnimation {
        id: slideInAnimation
        target: popupWindow
        property: "slideProgress"
        from: 0
        to: 1
        duration: 300
        easing.type: Easing.OutCubic
    }
    
    NumberAnimation {
        id: slideOutAnimation
        target: popupWindow
        property: "slideProgress"
        to: 0
        duration: 200
        easing.type: Easing.InCubic
        onFinished: popupWindow.dismissed()
    }
    
    Component.onCompleted: {
        slideInAnimation.start();
    }
    
    NotificationPopup {
        id: popup
        width: parent.width
        notification: popupWindow.notification
        
        opacity: popupWindow.slideProgress
        x: (1 - popupWindow.slideProgress) * 400
        
        onDismissRequested: {
            popupWindow.startDismiss();
        }
    }

    Connections {
        target: StateManager
        function onNotificationCenterOpenedChanged() {
            if (StateManager.notificationCenterOpened) {
                popupWindow.startDismiss();
            }
        }
    }
}
