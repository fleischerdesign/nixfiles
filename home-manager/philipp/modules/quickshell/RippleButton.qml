import QtQuick

// Reusable Button Component with Android-Style Ripple
Rectangle {
    id: button
    width: fixedWidth ? 55 : Math.max(55, contentItem.implicitWidth + 40)
    height: 55
    radius: 15
    color: "#000000"
    property bool fixedWidth: false
    default property alias content: contentItem.data
    clip: true
    
    Behavior on color {
        ColorAnimation {
            duration: 150
        }
    }
    
    Item {
        id: contentItem
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
        anchors.centerIn: parent
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
