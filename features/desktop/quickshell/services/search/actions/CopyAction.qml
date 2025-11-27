import QtQuick
import Quickshell.Io
import qs.services
import "./"

// Handles actions of type "copy"
BaseAction {
    type: "copy"

    Process {
        id: shellProcess
    }

    function execute(action) {
        shellProcess.command = ["sh", "-c", `echo "${action.text}" | wl-copy`]
        shellProcess.running = true
        NotificationService.send(
            "In die Zwischenablage kopiert",
            action.text,
            "content_copy"
        )
    }
}
