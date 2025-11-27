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
        for (const prop in this) {
            const handler = this[prop];
            if (handler && handler.objectName === "actionHandler") {
                actionHandlers[handler.type] = handler;
            }
        }
        console.log(`[ActionRegistry] All ${Object.keys(actionHandlers).length} handlers registered via introspection.`);
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