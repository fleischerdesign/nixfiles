pragma Singleton
import QtQuick
import Quickshell.Io
import qs.services

// This singleton is responsible for executing actions described by an object.
Item {
    id: root

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
        if (!action) return;

        console.log(`[ActionHandler] Executing action: ${JSON.stringify(action)}`)

        switch (action.type) {
            case "command":
                shellProcess.command = action.command
                shellProcess.running = true
                break;
            case "url":
                shellProcess.command = ["xdg-open", action.url]
                shellProcess.running = true
                break;
            case "copy":
                shellProcess.command = ["sh", "-c", `echo "${action.text}" | wl-copy`]
                shellProcess.running = true
                NotificationService.send(
                    "In die Zwischenablage kopiert",
                    action.text,
                    "content_copy"
                )
                break;
            case "launchApp": // New case for launching applications
                if (action.appEntry && typeof action.appEntry.execute === 'function') {
                    action.appEntry.execute();
                } else {
                    console.warn(`[ActionHandler] launchApp action missing executable appEntry: ${JSON.stringify(action)}`);
                }
                break;
            case "noAction": // New case for actions that do nothing
                // Do nothing
                break;
            default:
                console.warn(`[ActionHandler] Unknown action type: ${action.type}`)
        }
    }
}
