

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.components

// AppLauncher.qml
// A self-contained Modal component for the application launcher.

Modal {
    id: appLauncherModal

    // Point to the content item
    contentItem: launcherContent

    // --- Behavior ---
    visible: false

    onVisibleChanged: {
        if (visible) {
            searchInput.forceActiveFocus();
        }
    }

    onBackgroundClicked: {
        visible = false
    }

    // --- Signals & API ---
    signal appLaunched(string appName)

    function toggle() {
        visible = !visible;
    }

    // --- Visual Content Definition ---
    Rectangle {
        id: launcherContent

        width: 500
        height: 600
        radius: 15
        color: ColorService.palette.m3SurfaceContainerHigh
        clip: true

        // Position the launcher content above the bottom bar
        anchors {
            left: parent.left
            bottom: parent.bottom
            leftMargin: 10
            bottomMargin: 75 // 65 (bar height) + 10 (spacing)
        }

        ColumnLayout {
            anchors.fill: parent

            // 1. Search Bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                Layout.margins: 20
                radius: 25
                color: ColorService.palette.m3SurfaceContainerLowest
                
                TextField {
                    id: searchInput
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    font.pixelSize: 18
                    placeholderText: "Anwendungen suchen..."
                    background: null // Remove the default TextField background
                    color: ColorService.palette.m3OnSurface

                    // TODO: Implement search logic to filter the GridView model
                }
            }

            // 2. App Grid
            GridView {
                id: appGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 10

                cellWidth: 120
                cellHeight: 120

                model: ListModel {
                    ListElement { appName: "Firefox"; appIcon: "web-browser" }
                    ListElement { appName: "Terminal"; appIcon: "utilities-terminal" }
                    ListElement { appName: "Dateien"; appIcon: "system-file-manager" }
                    ListElement { appName: "Editor"; appIcon: "accessories-text-editor" }
                    ListElement { appName: "Einstellungen"; appIcon: "system-settings" }
                    ListElement { appName: "Rechner"; appIcon: "accessories-calculator" }
                }

                delegate: ColumnLayout {
                    width: appGrid.cellWidth
                    height: appGrid.cellHeight
                    spacing: 8

                    MouseArea {
                        anchors.fill: parent
                        onClicked: appLauncherModal.appLaunched(appName)
                    }

                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        width: 64
                        height: 64
                        source: "qrc:/icons/" + appIcon + ".svg" // Placeholder path
                    }

                    Text {
                        Layout.fillWidth: true
                        text: appName
                        color: ColorService.palette.m3OnSurface
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
