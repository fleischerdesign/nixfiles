import QtQuick
import Quickshell.Io
import qs.services
import "./"

// Handles actions of type "command"
BaseAction {
    type: "command"

    Process {
        id: shellProcess
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                NotificationService.send(
                    "Aktion fehlgeschlagen",
                    `Befehl ist mit Code ${exitCode} fehlgeschlagen.`,
                    "dialog-error"
                )
            }
        }
    }

    function execute(action) {
        shellProcess.command = action.command
        shellProcess.running = true
    }
}
