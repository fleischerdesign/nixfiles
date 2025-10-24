import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

Rectangle {
    id: root
    width: 400
    height: contentColumn.height + 30
    radius: 15
    clip: true
    
    property var notification
    property bool isInNotificationCenter: false
    
    // Hintergrundfarbe basierend auf Urgency
    color: {
        if (!root.notification)
            return Colors.palette.m3SurfaceContainer;

        var baseColor = root.isInNotificationCenter
            ? Colors.palette.m3SurfaceContainerHigh
            : Colors.palette.m3SurfaceContainer;

        switch (root.notification.urgency) {
        case 0: // Low
            return baseColor;
        case 1: // Normal
            return baseColor;
        case 2: // Critical
            return Colors.palette.m3ErrorContainer;
        default:
            return baseColor;
        }
    }

    // Content-Farbe basierend auf Urgency
    property color onSurfaceColor: {
        if (!root.notification)
            return Colors.palette.m3OnSurface;
        switch (root.notification.urgency) {
        case 0: // Low
            return Colors.palette.m3OnSurface;
        case 1: // Normal
            return Colors.palette.m3OnSurface;
        case 2: // Critical
            return Colors.palette.m3OnErrorContainer;
        default:
            return Colors.palette.m3OnSurface;
        }
    }

    signal dismissRequested

    // State Layer mit neuer API
    M3StateLayer {
        colorRole: root.notification && root.notification.urgency === 2 
            ? M3StateLayer.ColorRole.Error 
            : M3StateLayer.ColorRole.Surface
        customStateColor: root.onSurfaceColor
        isHovered: popupHover.hovered
    }
    
    HoverHandler {
        id: popupHover
    }

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
                color: root.onSurfaceColor
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
                color: root.onSurfaceColor
                font.pixelSize: 12
                Layout.fillWidth: true
            }

            // Close Button mit neuem RippleButton
            RippleButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                style: RippleButton.Style.Text
                colorRole: root.notification && root.notification.urgency === 2 
                    ? RippleButton.ColorRole.Error 
                    : RippleButton.ColorRole.Surface
                icon: "close"
                iconOnly: true
                iconSize: 18
                opacity: popupHover.hovered ? 1 : 0
                onClicked: root.dismissRequested()

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }
            }
        }

        // Summary (Title)
        Text {
            text: root.notification ? root.notification.summary : ""
            color: root.onSurfaceColor
            font.pixelSize: 16
            font.weight: Font.Bold
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: text !== ""
        }

        // Body
        Text {
            text: root.notification ? root.notification.body : ""
            color: root.onSurfaceColor
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
            color: root.onSurfaceColor
            visible: root.notification && root.notification.image !== ""
            clip: true

            Image {
                anchors.fill: parent
                source: root.notification ? root.notification.image : ""
                fillMode: Image.PreserveAspectCrop
            }
        }

        // Actions mit neuem RippleButton
        Flow {
            Layout.fillWidth: true
            spacing: 8
            visible: root.notification && root.notification.actions && root.notification.actions.length > 0

            Repeater {
                model: (root.notification && root.notification.actions) ? root.notification.actions : []

                RippleButton {
                    implicitHeight: 32
                    style: RippleButton.Style.Text
                    colorRole: root.notification && root.notification.urgency === 2 
                        ? RippleButton.ColorRole.Error 
                        : RippleButton.ColorRole.Primary
                    text: modelData ? modelData.text : ""
                    
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
    
    // Smooth color transitions
    Behavior on color {
        ColorAnimation { duration: 200 }
    }
}
