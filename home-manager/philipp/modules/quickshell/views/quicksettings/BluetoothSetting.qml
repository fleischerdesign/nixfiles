import qs.components
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

QuickSettingButton {
    id: bluetoothButton

    icon: "bluetooth"
    label: "Bluetooth"
    toggled: BluetoothService.enabled
    
    // We handle this in the MouseArea below
    onClicked: {}

    MouseArea {
        id: buttonMouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                // To see non-bonded devices during discovery, a scan can be initiated.
                // BluetoothService.startDiscovery()
                deviceMenu.open()
            } else {
                BluetoothService.togglePower()
            }
        }
    }

    Popup {
        id: deviceMenu
        width: 250
        padding: 8
        // Dynamically bind height to visibility to force recalculation when opened
        height: visible ? Math.min(300, flickableContent.contentHeight + padding * 2) : 0

        // Position it nicely above the button
        x: parent.x - (width - parent.width) / 2
        y: parent.y - height - 10
        
        background: Rectangle {
            id: backgroundRect
            radius: 15 // Match QuickSettings container
            color: ColorService.palette.m3SurfaceContainerHighest // Use a more elevated color

            RectangularShadow {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.15)
                blur: 12
                radius: backgroundRect.radius
                z: -1
            }
        }

        Flickable {
            id: flickableContent
            anchors.fill: parent
            contentHeight: deviceList.height
            clip: true

            Column {
                id: deviceList
                spacing: 4
                width: parent.width

                Repeater {
                    model: BluetoothService.knownDevices

                    delegate: Item {
                        id: delegateRoot
                        width: parent.width
                        height: modelData.bonded ? 52 : 0 // Increased height for better spacing
                        visible: modelData.bonded

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            radius: 8

                            M3StateLayer {
                                isHovered: delegateMouseArea.containsMouse
                                isPressed: delegateMouseArea.pressed
                                customStateColor: ColorService.palette.m3OnSurface
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16

                            Text {
                                text: modelData.name
                                color: ColorService.palette.m3OnSurface
                                font.pixelSize: 14
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            
                            Text {
                                text: modelData.connected ? "Connected" : ""
                                color: ColorService.palette.m3Primary
                                font.pixelSize: 12
                                opacity: 0.8
                            }
                        }

                        MouseArea {
                            id: delegateMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (modelData.connected) {
                                    BluetoothService.disconnectFromDevice(modelData)
                                } else {
                                    BluetoothService.connectToDevice(modelData)
                                }
                                deviceMenu.close()
                            }
                        }
                    }
                }
            }
        }
    }
}




