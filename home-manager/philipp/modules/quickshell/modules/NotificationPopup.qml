import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services

Rectangle {
    id: root
    width: 400
    height: expanded ? contentColumn.height + 30 : 130
    radius: 15
    clip: true
    
    property var notification
    property bool isInNotificationCenter: false
    property bool expanded: false
    
    // Hintergrundfarbe basierend auf Urgency
    color: {
        if (!root.notification)
            return ColorService.palette.m3SurfaceContainer;

        var baseColor = root.isInNotificationCenter
            ? ColorService.palette.m3SurfaceContainerHigh
            : ColorService.palette.m3SurfaceContainer;

        switch (root.notification.urgency) {
        case 0: // Low
            return baseColor;
        case 1: // Normal
            return baseColor;
        case 2: // Critical
            return ColorService.palette.m3ErrorContainer;
        default:
            return baseColor;
        }
    }

    // Content-Farbe basierend auf Urgency
    property color onSurfaceColor: {
        if (!root.notification)
            return ColorService.palette.m3OnSurface;
        switch (root.notification.urgency) {
        case 0: // Low
            return ColorService.palette.m3OnSurface;
        case 1: // Normal
            return ColorService.palette.m3OnSurface;
        case 2: // Critical
            return ColorService.palette.m3OnErrorContainer;
        default:
            return ColorService.palette.m3OnSurface;
        }
    }

    signal dismissRequested

    // Smooth height animation
    Behavior on height {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    RippleEffect {
        id: rippleEffect
        enabled: root.enabled
        rippleColor: root.onSurfaceColor
        parentRadius: root.radius
    }

    // State Layer mit neuer API
    M3StateLayer {
        colorRole: root.notification && root.notification.urgency === 2 
            ? M3StateLayer.ColorRole.Error 
            : M3StateLayer.ColorRole.Surface
        customStateColor: root.onSurfaceColor
        isHovered: mouseArea.containsMouse
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton

        onPressed: (mouse) => {
            rippleEffect.trigger(mouse.x, mouse.y);
        }

        onClicked: {
            root.expanded = !root.expanded;
        }
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

        // Compact Header (immer sichtbar)
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

            // Summary (Title) - Compact
            Text {
                text: root.notification ? root.notification.summary : ""
                color: root.onSurfaceColor
                font.pixelSize: 14
                font.weight: Font.Medium
                Layout.fillWidth: true
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            RippleButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                style: RippleButton.Style.Text
                colorRole: root.notification && root.notification.urgency === 2 
                    ? RippleButton.ColorRole.Error 
                    : RippleButton.ColorRole.Surface
                icon: root.expanded ? "expand_less" : "expand_more"
                iconOnly: true
                iconSize: 18
                opacity: popupHover.hovered ? 1 : 0
                onClicked: {
                   root.expanded = !root.expanded
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }
            }
        

            // Close Button
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
                onClicked: {
                    root.dismissRequested()
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }
            }
        }

        // Expanded Content
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            // Body
            Text {
                text: root.notification ? root.notification.body : ""
                color: root.onSurfaceColor
                font.pixelSize: 14
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
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

            // Actions
            Flow {
                Layout.fillWidth: true
                spacing: 8
                visible: root.notification && root.notification.actions && root.notification.actions.length > 0

                Repeater {
                    model: (root.notification && root.notification.actions) ? root.notification.actions : []

                    RippleButton {
                        implicitHeight: 32
                        style: RippleButton.Style.Filled
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
    }
    
    // Smooth color transitions
    Behavior on color {
        ColorAnimation { duration: 200 }
    }
    
    // Fade-out Gradient Overlay (nur wenn collapsed)
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 40
        visible: !root.expanded
        radius: root.radius
        gradient: Gradient {
            GradientStop { 
                position: 0.0
                color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0)
            }
            GradientStop { 
                position: 1.0
                color: root.color
            }
        }
    }
}
