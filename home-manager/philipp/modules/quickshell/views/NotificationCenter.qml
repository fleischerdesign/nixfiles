import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.core
import QtQuick.Controls.Basic

Modal {
    id: notificationCenterModal

    property bool shouldBeVisible: false

    contentItem: contentRectangle
    visible: false
    onBackgroundClicked: {
        StateManager.notificationCenterOpened = false;
    }

    Connections {
        target: StateManager
        function onNotificationCenterOpenedChanged() {
            shouldBeVisible = StateManager.notificationCenterOpened;
        }
    }

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            visible = true;
            NotificationService.dismissAll();
        } else {
            var timer = Qt.createQmlObject("import QtQuick; Timer {interval: 200; onTriggered: { notificationCenterModal.visible = false; } }", notificationCenterModal);
            timer.start();
        }
    }

    Rectangle {
        id: contentRectangle
        width: 400

        Component.onCompleted: {
            x = screen.width;
        }

        anchors {
            top: parent.top
            bottom: parent.bottom
            bottomMargin: 65 + 10
            topMargin: 10
        }
        opacity: shouldBeVisible ? 1.0 : 0
        x: shouldBeVisible ? (parent.width - width - 10) : parent.width

        Behavior on x {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }

        // Performance-Boost with true: render as gpu texture
        layer.enabled: false

        radius: 15
        color: ColorService.palette.m3SurfaceContainer

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "Benachrichtigungen"
                    color: "white"
                    font.pixelSize: 18
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }

                M3Button {
                    style: M3Button.Style.Filled
                    colorRole: M3Button.ColorRole.Primary
                    onClicked: {
                        const notifications = NotificationService.server.trackedNotifications.values;
                        for (let i = notifications.length - 1; i >= 0; i--) {
                            notifications[i].dismiss();
                        }
                    }

                    Text {
                        text: "delete_sweep"
                        color: parent.autoContentColor
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 20
                    }
                }
            }

            ListView {
                id: notificationList
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                clip: true
                model: NotificationService.server.trackedNotifications

                delegate: NotificationCard {
                    width: notificationList.width
                    notification: modelData
                    onDismissRequested: modelData.dismiss()
                    isInNotificationCenter: true
                }

                Text {
                    anchors.centerIn: parent
                    visible: notificationList.count === 0
                    text: "Keine Benachrichtigungen"
                    color: "#888888"
                    font.pixelSize: 14
                }
            }

            Rectangle {
                id: quickSettingsContainer
                color: ColorService.palette.m3SurfaceContainerHigh
                width: parent.width
                radius: 15
                Layout.fillWidth: true
                Layout.preferredHeight: settingsLayout.implicitHeight + 30

                ColumnLayout {
                    id: settingsLayout
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 15

                    M3Slider {
                        Layout.fillWidth: true
                        icon: "brightness_6"
                        from: 0.0
                        to: 1.0
                        value: BrightnessService.currentBrightness
                        onValueChanged: {
                            BrightnessService.setBrightness(value)
                        }
                    }

                    M3Slider {
                        Layout.fillWidth: true
                        icon: AudioService.muted ? "volume_off" : "volume_up"
                        from: 0.0
                        to: 1.0
                        value: AudioService.volume
                        toggled: !AudioService.muted

                        onValueChanged: {
                            AudioService.setVolume(value)
                            if (AudioService.muted && value > 0) {
                                AudioService.toggleMute()
                            }
                        }
                        onIconClicked: {
                            AudioService.toggleMute()
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 10
                        rowSpacing: 10

                        QuickSettingButton {
                            icon: "wifi"
                            label: "WLAN"
                            toggled: NetworkService.wifiEnabled
                            onClicked: NetworkService.toggleWifi()
                        }

                        QuickSettingButton {
                            icon: "bluetooth"
                            label: "Bluetooth"
                            toggled: BluetoothService.enabled
                            onClicked: BluetoothService.togglePower()
                        }

                        QuickSettingButton {
                            icon: "night_sight_auto"
                            label: "Nachtlicht"
                            toggled: NightlightService.enabled
                            onClicked: NightlightService.toggle()
                        }

                        QuickSettingButton {
                            icon: StateManager.dndEnabled ? "notifications_off" : "notifications"
                            label: "Nicht stören"
                            toggled: StateManager.dndEnabled
                            onClicked: StateManager.dndEnabled = !StateManager.dndEnabled
                        }

                        QuickSettingButton {
                            icon: "lock"
                            label: "Sperren"
                            onClicked: sessionLocker.locked = true
                        }
                    }
                }
            }
        }
    }
}
