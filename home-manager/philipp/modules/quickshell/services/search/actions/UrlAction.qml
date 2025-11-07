import QtQuick
import Quickshell.Io
import "./"

// Handles actions of type "url"
BaseAction {
    type: "url"

    Process {
        id: shellProcess
    }

    function execute(action) {
        shellProcess.command = ["xdg-open", action.url]
        shellProcess.running = true
    }
}
