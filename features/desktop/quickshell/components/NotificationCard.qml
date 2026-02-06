import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

Rectangle {
    id: root
    
    property var notification
    property bool isInNotificationCenter: false
    property bool expanded: false

    signal dismissRequested

    implicitWidth: 380
    // Height logic: Auto-expand based on content
    height: expanded ? contentColumn.implicitHeight + 24 : Math.min(contentColumn.implicitHeight + 24, 90)
    
    radius: FrameTheme.radius
    color: FrameTheme.card
    border.width: FrameTheme.borderWidth
    border.color: notification && notification.urgency === 2 ? FrameTheme.destructive : FrameTheme.border
    clip: true

    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    // Hover Background
    Rectangle {
        anchors.fill: parent
        color: FrameTheme.accent
        opacity: hoverHandler.hovered ? 0.4 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    HoverHandler { id: hoverHandler }
    
    TapHandler {
        id: tapHandler
        onTapped: root.expanded = !root.expanded
    }

    ColumnLayout {
        id: contentColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        spacing: 8

        // Header: Icon + Title
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            
            // App Icon
            Item {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                visible: root.notification && root.notification.appIcon !== ""
                
                Image {
                    anchors.fill: parent
                    source: root.notification ? root.notification.appIcon : ""
                    fillMode: Image.PreserveAspectFit
                    mipmap: true
                }
            }

            Text {
                text: root.notification ? root.notification.summary : ""
                color: FrameTheme.foreground
                font.family: FrameTheme.fontFamily
                font.pixelSize: 14
                font.weight: Font.Bold
                Layout.fillWidth: true
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            
            // Spacer for Close Button
            Item { width: 20 }
        }
        
        // Body
        Text {
            text: root.notification ? root.notification.body : ""
            color: FrameTheme.mutedForeground
            font.family: FrameTheme.fontFamily
            font.pixelSize: 13
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            elide: root.expanded ? Text.ElideNone : Text.ElideRight
            maximumLineCount: root.expanded ? 99 : 2
            textFormat: Text.PlainText
        }

        // Image (Expanded only)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            radius: FrameTheme.radius
            color: FrameTheme.muted
            visible: root.expanded && root.notification && root.notification.image !== ""
            clip: true

            Image {
                anchors.fill: parent
                source: root.notification ? root.notification.image : ""
                fillMode: Image.PreserveAspectCrop
            }
        }

        // Actions (Expanded only)
        Flow {
            Layout.fillWidth: true
            spacing: 8
            visible: root.expanded && root.notification && root.notification.actions && root.notification.actions.length > 0

            Repeater {
                model: (root.notification && root.notification.actions) ? root.notification.actions : []

                FrameButton {
                    variant: FrameButton.Variant.Outline
                    text: modelData ? modelData.text : ""
                    implicitHeight: 32
                    onClicked: {
                        if (modelData) modelData.invoke()
                        if (root.notification && !root.notification.resident) root.dismissRequested()
                    }
                }
            }
        }
    }

    // Close Button (Top Right Overlay)
    FrameButton {
        width: 24
        height: 24
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        variant: FrameButton.Variant.Ghost
        icon: "close"
        
        // Visible on hover OR if expanded
        visible: hoverHandler.hovered || root.expanded
        
        onClicked: root.dismissRequested()
    }
}