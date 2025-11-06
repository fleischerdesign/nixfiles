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
// This view is now a "dumb" component. All logic is handled by the
// SearchService and its providers.

Modal {
    id: appLauncherModal

    // Instantiate the providers for the SearchService. They will register themselves.
    AppSearchProvider {}
    CalculatorProvider {}
    WebSearchProvider {}
    FileSearchProvider {}
    SystemActionProvider {}
    WeatherProvider {}

    // --- Behavior ---

    property bool shouldBeVisible: false

    visible: false

    onBackgroundClicked: {
        StateManager.appLauncherOpened = false
    }

    Connections {
        target: StateManager
        function onAppLauncherOpenedChanged() {
            shouldBeVisible = StateManager.appLauncherOpened
            if (shouldBeVisible) {
                // Clear search on open. This will trigger the service
                // to query providers for default results.
                SearchService.searchText = ""
                searchInput.forceActiveFocus()
            }
        }
    }

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            visible = true
        } else {
            // Delay hiding the modal to allow the slide-out animation to finish
            var timer = Qt.createQmlObject("import QtQuick; Timer {interval: 200; onTriggered: { appLauncherModal.visible = false; } }", appLauncherModal);
            timer.start();
        }
    }

    // --- Functions & Signals ---

    signal appLaunched(string appName)

    function toggle() {
        StateManager.appLauncherOpened = !StateManager.appLauncherOpened
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
    
            Component.onCompleted: {
                // Set initial position off-screen to the left without animation
                x = -width
            }
    
            // Position using x for animation
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 75 // 65 (bar height) + 10 (spacing)
            anchors.leftMargin: 10 // Keep the left margin for the visible state
            x: shouldBeVisible
                ? 10 // Visible: 10px from the left edge (parent.left + leftMargin)
                : -width // Hidden: completely off-screen to the left
    
            // Animate the x property
            Behavior on x {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.InOutQuad
                }
            }
            layer.enabled: true
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 15

            Timer {
                id: animationEnableTimer
                interval: 50
                onTriggered: appListView.animationsEnabled = true
            }

            Connections {
                target: SearchService
                function onSearchInProgressChanged() {
                    if (SearchService.searchInProgress) {
                        appListView.animationsEnabled = false
                    } else {
                        animationEnableTimer.restart()
                    }
                }
            }

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
                    
                    // Bind the text to the central search service
                    text: SearchService.searchText
                    onTextChanged: SearchService.searchText = text

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (appListView.currentIndex >= 0) {
                                SearchService.results.get(appListView.currentIndex).entryObject.execute()
                                StateManager.appLauncherOpened = false
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down) {
                            if (appListView.currentIndex < appListView.count - 1) {
                                appListView.currentIndex++
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            if (appListView.currentIndex > 0) {
                                appListView.currentIndex--
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
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
                    property bool animationsEnabled: true
                    focus: true // Allow the list to receive keyboard focus
                    anchors.fill: parent
                    spacing: 4

                    // Bind the model to the central search service results
                    model: SearchService.results

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (currentIndex >= 0) {
                                model.get(currentIndex).entryObject.execute()
                                StateManager.appLauncherOpened = false
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            StateManager.appLauncherOpened = false
                            event.accepted = true
                        } else if (event.key === Qt.Key_Backspace && searchInput.text.length > 0) {
                            searchInput.forceActiveFocus()
                            searchInput.backspace()
                            event.accepted = true
                        } else if (event.text.length > 0) {
                            searchInput.forceActiveFocus()
                            searchInput.insert(searchInput.cursorPosition, event.text)
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

                            // Data-driven icon display
                            IconImage {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 32
                                mipmap: true
                                asynchronous: true
                                visible: model.icon.type === "image"
                                source: visible ? ("image://icon/" + model.icon.source) : ""
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32
                                font.pixelSize: 32
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: ColorService.palette.m3OnSurface
                                visible: model.icon.type === "fontIcon"
                                font.family: visible ? model.icon.fontFamily : ""
                                text: visible ? model.icon.source : ""
                            }

                            ColumnLayout {
                                anchors.left: parent.left
                                anchors.leftMargin: 10 + 32 + 15 // left margin + icon width + spacing
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
                            animationsEnabled: appListView.animationsEnabled
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
                    z: 3
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
                    z: 3
                }
            }
        }
    }
}