import QtQuick
import QtQuick.Layouts
import qs.components

Rectangle {
    id: root
    width: 400
    height: contentColumn.height + 30
    radius: 15
    clip: true
    M3StateLayer {
      stateColor: onSurfaceColor
      isHovered: popupHover.hovered
    }
    HoverHandler {
        id: popupHover
    }
    property var notification
    property bool isInNotificationCenter: false
    color: {
        if (!root.notification)
            return "#FFB84A";

        var baseColor = root.isInNotificationCenter
            ? M3ColorPalette.m3SurfaceContainerHigh
            : M3ColorPalette.m3SurfaceContainer;

        switch (root.notification.urgency) {
        case 0:
            return baseColor;
        case 1:
            return baseColor;
        case 2:
            return M3ColorPalette.m3Error;
        default:
            return baseColor;
        }
    }

    property color onSurfaceColor: {
        if (!root.notification)
            return M3ColorPalette.m3OnSurface;
        switch (root.notification.urgency) {
        case 0:
            return M3ColorPalette.m3OnSurface;
        case 1:
            return M3ColorPalette.m3OnSurface;
        case 2:
            return M3ColorPalette.m3OnError;
        default:
            return M3ColorPalette.m3OnSurface;
        }
    }

    signal dismissRequested

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
                color: onSurfaceColor
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
                color: onSurfaceColor
                font.pixelSize: 12
                Layout.fillWidth: true
            }

            // Close Button
            RippleButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 12
                filled: false
                contentColor: root.onSurfaceColor
                onClicked: root.dismissRequested()
                opacity: popupHover.hovered ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                Text {
                    text: "close"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 18
                    color: root.onSurfaceColor // Bind to the button's content color
                }
            }
        }

        // Summary (Title)
        Text {
            text: root.notification ? root.notification.summary : ""
            color: onSurfaceColor
            font.pixelSize: 16
            font.weight: Font.Bold
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: text !== ""
        }

        // Body
        Text {
            text: root.notification ? root.notification.body : ""
            color: onSurfaceColor
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
            color: onSurfaceColor
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

                RippleButton {
                    height: 32
                    radius: 15 // As per user request
                    filled: false
                    contentColor: root.onSurfaceColor
                    baseOpacity: 0.1 // User wanted a visible resting state
                    hoverOpacity: 0.18 // A bit more than base
                    onClicked: {
                        if (modelData) {
                            modelData.invoke();
                        }
                        if (root.notification && !root.notification.resident) {
                            root.dismissRequested();
                        }
                    }

                    Text {
                        text: modelData ? modelData.text : ""
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        color: root.onSurfaceColor
                    }
                }
            }
        }
    }
}
