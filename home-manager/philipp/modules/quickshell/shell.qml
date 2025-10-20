import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

PanelWindow {
    id: sidebarWindow
    property bool isOpen: false

    // Use a separate property for width to control it independently.
    property int panelWidth: isOpen ? (55 + 25) : 10
    implicitWidth: panelWidth

    anchors {
        left: true
        top: true
        bottom: true
    }

    exclusiveZone: isOpen ? 55 : 0
    color: "transparent"

    Behavior on exclusiveZone {
        NumberAnimation {
            duration: 250
            easing.type: Easing.InOutQuad
        }
    }

    Rectangle {
        id: clippingRect
        anchors.fill: parent
        color: "transparent"
        clip: true

        Item {
            id: contentWrapper
            width: 55 + 25
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            x: isOpen ? 0 : -width

            Behavior on x {
                NumberAnimation {
                    id: slideAnimation
                    duration: 250
                    easing.type: Easing.InOutQuad

                    // After the closing animation finishes, shrink the window.
                    onRunningChanged: {
                        if (!running && !sidebarWindow.isOpen) {
                            sidebarWindow.panelWidth = 10
                        }
                    }
                }
            }

            // Sidebar background
            Rectangle {
                id: sidebarBackground
                anchors {
                    fill: parent
                    rightMargin: 25
                }
                color: "#333333"
            }

            // Round decorators
            Item {
                id: roundDecorators
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    left: sidebarBackground.right
                    right: parent.right
                }
                width: 25

                RoundCorner {
                    id: topCorner
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    implicitSize: 25
                    color: "#333333"
                    corner: RoundCorner.CornerEnum.TopLeft
                }

                RoundCorner {
                    id: bottomCorner
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    implicitSize: 25
                    color: "#333333"
                    corner: RoundCorner.CornerEnum.BottomLeft
                }
            }

            // Sidebar content
            ColumnLayout {
                anchors {
                    fill: sidebarBackground
                    topMargin: 5
                    bottomMargin: 5
                    leftMargin: 5
                    rightMargin: 5
                }
                spacing: 10

                Text {
                    text: "home"
                    color: "white"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 24
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "apps"
                    color: "white"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 24
                    Layout.alignment: Qt.AlignHCenter
                }

                Item {
                    Layout.fillHeight: true
                }

                // Uhr
                Text {
                    id: clockText
                    color: "white"
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignHCenter

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

                Text {
                    id: batteryText
                    color: "white"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 20
                    Layout.alignment: Qt.AlignHCenter
                    text: "battery_android_full"
                    // Only show battery icon if a battery is present (e.g. on a laptop)
                    visible: UPower.displayDevice ? UPower.displayDevice.type === 2 : false // 2 = UPowerDeviceType.BATTERY

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

                Text {
                    text: "settings"
                    color: "white"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 24
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                // First, expand the window instantly.
                sidebarWindow.panelWidth = 55 + 25
                // Then, trigger the animation.
                sidebarWindow.isOpen = true
            }
            onExited: {
                // Just trigger the animation. The onRunningChanged handler
                // on the animation will take care of shrinking the window later.
                sidebarWindow.isOpen = false
            }
        }
    }
}
