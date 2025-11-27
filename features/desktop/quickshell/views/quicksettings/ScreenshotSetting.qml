import QtQuick
import qs.components
import qs.services
import Quickshell.Io

QuickSettingButton {
    id: screenshotButton
    icon: "screenshot"
    label: "Screenshot"
    onClicked: {
        screenshotProcess.command = ["niri", "msg", "action", "screenshot"]
        screenshotProcess.running = true
    }

    Process {
        id: screenshotProcess
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                NotificationService.send(
                    "Screenshot fehlgeschlagen",
                    `Der Screenshot-Befehl ist mit Exit-Code ${exitCode} fehlgeschlagen.`,
                    "dialog-error"
                )
            } else {
                NotificationService.send(
                    "Screenshot erstellt",
                    "Der Screenshot wurde erfolgreich erstellt.",
                    "image"
                )
            }
        }
    }
}
