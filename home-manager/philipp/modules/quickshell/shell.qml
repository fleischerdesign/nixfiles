import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

PanelWindow {
    id: sidebarWindow
    property bool isOpen: true
    
    anchors {
        left: true
        top: true
        bottom: true
    }
    
    implicitWidth: isOpen ? (55 + 25) : 0
    exclusiveZone: isOpen ? 55 : 0
    color: "transparent"
    
    Behavior on implicitWidth {
        NumberAnimation {
            duration: 250
            easing.type: Easing.InOutQuad
        }
    }
    
    Behavior on exclusiveZone {
        NumberAnimation {
            duration: 250
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
    
    // MouseArea für Hover
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: sidebarWindow.isOpen = true
        onExited: sidebarWindow.isOpen = false
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

        // Batterie-Status mit Icon
        Text {
            id: batteryText
            color: "white"
            font.family: "Material Symbols Rounded"
            font.pixelSize: 20
            Layout.alignment: Qt.AlignHCenter
            text: "battery_full"

            function updateBatteryIcon() {
                if (UPower.displayDevice && UPower.displayDevice.ready) {
                    const percent = UPower.displayDevice.percentage > 100 ? Math.round(UPower.displayDevice.percentage) : Math.round(UPower.displayDevice.percentage * 100)
                    const charging = UPower.displayDevice.state === 1
                    
                    if (charging) {
                        batteryText.text = "battery_charging_full"
                    } else if (percent > 75) {
                        batteryText.text = "battery_full"
                    } else if (percent > 50) {
                        batteryText.text = "battery_6_bar"
                    } else if (percent > 25) {
                        batteryText.text = "battery_4_bar"
                    } else {
                        batteryText.text = "battery_2_bar"
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
