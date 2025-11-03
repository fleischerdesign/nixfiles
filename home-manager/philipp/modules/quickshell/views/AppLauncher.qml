

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

    // --- Data Models ---

    // 1. A clean, JS-friendly copy of all applications.
    // This is populated once at startup by the Repeater below.
    ListModel {
        id: allAppsModel
    }

    // 2. The model that is actually displayed by the GridView.
    // This is the target for our filtering logic.
    ListModel {
        id: filteredAppsModel
    }

    // 3. An invisible Repeater that bridges the C++ model to our clean ListModel.
    Repeater {
        model: DesktopEntries.applications
        delegate: Item {
            required property var modelData
            Component.onCompleted: {
                var keywordString = ""
                if (modelData.keywords && typeof modelData.keywords.length !== 'undefined') {
                    for (var i = 0; i < modelData.keywords.length; i++) {
                        keywordString += modelData.keywords[i] + " "
                    }
                }

                allAppsModel.append({
                    "name": modelData.name,
                    "icon": modelData.icon,
                    "genericName": modelData.genericName,
                    "keywords": keywordString, // Store the pre-joined string
                    "entryObject": modelData // Store original object to call execute()
                })
            }
        }
    }

    // --- Behavior ---

    Component.onCompleted: {
        // Use a short timer to ensure the Repeater has finished its one-time population.
        var timer = Qt.createQmlObject("import QtQuick; Timer {interval: 50; running: true; onTriggered: { appLauncherModal.updateFilter() } }", appLauncherModal);
    }

    visible: false

    onVisibleChanged: {
        if (visible) {
            searchInput.text = "" // Clear search on open
            updateFilter()
            searchInput.forceActiveFocus()
        }
    }

    onBackgroundClicked: {
        visible = false
    }

    // --- Functions & Signals ---

    signal appLaunched(string appName)

    function toggle() {
        visible = !visible;
    }

    function updateFilter() {
        filteredAppsModel.clear()
        const searchText = searchInput.text.toLowerCase()

        for (var i = 0; i < allAppsModel.count; i++) {
            const entry = allAppsModel.get(i)

            if (searchText === "") {
                filteredAppsModel.append(entry)
                continue
            }

            // Search in name, generic name, and keywords
            const name = entry.name ? entry.name.toLowerCase() : ""
            const generic = entry.genericName ? entry.genericName.toLowerCase() : ""
            const keywords = entry.keywords ? entry.keywords.toLowerCase() : "" // entry.keywords is now a string
            const searchableString = name + " " + generic + " " + keywords

            if (searchableString.includes(searchText)) {
                filteredAppsModel.append(entry)
            }
        }
    }

    // --- Visual Content Definition ---

    contentItem: launcherContent

    // --- Visual Content Definition ---

    Rectangle {
        id: launcherContent

        width: 510
        height: 600
        radius: 15
        color: ColorService.palette.m3SurfaceContainerHigh
        clip: true

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
                    background: null
                    color: ColorService.palette.m3OnSurface
                    onTextChanged: appLauncherModal.updateFilter()
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
                model: filteredAppsModel // Bind to the clean, filtered model

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

                delegate: Item {
                    width: appGrid.cellWidth
                    height: appGrid.cellHeight

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        IconImage {
                            Layout.alignment: Qt.AlignHCenter
                            implicitSize: 64
                            source: "image://icon/" + model.icon
                            mipmap: true
                            asynchronous: true
                        }

                        Text {
                            Layout.fillWidth: true
                            text: model.name
                            color: ColorService.palette.m3OnSurface
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            model.entryObject.execute()
                            appLauncherModal.visible = false
                        }
                    }
                }
            }
        }
    }
}
