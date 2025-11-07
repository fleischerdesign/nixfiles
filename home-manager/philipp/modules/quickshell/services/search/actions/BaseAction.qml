// Base class for all action handlers.
import QtQuick

Item {
    objectName: "actionHandler"
    // The unique type name for this action, e.g., "command", "url".
    property string type: ""

    // The function that executes the action.
    // Concrete handlers must implement this.
    function execute(actionObject) {
        console.warn(`[BaseAction] execute() not implemented for action type: ${actionObject.type}`)
    }
}
