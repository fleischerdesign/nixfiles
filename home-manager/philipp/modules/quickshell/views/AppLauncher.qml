

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.components
import Quickshell
import Quickshell.Widgets

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

        width: 510
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
            anchors.margins: 15
            spacing: 15

            // 1. Search Bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
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
                clip: true
                cellWidth: 120
                cellHeight: 120

                // Explicitly remove any potential top spacing
                header: null

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 8
                    background: Rectangle { color: "transparent" }
                    contentItem: Rectangle {
                        implicitWidth: 8
                        radius: 4
                        color: ColorService.palette.m3Outline
                        opacity: 0.5
                    }
                }

                model: DesktopEntries.applications

                delegate: Item {
                    width: appGrid.cellWidth
                    height: appGrid.cellHeight

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        IconImage {
                            Layout.alignment: Qt.AlignHCenter
                            implicitSize: 64
                            source: "image://icon/" + modelData.icon
                            mipmap: true
                            asynchronous: true
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            color: ColorService.palette.m3OnSurface
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            modelData.execute()
                            appLauncherModal.visible = false
                        }
                    }
                }
            }
        }
    }
}
