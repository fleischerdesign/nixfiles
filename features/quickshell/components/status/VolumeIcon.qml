import QtQuick
import qs.services

Text {
    property color iconColor: ColorService.palette.m3OnSurface

    // Connections to AudioService are implicit through property bindings
    text: AudioService.muted ? "volume_off" : "volume_up"
    font.family: "Material Symbols Rounded"
    font.pixelSize: 18
    color: iconColor
}
