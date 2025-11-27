// components/QuickSettingButton.qml
import QtQuick
import qs.components

M3Button {
    id: root

    property bool toggled: false
    property string icon: ""
    property string label: ""

    // Override M3Button style based on toggled state
    style: toggled ? M3Button.Style.Filled : M3Button.Style.FilledTonal
    colorRole: M3Button.ColorRole.Primary

    // Make it a square
    implicitWidth: 80
    implicitHeight: 80
    radius: 15

    // Override default content (which is a Row) with a Column
    content: Column {
        spacing: 4

        Text {
            text: root.icon
            font.family: "Material Symbols Rounded"
            font.pixelSize: 28
            color: root.autoContentColor
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: root.label
            font.pixelSize: 12
            font.weight: Font.Medium
            color: root.autoContentColor
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
