import QtQuick
import "./"

// Handles actions of type "launchApp"
BaseAction {
    type: "launchApp"

    function execute(action) {
        if (action.appEntry && typeof action.appEntry.execute === 'function') {
            action.appEntry.execute();
        } else {
            console.warn(`[ActionHandler] launchApp action missing executable appEntry: ${JSON.stringify(action)}`);
        }
    }
}
