// Lockscreen.qml (Finale UI-Komponente)

import QtQuick
import QtQuick.Controls
import Quickshell.Services.Pam

Rectangle {
    id: root
    color: "#282a36"

    signal unlocked()
    property alias user: pamAuth.user

    PamContext { id: pamAuth }

    Connections {
        target: pamAuth
        onPamMessage: {
            promptLabel.text = pamAuth.message
            if (pamAuth.responseRequired) {
                passwordInput.visible = true
                passwordInput.echoMode = pamAuth.responseVisible ? TextInput.Normal : TextInput.Password
                passwordInput.forceActiveFocus()
            }
        }
        onCompleted: (result) => {
            if (result === PamResult.Success) {
                unlocked()
            } else {
                statusLabel.text = "Authentifizierung fehlgeschlagen"
                passwordInput.text = ""
                shakeAnimation.start()
                pamAuth.start()
            }
        }
    }
    
    Component.onCompleted: {
        pamAuth.start()
    }

    Column {
        anchors.centerIn: parent
        spacing: 25
        width: 400

        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: 72
            font.weight: Font.Light
            color: "white"
            text: Qt.formatTime(new Date(), "hh:mm")
            
            Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.text = Qt.formatTime(new Date(), "hh:mm") }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 15
            Rectangle { width: 60; height: 60; radius: 30; color: "#44475a" }
            Text { text: pamAuth.user; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 24; color: "white" }
        }

        Text {
            id: promptLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Gesperrt"
            font.pixelSize: 22
            color: "white"
        }

        TextField {
            id: passwordInput
            width: parent.width
            placeholderText: "Passwort"
            echoMode: TextInput.Password
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 18
            visible: false
            onAccepted: pamAuth.respond(passwordInput.text)
            
            SequentialAnimation { 
                id: shakeAnimation; running: false
                NumberAnimation { target: passwordInput; property: "x"; to: 10; duration: 50 }
                NumberAnimation { target: passwordInput; property: "x"; to: -10; duration: 100 }
                NumberAnimation { target: passwordInput; property: "x"; to: 0; duration: 50 }
            }
        }

        Text { id: statusLabel; anchors.horizontalCenter: parent.horizontalCenter; font.pixelSize: 14; color: "#ff5555" }
    }

    Button {
        anchors { bottom: parent.bottom; right: parent.right; margins: 20 }
        text: "Notfall-Entsperrung"
        onClicked: { unlocked() }
    }
}
