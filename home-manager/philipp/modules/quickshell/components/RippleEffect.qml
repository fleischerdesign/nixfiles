import QtQuick

Item {
    id: root
    anchors.fill: parent
    clip: true

    property color rippleColor: "white"
    property real parentRadius: 0

    signal clicked

    Canvas {
        id: sparkleCanvas
        anchors.fill: parent
        z: 1 // Ensure it's above the background but below content
        property real rippleProgress: 0
        property point rippleCenter: Qt.point(0, 0)

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
            const r = root.parentRadius;
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

            const maxRadius = Math.max(parent.width, parent.height) * 2.5;
            const currentRadius = rippleProgress * maxRadius;

            const baseOpacity = (1 - rippleProgress) * 0.25;
            if (baseOpacity > 0) {
                const gradient = ctx.createRadialGradient(rippleCenter.x, rippleCenter.y, currentRadius * 0.3, rippleCenter.x, rippleCenter.y, currentRadius);
                const rippleStartColor = Qt.rgba(root.rippleColor.r, root.rippleColor.g, root.rippleColor.b, baseOpacity);

                gradient.addColorStop(0, rippleStartColor.toString(Qt.RGBA));
                gradient.addColorStop(1, "rgba(0, 0, 0, 0)");
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
        onPressed: function (mouse) {
            sparkleCanvas.triggerRipple(mouse.x, mouse.y);
            mouse.accepted = true;
        }
        onClicked: {
            root.clicked();
        }
        onPositionChanged: function (mouse) {
            mouse.accepted = false;
        }
    }
}
