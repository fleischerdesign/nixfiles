import Quickshell
import QtQuick
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    VolumeOSD {}
    BrightnessOSD {}
    
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