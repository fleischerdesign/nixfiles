import QtQuick
import QtQuick.Controls.Basic
import qs.services

Slider {
    id: root

    property string icon: ""

    implicitHeight: 40

    handle: null

    background: Rectangle {
        id: backgroundTrack
        width: root.width
        height: 30
        radius: 15
        color: ColorService.palette.m3SurfaceContainerHighest
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            id: progressBar
            width: backgroundTrack.width * root.position
            height: parent.height
            radius: 15
            color: ColorService.palette.m3Primary
            clip: true

            Text {
                visible: root.icon !== ""
                text: root.icon
                font.family: "Material Symbols Rounded"
                font.pixelSize: 20
                color: ColorService.palette.m3OnPrimary
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 10
            }
        }
    }
}
