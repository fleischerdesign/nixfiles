import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Scope {
    id: root
    
    // Öffentliche Properties, die von außen gesetzt werden
    property bool shouldShow: false
    property real value: 0.0  // 0.0 bis 1.0
    property string icon: "circle"
    property color barColor: "#ffffff"
    property int autoHideDelay: 2000
    
    // Layout-Eigenschaften
    property int osdWidth: 60
    property int osdHeight: 300
    property int slideDistance: 10
    property int rightMargin: 10
    
    PanelWindow {
        id: osdContainer
        anchors {
            right: true
            top: true
            bottom: true
        }
        margins.right: 0
        width: root.osdWidth + root.slideDistance + root.rightMargin
        height: root.osdHeight
        color: "transparent"
        mask: Region {}
        exclusiveZone: 0
        
        Rectangle {
            id: osdContent
            width: root.osdWidth
            height: root.osdHeight
            anchors.verticalCenter: parent.verticalCenter
            
            x: root.shouldShow ? root.rightMargin : parent.width
            
            Behavior on x {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }
            
            opacity: root.shouldShow ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }
            
            radius: 13
            color: "#000000"
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 10
                
                // Progress Bar
                Rectangle {
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignHCenter
                    width: 10
                    radius: 5
                    color: "#50ffffff"
                    
                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: parent.height * Math.max(0, Math.min(1, root.value))
                        radius: parent.radius
                        color: root.barColor
                        
                        Behavior on height {
                            NumberAnimation {
                                duration: 100
                                easing.type: Easing.OutQuad
                            }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                    }
                }
                
                // Icon
                Text {
                    text: root.icon
                    color: "white"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 24
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
