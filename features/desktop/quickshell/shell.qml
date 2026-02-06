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
            StateManager.appLauncherOpened = true;
        }
        function close(): void {
            StateManager.appLauncherOpened = false;
        }
        function toggle(): void {
            StateManager.appLauncherOpened = !StateManager.appLauncherOpened;
        }
    }
    
    BottomBar {
        id: bottomBarWindow
        onAppLauncherClicked: appLauncher.toggle()
        onVolumeClicked: audioPanel.toggle()
        onPowerClicked: powerPanel.toggle()
        onWifiClicked: networkPanel.toggle()
        onBluetoothClicked: bluetoothPanel.toggle()
    }
}
