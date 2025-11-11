import QtQuick
import Quickshell
import "./"

// Handles actions of type "launchApp"
BaseAction {
    type: "launchApp"

    function execute(action) {
        if (action.appEntry) {
            Quickshell.execDetached({
                command: action.appEntry.command,
                workingDirectory: action.appEntry.workingDirectory
            });
        } else {
            console.warn(`[ActionHandler] launchApp action missing appEntry: ${JSON.stringify(action)}`);
        }
    }
}
