// Batteries: the laptop plus devices UPower reports (Bluetooth mice, keyboards, headphones, phones…).
//   small = up to 4 rings in a 2×2 grid; medium = up to 4 rings in a row with names; large = a list with bars
import QtQuick
import Quickshell.Services.UPower
import "SilkyWidgetsFormat.js" as F

Item {
    id: w
    required property var host
    readonly property var devices: {
        var all = UPower.devices ? UPower.devices.values : [], out = [];
        for (var i = 0; i < all.length; i++) {
            var d = all[i];
            if (!d || !d.ready) continue;
            if (d.isLaptopBattery) { if (d.isPresent) out.unshift(d); continue; }
            if (d.type === UPowerDeviceType.LinePower || d.type === UPowerDeviceType.Unknown || d.powerSupply) continue;
            if (d.percentage > 0) out.push(d);
        }
        return out;
    }
    function pct(d) { return d ? Math.round(d.percentage <= 1 ? d.percentage * 100 : d.percentage) : 0; }
    function charging(d) { return d && (d.state === UPowerDeviceState.Charging || d.state === UPowerDeviceState.FullyCharged); }
    function name(d) {
        if (!d) return "";
        if (d.isLaptopBattery) return F.tr("This laptop");
        return d.model || UPowerDeviceType.toString(d.type);
    }
    // 4-tier battery scale: charging / abundant (> 65%) green, normal (36-65%) cyan,
    // low (20-35%) amber, critical (< 20%) red.
    function ink(d) {
        if (charging(d)) return w.host.dark ? "#30d158" : "#1c8241";
        var p = pct(d);
        if (p < 20) return w.host.dark ? "#ff453a" : "#c92a22";
        if (p <= 35) return w.host.dark ? "#ff9f0a" : "#b85d00";
        if (p <= 65) return w.host.dark ? "#64d2ff" : "#0071a4";
        return w.host.dark ? "#30d158" : "#1c8241";
    }

    SilkyWLabel {
        visible: w.devices.length === 0
        host: w.host; anchors.centerIn: parent; dim: true; text: F.tr("No battery")
    }

    // rings: small (2×2) and medium (a row of 4)
    Grid {
        visible: w.host.size !== "large" && w.devices.length > 0
        anchors.centerIn: parent
        columns: w.host.size === "small" ? 2 : 4
        columnSpacing: w.host.size === "small" ? 14 : 20
        rowSpacing: 12
        Repeater {
            model: w.devices.slice(0, 4)
            Column {
                required property var modelData
                spacing: 6
                readonly property real ring: w.host.size === "small" ? (w.devices.length === 1 ? 104 : 56) : 62
                Item {
                    width: parent.ring; height: parent.ring
                    anchors.horizontalCenter: parent.horizontalCenter
                    SilkyWRing {
                        anchors.fill: parent
                        value: w.pct(modelData)
                        ink: w.ink(modelData)
                        track: w.host.track
                        line: parent.width > 80 ? 9 : 6
                    }
                    SilkyWLabel {
                        anchors.centerIn: parent
                        host: w.host; strong: true
                        px: parent.width > 80 ? 24 : 14
                        text: (w.charging(modelData) ? "⚡" : "") + w.pct(modelData) + "%"
                    }
                }
                SilkyWLabel {
                    visible: w.host.size === "medium" || w.devices.length === 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, 72)
                    host: w.host; dim: true; px: 11; text: w.name(modelData)
                }
            }
        }
    }

    // list (large)
    Column {
        visible: w.host.size === "large" && w.devices.length > 0
        x: 16; y: 14
        width: parent.width - 32
        spacing: 10
        SilkyWLabel { host: w.host; dim: true; strong: true; px: 12; text: F.tr("Batteries") }
        Repeater {
            model: w.devices.slice(0, 7)
            Item {
                required property var modelData
                width: parent.width
                height: 34
                SilkyWRing {
                    width: 30; height: 30
                    anchors.verticalCenter: parent.verticalCenter
                    value: w.pct(modelData); ink: w.ink(modelData); track: w.host.track; line: 4
                }
                SilkyWLabel { x: 42; y: 0; width: parent.width - 110; host: w.host; px: 13; text: w.name(modelData) }
                SilkyWLabel {
                    x: 42; y: 18; host: w.host; dim: true; px: 11
                    text: w.charging(modelData) ? F.tr("Charging") : ""
                }
                SilkyWLabel {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    host: w.host; strong: true; px: 15; text: w.pct(modelData) + "%"
                }
            }
        }
    }
}
