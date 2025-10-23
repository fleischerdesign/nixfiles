import Quickshell
import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import qs.core
import qs.modules

ShellRoot {
    ClickInterceptor {
        id: ncInterceptor
        visible: StateManager.notificationCenterOpened
        onClicked: {
            StateManager.notificationCenterOpened = false
        }
    }
    VolumeOSD {}
    BrightnessOSD {}
    Notifications {}

    NotificationCenter {
        id: nc
        shouldBeVisible: ncInterceptor.backingWindowVisible && StateManager.notificationCenterOpened
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
    
    BottomBar {
        id: bottomBarWindow
    }
}
