import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    VolumeOSD {}
    BrightnessOSD {}
    
    WlSessionLock {
        id: sessionLocker
        // Surface wird dynamisch basierend auf locked-Status erstellt
        surface: sessionLocker.locked ? lockSurfaceComponent : null
        
        Component {
            id: lockSurfaceComponent
            WlSessionLockSurface {
                color: "transparent"
                Lockscreen {
                    id: lockScreenComponent
                    anchors.fill: parent
                    
                    onUnlocked: {
                        sessionLocker.locked = false;
                    }
                }
            }
        }
    }
    
    IpcHandler {
        target: "lockscreen"
        function lock(): void {
            sessionLocker.locked = true;
        }
    }
    
    PanelWindow {
        id: bottomBarWindow
        property bool isOpen: false
        
        // Dynamische Höhe: klein wenn geschlossen, groß wenn offen
       implicitHeight: isOpen ? 65 : (contentWrapper.y >= 55 ? 10 : 65) 
        anchors {
            left: true
            right: true
            bottom: true
        }
        exclusiveZone: 0
        color: "transparent"
        
        // HoverHandler für die Trigger-Zone
        HoverHandler {
            id: triggerHover
            onHoveredChanged: {
                if (hovered) {
                    bottomBarWindow.isOpen = true;
                }
            }
        }
        
        // Content-Wrapper mit Clip
        Item {
            id: clippingRect
            anchors.fill: parent
            clip: true
            
            Item {
                id: contentWrapper
                height: 65
                width: parent.width
                opacity: bottomBarWindow.isOpen ? 1 : 0
                y: bottomBarWindow.isOpen ? 0 : 55
                
                Behavior on y {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.InOutQuad
                    }
                }
                
                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }
                
                // HoverHandler für die geöffnete Bar
                HoverHandler {
                    id: barHover
                    onHoveredChanged: {
                        if (!hovered) {
                            bottomBarWindow.isOpen = false;
                        }
                    }
                }
                
                // MouseArea nur für Event-Propagation zu Buttons
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: false
                    propagateComposedEvents: true
                    onPressed: function(mouse) {
                        mouse.accepted = false;
                    }
                }
                
                Rectangle {
                    id: shadow
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: "#00000000"
                        }
                        GradientStop {
                            position: 1.0
                            color: "#ff000000"
                        }
                    }
                }
                
                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 10
                        bottomMargin: 10
                    }
                    spacing: 10
                    
                    RippleButton {
                        Layout.alignment: Qt.AlignVCenter
                        iconText: "home"
                        fixedWidth: true
                    }
                    
                    RippleButton {
                        Layout.alignment: Qt.AlignVCenter
                        iconText: "apps"
                        fixedWidth: true
                    }
                    
                    Item {
                        Layout.fillWidth: true
                    }
                    
                    RippleButton {
                        Layout.alignment: Qt.AlignVCenter
                        iconSize: 12
                        iconFamily: "Roboto"
                        fixedWidth: true
                        
                        Component.onCompleted: {
                            const now = new Date();
                            const hours = String(now.getHours()).padStart(2, '0');
                            const minutes = String(now.getMinutes()).padStart(2, '0');
                            iconText = hours + "\n" + minutes;
                        }
                        
                        Timer {
                            interval: 1000
                            running: true
                            repeat: true
                            onTriggered: {
                                const now = new Date();
                                const hours = String(now.getHours()).padStart(2, '0');
                                const minutes = String(now.getMinutes()).padStart(2, '0');
                                parent.iconText = hours + "\n" + minutes;
                            }
                        }
                    }
                    
                    RippleButton {
                        id: batteryButton
                        Layout.alignment: Qt.AlignVCenter
                        visible: UPower.displayDevice && UPower.displayDevice.type === 2
                        iconFamily: "Material Symbols Outlined"
                        iconSize: 20
                        fixedWidth: true
                        iconText: {
                            if (!UPower.displayDevice || !UPower.displayDevice.ready) {
                                return "battery_unknown";
                            }
                            const percent = Math.round(UPower.displayDevice.percentage * 100);
                            const charging = UPower.displayDevice.state === 1;
                            if (charging)
                                return "battery_android_bolt";
                            if (percent > 87)
                                return "battery_android_full";
                            if (percent > 75)
                                return "battery_android_6";
                            if (percent > 62)
                                return "battery_android_5";
                            if (percent > 50)
                                return "battery_android_4";
                            if (percent > 37)
                                return "battery_android_3";
                            if (percent > 25)
                                return "battery_android_2";
                            if (percent > 12.5)
                                return "battery_android_1";
                            return "battery_android_0";
                        }
                    }
                    
                    RippleButton {
                        Layout.alignment: Qt.AlignVCenter
                        iconText: "clarify"
                        fixedWidth: true
                    }
                }
            }
        }
    }
    
    // Reusable Button Component with Android-Style Ripple
    component RippleButton: Rectangle {
        id: button
        width: fixedWidth ? 55 : Math.max(55, buttonIcon.implicitWidth + 40)
        height: 55
        radius: 15
        color: "#000000"
        property alias iconText: buttonIcon.text
        property alias iconFamily: buttonIcon.font.family
        property alias iconSize: buttonIcon.font.pixelSize
        property bool fixedWidth: false
        clip: true
        
        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }
        
        Text {
            id: buttonIcon
            color: "white"
            font.family: "Material Symbols Rounded"
            font.pixelSize: 24
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            z: 3
        }
        
        Canvas {
            id: sparkleCanvas
            anchors.fill: parent
            z: 1
            property real rippleProgress: 0
            property point rippleCenter: Qt.point(0, 0)
            property var noisePattern: []
            
            function triggerRipple(x, y) {
                rippleCenter = Qt.point(x, y);
                rippleProgress = 0;
                rippleAnimation.restart();
            }
            
            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                
                ctx.save();
                ctx.beginPath();
                const r = button.radius;
                const w = width;
                const h = height;
                ctx.moveTo(r, 0);
                ctx.lineTo(w - r, 0);
                ctx.arcTo(w, 0, w, r, r);
                ctx.lineTo(w, h - r);
                ctx.arcTo(w, h, w - r, h, r);
                ctx.lineTo(r, h);
                ctx.arcTo(0, h, 0, h - r, r);
                ctx.lineTo(0, r);
                ctx.arcTo(0, 0, r, 0, r);
                ctx.closePath();
                ctx.clip();
                
                const maxRadius = Math.max(button.width, button.height) * 1.5;
                const currentRadius = rippleProgress * maxRadius;
                
                const baseOpacity = (1 - rippleProgress) * 0.25;
                if (baseOpacity > 0) {
                    const gradient = ctx.createRadialGradient(
                        rippleCenter.x, rippleCenter.y, currentRadius * 0.3,
                        rippleCenter.x, rippleCenter.y, currentRadius
                    );
                    gradient.addColorStop(0, `rgba(255, 255, 255, ${baseOpacity})`);
                    gradient.addColorStop(1, "rgba(255, 255, 255, 0)");
                    ctx.fillStyle = gradient;
                    ctx.beginPath();
                    ctx.arc(rippleCenter.x, rippleCenter.y, currentRadius, 0, Math.PI * 2);
                    ctx.fill();
                }
                
                ctx.restore();
            }
            
            NumberAnimation {
                id: rippleAnimation
                target: sparkleCanvas
                property: "rippleProgress"
                from: 0
                to: 1.2
                duration: 850
                easing.type: Easing.OutCubic
                onRunningChanged: {
                    if (running) {
                        sparkleTimer.start();
                    } else {
                        sparkleTimer.stop();
                    }
                }
            }
            
            Timer {
                id: sparkleTimer
                interval: 16
                repeat: true
                onTriggered: sparkleCanvas.requestPaint()
            }
        }
        
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            propagateComposedEvents: true
            onEntered: {
                parent.color = "#1A1A1A";
            }
            onExited: {
                parent.color = "#000000";
            }
            onPressed: function (mouse) {
                sparkleCanvas.triggerRipple(mouse.x, mouse.y);
                mouse.accepted = true;
            }
            onPositionChanged: function(mouse) {
                mouse.accepted = false;
            }
        }
    }
}
