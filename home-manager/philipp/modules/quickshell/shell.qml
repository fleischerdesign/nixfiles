import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

PanelWindow {
    id: bottomBarWindow
    property bool isOpen: false

    // Decoupled panelHeight from isOpen to fix animation conflicts
    property int panelHeight: 10
    implicitHeight: panelHeight

    anchors {
        left: true
        right: true
        bottom: true
    }

    exclusiveZone: 0 // User preference
    color: "transparent"

    // A single clipping rectangle containing the content
    Rectangle {
        id: clippingRect
        anchors.fill: parent
        clip: true
        color: "transparent"

        Item {
            id: contentWrapper
            height: 65
            width: parent.width

            y: isOpen ? 0 : height

            Behavior on y {
                NumberAnimation {
                    id: slideAnimation
                    duration: 200
                    easing.type: Easing.InOutQuad
                    // After the slide-out animation finishes, shrink the window.
                    onRunningChanged: {
                        if (!running && !isOpen) {
                            bottomBarWindow.panelHeight = 10
                        }
                    }
                }
            }

            // Shadow is now inside the wrapper and will be animated with it.
            Rectangle {
                id: shadow
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00000000" } // Top (transparent)
                    GradientStop { position: 1.0; color: "#ff000000" } // Bottom (semi-transparent black)
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

                // --- Segments ---
                Rectangle {
                    width: 55
                    height: 55
                    radius: 15
                    color: "#333333"
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        text: "home"
                        color: "white"
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 24
                        anchors.centerIn: parent
                    }
                }

                Rectangle {
                    width: 55
                    height: 55
                    radius: 15
                    color: "#333333"
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        text: "apps"
                        color: "white"
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 24
                        anchors.centerIn: parent
                    }
                }

                // --- Spacer in the middle ---
                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    width: 55
                    height: 55
                    radius: 15
                    color: "#333333"
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: clockText
                        color: "white"
			font.pixelSize: 12
			font.weight: 500
                        horizontalAlignment: Text.AlignHCenter
                        anchors.centerIn: parent

                        Timer {
                            interval: 1000
                            running: true
                            repeat: true
                            onTriggered: {
                                const now = new Date()
                                const hours = String(now.getHours()).padStart(2, '0')
                                const minutes = String(now.getMinutes()).padStart(2, '0')
                                clockText.text = hours + ":" + minutes
                            }
                        }

                        Component.onCompleted: {
                            const now = new Date()
                            const hours = String(now.getHours()).padStart(2, '0')
                            const minutes = String(now.getMinutes()).padStart(2, '0')
                            text = hours + ":" + minutes
                        }
                    }
                }

                Rectangle {
                    width: 55
                    height: 55
                    radius: 15
                    color: "#333333"
                    Layout.alignment: Qt.AlignVCenter
		    visible: UPower.displayDevice ? UPower.displayDevice.type === 2 : false // 2 = UPowerDeviceType.BATTERY



                    Text {
                        id: batteryText
                        color: "white"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 20
                        anchors.centerIn: parent
                        text: "battery_android_full"

                        function updateBatteryIcon() {
                            if (UPower.displayDevice && UPower.displayDevice.ready) {
                                const percent = UPower.displayDevice.percentage > 100 ? Math.round(UPower.displayDevice.percentage) : Math.round(UPower.displayDevice.percentage * 100)
                                const charging = UPower.displayDevice.state === 1
                                
                                if (charging) {
                                    batteryText.text = "battery_android_bolt"
                                } else if (percent > 87) {
                                    batteryText.text = "battery_android_full"
                                } else if (percent > 75) {
                                    batteryText.text = "battery_android_6"
                                } else if (percent > 62) {
                                    batteryText.text = "battery_android_5"
                                } else if (percent > 50) {
                                    batteryText.text = "battery_android_4"
                                } else if (percent > 37) {
                                    batteryText.text = "battery_android_3"
                                } else if (percent > 25) {
                                    batteryText.text = "battery_android_2"
                                } else if (percent > 12.5) {
                                    batteryText.text = "battery_android_1"
                                } else {
                                    batteryText.text = "battery_android_0"
                                }
                            } else {
                                batteryText.text = "battery_unknown"
                            }
                        }

                        Component.onCompleted: updateBatteryIcon()

                        Connections {
                            target: UPower.displayDevice
                            function onPercentageChanged() { batteryText.updateBatteryIcon() }
                            function onStateChanged() { batteryText.updateBatteryIcon() }
                            function onReadyChanged() { batteryText.updateBatteryIcon() }
                        }
                    }
                }

                Rectangle {
                    width: 55
                    height: 55
                    radius: 15
                    color: "#333333"
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        text: "clarify"
                        color: "white"
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 24
                        anchors.centerIn: parent
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                // Expand window instantly, then trigger slide-in animation.
                bottomBarWindow.panelHeight = 65
                isOpen = true
            }
            onExited: {
                // Just trigger slide-out animation. Window shrinks when it's done.
                isOpen = false
            }
        }
    }
}
