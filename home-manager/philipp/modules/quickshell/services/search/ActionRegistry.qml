pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel 2.15
import "./actions"

// This singleton discovers and manages all available action handlers.
Item {
    id: root

    // --- State ---
    property var actionHandlers: ({})
    property bool handlersReady: false
    property var _pendingActions: [] // Action queue

    // --- Dynamic Action Handler Discovery ---

    // 1. Find all action QML files
    FolderListModel {
        id: actionFilesModel
        folder: Qt.resolvedUrl("actions/")
        nameFilters: ["*Action.qml", "!BaseAction.qml"]
        showDirs: false
    }

    // 2. For each file, create an instance and register it.
    Instantiator {
        model: actionFilesModel

        delegate: Item { // Use a simple Item as a container for the logic
            Component.onCompleted: {
                const component = Qt.createComponent(filePath);
                if (component.status === Component.Ready) {
                    const handler = component.createObject(root);
                    if (handler && typeof handler.type !== 'undefined') {
                        if (handler.type === "") { // BaseAction has an empty type
                            handler.destroy();
                            return;
                        }
                        console.log(`[ActionRegistry] Registering action handler for type: ${handler.type}`);
                        root.actionHandlers[handler.type] = handler;

                        // Check if all handlers are now registered
                        const expectedCount = actionFilesModel.count - 1; // -1 for BaseAction
                        if (Object.keys(root.actionHandlers).length === expectedCount) {
                            console.log("[ActionRegistry] All action handlers are ready.");
                            root.handlersReady = true;
                        }
                    }
                } else {
                    console.error(`[ActionRegistry] Error loading action handler: ${component.errorString()}`);
                }
            }
        }
    }

    // --- Lifecycle ---
    onHandlersReadyChanged: {
        if (handlersReady) {
            // Process any actions that were queued before we were ready
            if (_pendingActions.length > 0) {
                console.log(`[ActionRegistry] Processing ${_pendingActions.length} pending actions...`);
                for (var i = 0; i < _pendingActions.length; i++) {
                    execute(_pendingActions[i]);
                }
                _pendingActions = []; // Clear the queue
            }
        }
    }

    // --- Public API ---
    function execute(action) {
        if (!action || !action.type) {
            console.warn(`[ActionRegistry] Invalid action object received.`);
            return;
        }

        // If not ready, queue the action for later
        if (!handlersReady) {
            console.log(`[ActionRegistry] Not ready, queueing action of type: ${action.type}`);
            _pendingActions.push(action);
            return;
        }

        const handler = actionHandlers[action.type];
        if (handler) {
            handler.execute(action);
        } else {
            console.warn(`[ActionRegistry] No handler found for action type: ${action.type}`);
        }
    }
}
