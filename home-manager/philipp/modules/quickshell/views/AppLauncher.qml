

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.components
import Quickshell
import Quickshell.Widgets
import qs.core

// AppLauncher.qml
// A self-contained Modal component for the application launcher.

Modal {
    id: appLauncherModal

    // --- Data Models ---

    // 1. A clean, JS-friendly copy of all applications.
    // This is populated once at startup by the Repeater below.
    Timer {
        id: filterDebounceTimer
        interval: 10
        onTriggered: appLauncherModal.updateFilter()
    }

    ListModel {
        id: allAppsModel
        onCountChanged: {
            // Debounce the filter update. This is more robust than a fixed timer.
            // It waits until the repeater has stopped adding items for 10ms.
            filterDebounceTimer.restart()
        }
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

    visible: false

    Component.onCompleted: {
        // Initialize visibility from StateManager
        visible = StateManager.appLauncherOpened
    }

    Connections {
        target: StateManager
        function onAppLauncherOpenedChanged() {
            visible = StateManager.appLauncherOpened
            if (visible) {
                searchInput.text = "" // Clear search on open
                updateFilter()
                searchInput.forceActiveFocus()
            }
        }
    }

    onBackgroundClicked: {
        StateManager.appLauncherOpened = false
    }

    // --- Functions & Signals ---

    signal appLaunched(string appName)

    function toggle() {
        StateManager.appLauncherOpened = !StateManager.appLauncherOpened
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
        layer.enabled: true

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
                    placeholderTextColor: ColorService.palette.m3OnSurfaceVariant
                    background: null
                    color: ColorService.palette.m3OnSurface
                    onTextChanged: appLauncherModal.updateFilter()

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (appListView.currentIndex >= 0) {
                                filteredAppsModel.get(appListView.currentIndex).entryObject.execute()
                                StateManager.appLauncherOpened = false
                            }
                            event.accepted = true
                        }
                        if (event.key === Qt.Key_Down) {
                            appListView.forceActiveFocus()
                            appListView.currentIndex = 0
                            event.accepted = true
                        }
                        if (event.key === Qt.Key_Escape) {
                            StateManager.appLauncherOpened = false
                            event.accepted = true
                        }
                    }
                }
            }

            // 2. App Grid
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                color: "transparent"

                ListView {
                    id: appListView
                    focus: true // Allow the list to receive keyboard focus
                    anchors.fill: parent
                    spacing: 4

                    model: filteredAppsModel // Bind to the clean, filtered model

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (currentIndex >= 0) {
                                model.get(currentIndex).entryObject.execute()
                                StateManager.appLauncherOpened = false
                            }
                            event.accepted = true
                        }
                        if (event.key === Qt.Key_Escape) {
                            StateManager.appLauncherOpened = false
                            event.accepted = true
                        }
                    }

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

                    delegate: Rectangle {
                        id: delegateRoot
                        width: appListView.width
                        height: 55
                        radius: 8
                        color: "transparent" // Visual feedback is handled by the state layer
                        clip: true

                        property bool isCurrent: ListView.isCurrentItem

                        // --- Content (on top) ---
                        Item {
                            anchors.fill: parent
                            z: 2

                            IconImage {
                                id: icon
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 32
                                source: "image://icon/" + model.icon
                                mipmap: true
                                asynchronous: true
                            }

                            ColumnLayout {
                                anchors.left: icon.right
                                anchors.leftMargin: 15
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    text: model.name
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                    color: ColorService.palette.m3OnSurface
                                }
                                Text {
                                    text: model.genericName
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                    color: ColorService.palette.m3OnSurfaceVariant
                                }
                            }
                        }

                        // --- Input Handlers (non-visual) ---
                        HoverHandler { id: hoverHandler }

                        TapHandler {
                            id: tapHandler
                            onTapped: {
                                model.entryObject.execute()
                                StateManager.appLauncherOpened = false
                            }
                        }

                        // --- Feedback Layer (in the back) ---
                        M3StateLayer {
                            anchors.fill: parent
                            z: 1
                            isHovered: hoverHandler.hovered
                            isPressed: tapHandler.pressed || delegateRoot.isCurrent
                            colorRole: M3StateLayer.ColorRole.Surface
                        }
                    }
                }

                // Fade out at the top
                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 15
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: ColorService.palette.m3SurfaceContainerHigh }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    opacity: appListView.contentY > 0 ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                }

                // Fade out at the bottom
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 15
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: ColorService.palette.m3SurfaceContainerHigh }
                    }
                    opacity: appListView.contentY < (appListView.contentHeight - appListView.height) ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                }
            }
        }
    }
}
