import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import qs.services
import qs.components
import Quickshell
import Quickshell.Widgets
import qs.core
import qs.services.search as Search

// AppLauncher.qml - Frame Shell Edition
Modal {
    id: appLauncherModal

    // --- Behavior ---
    property bool shouldBeVisible: StateManager.activePanel === "launcher"
    visible: false

    onBackgroundClicked: StateManager.activePanel = ""

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            visible = true
            Search.SearchService.searchText = ""
            searchInput.forceActiveFocus()
        } else {
            Search.SearchService.cancelSearch()
            hideDelayTimer.start()
        }
    }

    Timer {
        id: hideDelayTimer
        interval: 200
        onTriggered: appLauncherModal.visible = false
    }

    signal appLaunched(string appName)

    function toggle() {
        StateManager.togglePanel("launcher")
    }

    // --- Visual Content ---
    contentItem: launcherContent

    Rectangle {
        id: launcherContent
        
        width: 420
        height: 550
        radius: FrameTheme.radius
        color: FrameTheme.popover
        border.width: FrameTheme.borderWidth
        border.color: FrameTheme.border
        
        // Position: Bottom Left, aligned with start button
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 70
        anchors.left: parent.left
        anchors.leftMargin: 20
        
        // Animation
        opacity: shouldBeVisible ? 1 : 0
        transform: Translate {
            y: shouldBeVisible ? 0 : 10
            Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
        }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Shadow
        RectangularShadow {
            width: parent.width; height: parent.height
            y: 4; z: -1
            color: Qt.rgba(0, 0, 0, 0.3); blur: 20; radius: parent.radius
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            // 1. Search Input
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: FrameTheme.radius
                color: FrameTheme.card
                border.width: 1
                border.color: searchInput.activeFocus ? FrameTheme.ring : FrameTheme.border
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    
                    Text {
                        text: "search"
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 18
                        color: FrameTheme.mutedForeground
                    }

                    TextField {
                        id: searchInput
                        Layout.fillWidth: true
                        font.family: FrameTheme.fontFamily
                        font.pixelSize: 14
                        placeholderText: "Search apps..."
                        placeholderTextColor: FrameTheme.mutedForeground
                        background: null
                        color: FrameTheme.foreground
                        selectByMouse: true
                        
                        text: Search.SearchService.searchText
                        onTextChanged: Search.SearchService.searchText = text

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (appListView.currentIndex >= 0) {
                                    const item = Search.SearchService.results.get(appListView.currentIndex)
                                    if (item.actionObject) Search.ActionRegistry.execute(item.actionObject)
                                    else if (item.entryObject) Quickshell.execDetached({ command: item.entryObject.command, workingDirectory: item.entryObject.workingDirectory })
                                    StateManager.activePanel = ""
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down) {
                                appListView.incrementCurrentIndex()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up) {
                                appListView.decrementCurrentIndex()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape) {
                                StateManager.activePanel = ""
                                event.accepted = true
                            }
                        }
                    }
                }
            }
            
            // Separator
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: FrameTheme.border
            }

            // 2. App List
            ListView {
                id: appListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                
                model: Search.SearchService.results
                
                ScrollBar.vertical: ScrollBar {
                    width: 4
                    active: appListView.moving || appListView.flickableItem.contentHeight > appListView.height
                    background: Rectangle { color: "transparent" }
                    contentItem: Rectangle {
                        radius: 2
                        color: FrameTheme.mutedForeground
                        opacity: 0.5
                    }
                }

                delegate: Rectangle {
                    id: delegateRoot
                    width: appListView.width
                    height: 48
                    radius: FrameTheme.radius
                    color: {
                        if (ListView.isCurrentItem) return FrameTheme.primary;
                        if (hoverHandler.hovered) return FrameTheme.secondary;
                        return "transparent";
                    }

                    // Content
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 10
                        
                        // Icon
                        Item {
                            implicitWidth: 24
                            implicitHeight: 24
                            
                            IconImage {
                                anchors.fill: parent
                                mipmap: true
                                asynchronous: true
                                visible: model.icon.type === "image"
                                source: visible ? ("image://icon/" + model.icon.source) : ""
                            }
                            Text {
                                anchors.centerIn: parent
                                font.pixelSize: 20
                                font.family: visible ? model.icon.fontFamily : ""
                                text: visible ? model.icon.source : ""
                                color: delegateRoot.ListView.isCurrentItem ? FrameTheme.primaryForeground : FrameTheme.foreground
                                visible: model.icon.type === "fontIcon"
                            }
                        }
                        
                        // Text
                        Column {
                            Layout.fillWidth: true
                            Text {
                                text: model.name
                                color: delegateRoot.ListView.isCurrentItem ? FrameTheme.primaryForeground : FrameTheme.foreground
                                font.family: FrameTheme.fontFamily
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }
                        
                        // Shortcut Hint (optional)
                        Text {
                            text: "↵"
                            visible: delegateRoot.ListView.isCurrentItem
                            color: FrameTheme.primaryForeground
                            opacity: 0.7
                            font.pixelSize: 12
                        }
                    }

                    HoverHandler { id: hoverHandler }
                    TapHandler {
                        onTapped: {
                            if (model.entryObject) Quickshell.execDetached({ command: model.entryObject.command, workingDirectory: model.entryObject.workingDirectory })
                            else if (model.actionObject) Search.ActionRegistry.execute(model.actionObject)
                            StateManager.activePanel = ""
                        }
                    }
                }
            }
            
            // Footer (Profile / Power)
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: FrameTheme.border
            }
            
            RowLayout {
                Layout.fillWidth: true
                
                FrameButton {
                    variant: FrameButton.Variant.Ghost
                    text: "Philipp"
                    icon: "person"
                }
                
                Item { Layout.fillWidth: true }
                
                FrameButton {
                    variant: FrameButton.Variant.Ghost
                    icon: "power_settings_new"
                    onClicked: {
                        Quickshell.execDetached(["systemctl", "poweroff"])
                    }
                }
            }
        }
    }
}
