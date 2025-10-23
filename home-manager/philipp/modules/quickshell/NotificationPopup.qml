import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    width: 400
    height: contentColumn.height + 30
    radius: 15
    color: M3ColorPalette.m3SurfaceContainer
    
    property var notification
    signal dismissRequested()
    
    ColumnLayout {
        id: contentColumn
        anchors {
            left: parent.left
            right: parent.right
	    top: parent.top
            margins: 15
        }
        spacing: 10
        
        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            
            // App Icon
            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 8
                color: M3ColorPalette.m3OnSurface
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
                color: M3ColorPalette.m3OnSurface
                font.pixelSize: 12
                Layout.fillWidth: true
            }
            
            // Close Button
            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 12
                color: closeHover.hovered ? M3ColorPalette.m3Primary : "transparent"
                
                Text {
                    text: "close"
                    color: M3ColorPalette.m3OnPrimary
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 18
                    anchors.centerIn: parent
                }
                
                HoverHandler {
                    id: closeHover
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.dismissRequested()
                }
            }
        }
        
        // Summary (Title)
        Text {
            text: root.notification ? root.notification.summary : ""
            color: "white"
            font.pixelSize: 16
            font.weight: Font.Bold
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: text !== ""
        }
        
        // Body
        Text {
            text: root.notification ? root.notification.body : ""
            color: M3ColorPalette.m3OnSurface
            font.pixelSize: 14
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            maximumLineCount: 5
            elide: Text.ElideRight
            visible: text !== ""
            textFormat: Text.PlainText
        }
        
        // Image
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            radius: 8
            color: "#2A2A2A"
            visible: root.notification && root.notification.image !== ""
            clip: true
            
            Image {
                anchors.fill: parent
                source: root.notification ? root.notification.image : ""
                fillMode: Image.PreserveAspectCrop
            }
        }
        
        // Actions
        Flow {
            Layout.fillWidth: true
            spacing: 8
            visible: root.notification && root.notification.actions && root.notification.actions.length > 0
            
            Repeater {
                model: (root.notification && root.notification.actions) ? root.notification.actions : []
                
                Rectangle {
                    width: actionText.width + 20
                    height: 32
                    radius: 8
                    color: actionHover.hovered ? "#3A3A3A" : "#2A2A2A"
                    
                    Text {
                        id: actionText
                        text: modelData ? modelData.text : ""
                        color: "white"
                        font.pixelSize: 13
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
                            if (root.notification && !root.notification.resident) {
                                root.dismissRequested();
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Urgency Indicator
    Rectangle {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: 4
        radius: 2
        color: {
            if (!root.notification) return "#FFB84A";
            switch (root.notification.urgency) {
                case 0: return M3ColorPalette.m3Tertiary; // Low - Blue
                case 1: return M3ColorPalette.m3Primary; // Normal - Orange
                case 2: return M3ColorPalette.m3Error; // Critical - Red
                default: return "#FFB84A";
            }
        }
    }
}
