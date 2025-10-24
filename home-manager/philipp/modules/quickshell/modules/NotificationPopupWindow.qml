import Quickshell
import QtQuick
import qs.services
import qs.modules

// REINE UI - keine Business Logic
PanelWindow {
    id: popupContainer
    
    anchors {
        right: true
	top: true
	bottom: true
    }
    margins.right: 10
    margins.top: 10
    
    implicitWidth: 400
    implicitHeight: Math.min(Screen.height - 100, popupColumn.implicitHeight)
    color: "transparent"
    exclusiveZone: 0
    visible: NotificationService.popupCount > 0
    
    Flickable {
        anchors.fill: parent
        contentHeight: popupColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        
        layer.enabled: true
        layer.smooth: true
        
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
                    
                    NotificationPopup {
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
}
