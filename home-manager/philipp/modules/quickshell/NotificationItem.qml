import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    height: contentColumn.height + 20
    radius: 12
    color: "#1A1A1A"
    
    property var notification
    
    ColumnLayout {
        id: contentColumn
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 8
        
        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            
            // App Icon
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 6
                color: "#2A2A2A"
                visible: root.notification && root.notification.appIcon !== ""
                
                Image {
                    anchors.fill: parent
                    anchors.margins: 4
                    source: root.notification ? root.notification.appIcon : ""
                    fillMode: Image.PreserveAspectFit
                }
            }
            
            // App Name
            Text {
                text: root.notification ? root.notification.appName : ""
                color: "white"
                font.pixelSize: 13
                font.weight: Font.Medium
                Layout.fillWidth: true
            }
            
            // Close Button
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: closeHover.hovered ? "#3A3A3A" : "transparent"
                
                Text {
                    text: "close"
                    color: "white"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 16
                    anchors.centerIn: parent
                }
                
                HoverHandler {
                    id: closeHover
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.notification) {
                            root.notification.dismiss();
                        }
                    }
                }
            }
        }
        
        // Summary
        Text {
            text: root.notification ? root.notification.summary : ""
            color: "white"
            font.pixelSize: 14
            font.weight: Font.Bold
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: text !== ""
        }
        
        // Body
        Text {
            text: root.notification ? root.notification.body : ""
            color: "#CCC"
            font.pixelSize: 13
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            visible: text !== ""
            textFormat: Text.PlainText
        }
        
        // Image (smaller in center)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            radius: 6
            color: "#2A2A2A"
            visible: root.notification && root.notification.image !== ""
            clip: true
            
            Image {
                anchors.fill: parent
                source: root.notification ? root.notification.image : ""
                fillMode: Image.PreserveAspectCrop
            }
        }
        
        // Actions (compact)
        Flow {
            Layout.fillWidth: true
            spacing: 6
            visible: root.notification && root.notification.actions && root.notification.actions.length > 0
            
            Repeater {
                model: (root.notification && root.notification.actions) ? root.notification.actions : []
                
                Rectangle {
                    width: actionText.width + 16
                    height: 28
                    radius: 6
                    color: actionHover.hovered ? "#3A3A3A" : "#2A2A2A"
                    
                    Text {
                        id: actionText
                        text: modelData ? modelData.text : ""
                        color: "white"
                        font.pixelSize: 12
                        anchors.centerIn: parent
                    }
                    
                    HoverHandler {
                        id: actionHover
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (modelData) {
                                modelData.invoke();
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Urgency Indicator (smaller)
    Rectangle {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: 3
        radius: 1.5
        color: {
            if (!root.notification) return "#FFB84A";
            switch (root.notification.urgency) {
                case 0: return "#4A9EFF"; // Low
                case 1: return "#FFB84A"; // Normal
                case 2: return "#FF4A4A"; // Critical
                default: return "#FFB84A";
            }
        }
    }
}
