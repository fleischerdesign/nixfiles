import Quickshell
import QtQuick
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    VolumeOSD {}
    BrightnessOSD {}

    PanelWindow {
      id: notificationCenter
      anchors {
	right: true
	bottom: true
	top: true
      } 
      margins.bottom: 65 + 10
      margins.right: 10
      margins.top: 10
      exclusiveZone: 0
      color: "transparent"
      implicitWidth: 400
      visible: false

      Rectangle {
	anchors.fill: parent
	radius: 15
	color: "#000"
      }
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
