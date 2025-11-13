import QtQuick
import QtQuick.Layouts
import qs.services
import qs.core
import qs.views.quicksettings // Import the new quicksettings module

Rectangle {
    color: ColorService.palette.m3SurfaceContainerHigh
    radius: 15
    Layout.fillWidth: true
    Layout.preferredHeight: settingsLayout.implicitHeight + 30

    ColumnLayout {
        id: settingsLayout
        anchors.fill: parent
        anchors.margins: 15
        spacing: 15

        BrightnessSlider {
            Layout.fillWidth: true
        }

        VolumeSlider {
            Layout.fillWidth: true
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 10
            rowSpacing: 10

            WifiSetting {}
            BluetoothSetting {}
            NightlightSetting {}
            DndSetting {}
            LockSetting {}
            ScreenshotSetting {}
        }
    }
}
