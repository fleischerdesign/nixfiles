import Quickshell
import QtQuick
import qs.services
import qs.components

// REINE UI - keine Business Logic
PanelWindow {
    id: popupContainer
    
    anchors {
        right: true
        top: true
    }
    margins.right: 10
    margins.top: 10
    
    implicitWidth: 400
    implicitHeight: 800 // Feste Höhe, groß genug für mehrere Popups
    color: "transparent"
    exclusiveZone: 0
    visible: NotificationService.popupCount > 0
    
    // Mask definiert den klickbaren Bereich dynamisch
    mask: Region {
        item: popupColumn
    }
    
    Column {
        id: popupColumn
        width: parent.width
        spacing: 10
        
        move: Transition {
            NumberAnimation {
                properties: "y"
                duration: 200
                easing.type: Easing.OutQuad
            }
        }
        
        Repeater {
            model: NotificationService.activePopups
            
            delegate: Item {
                id: popupWrapper
                width: popupColumn.width
                height: popup.height
                
                NotificationCard {
                    id: popup
                    width: parent.width
                    notification: model.notification
                    onDismissRequested: NotificationService.dismiss(model.notification)
                    
                    // Animationen
                    opacity: model.dismissing ? 0 : slideProgress
                    x: model.dismissing ? 400 : ((1 - slideProgress) * 400)
                    
                    property real slideProgress: 0
                    
                    Component.onCompleted: {
                        slideInAnim.start();
                    }
                    
                    NumberAnimation {
                        id: slideInAnim
                        target: popup
                        property: "slideProgress"
                        from: 0
                        to: 1
                        duration: 300
                        easing.type: Easing.OutCubic
                    }
                    
                    Behavior on opacity {
                        NumberAnimation { 
                            duration: 200
                            easing.type: Easing.InQuad 
                        }
                    }
                    
                    Behavior on x {
                        NumberAnimation { 
                            duration: 200
                            easing.type: Easing.InQuad 
                        }
                    }
                    
                    HoverHandler {
                        id: hoverHandler
                        onHoveredChanged: {
                            if (hovered) {
                                NotificationService.pauseAutoHide(model.notification);
                            } else {
                                NotificationService.resumeAutoHide(model.notification);
                            }
                        }
                    }
                }
            }
        }
    }
}
