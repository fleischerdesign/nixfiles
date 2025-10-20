import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

PanelWindow {
    id: bottomBarWindow

    VolumeOSD {}

    property bool isOpen: false
    property int panelHeight: 10
    implicitHeight: panelHeight

    anchors {
        left: true
        right: true
        bottom: true
    }

    exclusiveZone: 0
    color: "transparent"

    Item {
        id: clippingRect
        anchors.fill: parent
        
        // Invisible trigger area at the very bottom
        MouseArea {
            id: edgeTrigger
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 10
            hoverEnabled: true
            z: 0
            
            onEntered: {
                bottomBarWindow.panelHeight = 65
                isOpen = true
            }
            onExited: {
                if (!contentWrapper.barHovered) {
                    isOpen = false
                }
            }
        }

        // Clipping wrapper
        Rectangle {
            id: clipRect
            anchors.fill: parent
            clip: true
            color: "transparent"
            z: 1

            Item {
                id: contentWrapper
                height: 65
                width: parent.width

                property bool barHovered: false

                y: isOpen ? 0 : height

                Behavior on y {
                    NumberAnimation {
                        id: slideAnimation
                        duration: 200
                        easing.type: Easing.InOutQuad
                        onRunningChanged: {
                            if (!running && !isOpen) {
                                bottomBarWindow.panelHeight = 10
                            }
                        }
                    }
                }

                // HoverHandler für die gesamte Bar - blockiert keine Mouse Events!
                HoverHandler {
                    id: barHoverHandler
                    onHoveredChanged: {
                        contentWrapper.barHovered = hovered
                        if (!hovered) {
                            isOpen = false
                        }
                    }
                }

                Rectangle {
                    id: shadow
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#00000000" }
                        GradientStop { position: 1.0; color: "#ff000000" }
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

                    Rectangle {
                        width: 55
                        height: 55
                        radius: 15
                        color: "#000000"
                        Layout.alignment: Qt.AlignVCenter

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            text: "home"
                            color: "white"
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 24
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: {
                                parent.color = "#1A1A1A"
                            }
                            onExited: {
                                parent.color = "#000000"
                            }
                        }
                    }

                    Rectangle {
                        width: 55
                        height: 55
                        radius: 15
                        color: "#000000"
                        Layout.alignment: Qt.AlignVCenter

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            text: "apps"
                            color: "white"
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 24
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: {
                                parent.color = "#1A1A1A"
                            }
                            onExited: {
                                parent.color = "#000000"
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        width: 55
                        height: 55
                        radius: 15
                        color: "#000000"
                        Layout.alignment: Qt.AlignVCenter

                        Behavior on color { ColorAnimation { duration: 150 } }

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

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: {
                                parent.color = "#1A1A1A"
                            }
                            onExited: {
                                parent.color = "#000000"
                            }
                        }
                    }

                    Rectangle {
                        width: 55
                        height: 55
                        radius: 15
                        color: "#000000"
                        Layout.alignment: Qt.AlignVCenter
                        visible: UPower.displayDevice ? UPower.displayDevice.type === 2 : false

                        Behavior on color { ColorAnimation { duration: 150 } }

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

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: {
                                parent.color = "#1A1A1A"
                            }
                            onExited: {
                                parent.color = "#000000"
                            }
                        }
                    }

                    Rectangle {
                        width: 55
                        height: 55
                        radius: 15
                        color: "#000000"
                        Layout.alignment: Qt.AlignVCenter

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            text: "clarify"
                            color: "white"
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 24
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: {
                                parent.color = "#1A1A1A"
                            }
                            onExited: {
                                parent.color = "#000000"
                            }
                        }
                    }
                }
            }
        }
    }
}
