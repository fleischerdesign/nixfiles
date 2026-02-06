pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- Public API ---
    property var workspaces: []
    property var windows: []
    property int activeWorkspaceId: -1

    // --- Methods ---
    function refresh() {
        getWorkspacesProcess.running = true;
        getWindowsProcess.running = true;
    }

    function focusWorkspace(idx) {
        Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", idx.toString()]);
    }

    function focusNext() {
        Quickshell.execDetached(["niri", "msg", "action", "focus-workspace-down"]);
    }

    function focusPrevious() {
        Quickshell.execDetached(["niri", "msg", "action", "focus-workspace-up"]);
    }

    // --- Processes ---

    // 1. Initial/Manual Fetch Workspaces
    Process {
        id: getWorkspacesProcess
        command: ["niri", "msg", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text);
                    root.workspaces = data;
                    for (const ws of data) {
                        if (ws.is_active) root.activeWorkspaceId = ws.id;
                    }
                } catch (e) { console.error("WorkspaceService: Error parsing workspaces JSON"); }
            }
        }
    }

    // 2. Initial/Manual Fetch Windows
    Process {
        id: getWindowsProcess
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.windows = JSON.parse(this.text);
                } catch (e) { console.error("WorkspaceService: Error parsing windows JSON"); }
            }
        }
    }

    // 3. Live Event Stream
    // Niri sends a JSON object per line for events.
    Process {
        id: eventStreamProcess
        running: true
        command: ["niri", "msg", "event-stream"]
        stdout: StdioCollector {
            waitForEnd: false
            onTextChanged: {
                // Whenever an event happens, we just refresh the whole state.
                // This is the most robust way to stay in sync with Niri's complex layout state.
                root.refresh();
            }
        }
    }

    Component.onCompleted: refresh()
}
