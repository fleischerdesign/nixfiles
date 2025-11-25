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
                        height: modelData.bonded ? 52 : 0
                        visible: modelData.bonded

                        HoverHandler {
                            id: itemHoverHandler
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            radius: 8

                            M3StateLayer {
                                isHovered: itemHoverHandler.hovered && !disconnectButton.hovered && !forgetButton.hovered
                                isPressed: delegateMouseArea.pressed
                                customStateColor: ColorService.palette.m3OnSurface
                            }
                        }

                        MouseArea {
                            id: delegateMouseArea
                            anchors.fill: parent
                            hoverEnabled: false
                            onClicked: {
                                if (!modelData.connected) {
                                    BluetoothService.connectToDevice(modelData)
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 8
                            spacing: 8
                            
                            Text { // The new icon
                                text: BluetoothIconMapping.getMaterialIcon(modelData.icon)
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 20
                                color: ColorService.palette.m3OnSurface
                                verticalAlignment: Text.AlignVCenter
                                width: 20 // Fixed width for consistent spacing
                            }

                            Text { // Device name
                                text: modelData.name
                                color: ColorService.palette.m3OnSurface
                                font.pixelSize: 14
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            BusyIndicator {
                                running: modelData.state === BluetoothService.stateConnecting
                                visible: running
                                width: 20
                                height: 20
                                Layout.alignment: Qt.AlignVCenter
                            }

                            // Disconnect Button
                            M3Button {
                                id: disconnectButton
                                visible: modelData.connected && itemHoverHandler.hovered
                                style: M3Button.Style.Text
                                implicitWidth: 40
                                implicitHeight: 40
                                radius: 20
                                Layout.alignment: Qt.AlignVCenter
                                onClicked: {
                                    BluetoothService.disconnectFromDevice(modelData)
                                }
                                Text {
                                    text: "link_off"
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 20
                                    color: disconnectButton.autoContentColor
                                    anchors.centerIn: parent
                                }
                            }

                            // Forget Button
                            M3Button {
                                id: forgetButton
                                style: M3Button.Style.Text
                                enabled: true
                                visible: itemHoverHandler.hovered
                                implicitWidth: 40
                                implicitHeight: 40
                                radius: 20
                                Layout.alignment: Qt.AlignVCenter
                                onClicked: {
                                    BluetoothService.forgetDevice(modelData)
                                }
                                Text {
                                    text: "delete"
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 20
                                    color: forgetButton.autoContentColor
                                    anchors.centerIn: parent
                                }

                                // Eat clicks when disabled
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !forgetButton.enabled
                                    onClicked: (mouse) => { mouse.accepted = true; }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}




