import Quickshell
import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import qs.core
import qs.views
import qs.components
import qs.services.search as Search

ShellRoot {
    AppLauncher {
        id: appLauncher
        onAppLaunched: (appName) => {
            // TODO: Implement actual application launching logic
            console.log("Request to launch:", appName)
            appLauncher.visible = false
        }
    }

    VolumeOSD {}
    BrightnessOSD {}
    NotificationHost {}

    NotificationCenter {
        id: nc
    }
    
    AudioPanel {
        id: audioPanel
    }
    
    PowerPanel {
        id: powerPanel
    }
    
    NetworkPanel {
        id: networkPanel
    }
    
    BluetoothPanel {
        id: bluetoothPanel
    }

    WlSessionLock {
        id: sessionLocker
        // Surface wird dynamisch basierend auf locked-Status erstellt
        surface: sessionLocker.locked ? lockSurfaceComponent : null
        
        Component {
            id: lockSurfaceComponent
            WlSessionLockSurface {
                color: "transparent"
                Lockscreen {
                    id: lockScreenComponent
                    anchors.fill: parent
                    
                    onUnlocked: {
                        sessionLocker.locked = false;
                    }
                }
            }
        }
    }
    
    IpcHandler {
        target: "lockscreen"
        function lock(): void {
            sessionLocker.locked = true;
        }
    }

    IpcHandler {
        target: "applauncher"
        function open(): void {
            StateManager.activePanel = "launcher";
        }
        function close(): void {
            if (StateManager.activePanel === "launcher") StateManager.activePanel = "";
        }
        function toggle(): void {
            StateManager.togglePanel("launcher");
        }
    }
    
    BottomBar {
        id: bottomBarWindow
        onAppLauncherClicked: StateManager.togglePanel("launcher")
        onVolumeClicked: StateManager.togglePanel("audio")
        onPowerClicked: StateManager.togglePanel("power")
        onWifiClicked: StateManager.togglePanel("network")
        onBluetoothClicked: StateManager.togglePanel("bluetooth")
    }
}
