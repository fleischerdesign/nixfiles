import QtQuick
import qs.services

Text {
    property color iconColor: ColorService.palette.m3OnSurface

    visible: NetworkService.ethernetConnected

    text: "lan"
    font.family: "Material Symbols Rounded"
    font.pixelSize: 18
    color: iconColor
}
