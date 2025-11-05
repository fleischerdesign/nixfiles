import QtQuick

// A simple, non-visual component that represents a self-contained, executable action.
// It provides a type-safe QObject that can be passed around in models.
Item {
    // This signal is emitted when the action is executed.
    signal triggered()

    // This function is called by the UI to perform the action.
    function execute() {
        triggered()
    }
}
