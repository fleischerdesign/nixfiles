// services/search/ActionRegistry.qml
pragma Singleton
import QtQuick
import Quickshell
import qs.services.search.actions as Actions

Singleton {
    id: root

    // Statically declare each handler as a property. This is a clean,
    // declarative, and syntactically valid way to instantiate them.
    property var commandAction: Actions.CommandAction {}
    property var copyAction: Actions.CopyAction {}
    property var launchAppAction: Actions.LaunchAppAction {}
    property var noAction: Actions.NoAction {}
    property var urlAction: Actions.UrlAction {}

    // This map provides fast O(1) lookup for the execute function.
    readonly property var actionHandlers: ({})

    Component.onCompleted: {
        // Populate the map from the statically declared handlers.
        actionHandlers[commandAction.type] = commandAction;
        actionHandlers[copyAction.type] = copyAction;
        actionHandlers[launchAppAction.type] = launchAppAction;
        actionHandlers[noAction.type] = noAction;
        actionHandlers[urlAction.type] = urlAction;
        
        console.log(`[ActionRegistry] All ${Object.keys(actionHandlers).length} handlers registered.`)
    }

    // Public API
    function execute(action) {
        if (!action || !action.type) {
            console.warn(`[ActionRegistry] Invalid action object received.`);
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