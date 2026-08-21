// Settings.qml — shown by Noctalia's plugin settings popup.
//
// Two groups: the metrics shown in the bar (the forked system-monitor settings,
// so nothing is lost by using this widget instead of the built-in one), and the
// options for the memory scanner behind the panel.

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi
  property int preferredWidth: 460

  readonly property var cfg: pluginApi ? pluginApi.pluginSettings : ({})

  // The popup sizes itself from this item's implicitHeight, and the loader sizes
  // itself from the popup — so taking the column's width from `parent.width`
  // makes the height depend on a width that does not exist yet, and the whole
  // page collapses to nothing. Drive the width from preferredWidth instead.
  implicitWidth: preferredWidth
  implicitHeight: col.implicitHeight

  function val(key, fallback) {
    return (cfg && cfg[key] !== undefined) ? cfg[key] : fallback;
  }

  function saveSettings() {
    if (!pluginApi)
      return;
    var s = pluginApi.pluginSettings || {};

    s.showCpuUsage = cpuUsage.checked;
    s.showCpuTemp = cpuTemp.checked;
    s.showCpuFreq = cpuFreq.checked;
    s.showCpuCores = cpuCores.checked;
    s.showGpuTemp = gpuTemp.checked;
    s.showMemoryUsage = memUsage.checked;
    s.showMemoryAsPercent = memPercent.checked;
    s.showSwapUsage = swapUsage.checked;
    s.showNetworkStats = netStats.checked;
    s.showDiskUsage = diskUsage.checked;
    s.showLoadAverage = loadAvg.checked;
    s.compactMode = compact.checked;
    s.useMonospaceFont = mono.checked;

    s.binPath = binInput.text.trim() || "~/.local/bin/mem-top";
    s.intervalMs = Math.max(3, intervalSpin.value) * 1000;
    s.limit = limitSpin.value;

    pluginApi.pluginSettings = s;
    pluginApi.saveSettings();
  }

  ColumnLayout {
    id: col
    width: root.preferredWidth
    spacing: Style.marginM

    NText {
      text: "Bar metrics"
      pointSize: Style.fontSizeL
      font.weight: Style.fontWeightBold
    }

    NToggle {
      id: cpuUsage
      Layout.fillWidth: true
      label: "CPU usage"
      checked: root.val("showCpuUsage", true)
    }
    NToggle {
      id: cpuTemp
      Layout.fillWidth: true
      label: "CPU temperature"
      checked: root.val("showCpuTemp", true)
    }
    NToggle {
      id: cpuFreq
      Layout.fillWidth: true
      label: "CPU frequency"
      checked: root.val("showCpuFreq", false)
    }
    NToggle {
      id: cpuCores
      Layout.fillWidth: true
      label: "Per-core usage"
      checked: root.val("showCpuCores", false)
    }
    NToggle {
      id: gpuTemp
      Layout.fillWidth: true
      label: "GPU temperature"
      checked: root.val("showGpuTemp", false)
    }
    NToggle {
      id: memUsage
      Layout.fillWidth: true
      label: "Memory usage"
      checked: root.val("showMemoryUsage", true)
    }
    NToggle {
      id: memPercent
      Layout.fillWidth: true
      label: "Memory as percent"
      description: "Off shows an absolute figure instead."
      checked: root.val("showMemoryAsPercent", true)
    }
    NToggle {
      id: swapUsage
      Layout.fillWidth: true
      label: "Swap usage"
      checked: root.val("showSwapUsage", false)
    }
    NToggle {
      id: netStats
      Layout.fillWidth: true
      label: "Network stats"
      checked: root.val("showNetworkStats", false)
    }
    NToggle {
      id: diskUsage
      Layout.fillWidth: true
      label: "Disk usage"
      checked: root.val("showDiskUsage", false)
    }
    NToggle {
      id: loadAvg
      Layout.fillWidth: true
      label: "Load average"
      checked: root.val("showLoadAverage", false)
    }
    NToggle {
      id: compact
      Layout.fillWidth: true
      label: "Compact mode"
      description: "Gauges instead of numbers."
      checked: root.val("compactMode", false)
    }
    NToggle {
      id: mono
      Layout.fillWidth: true
      label: "Monospace font"
      checked: root.val("useMonospaceFont", false)
    }

    NText {
      text: "Memory breakdown"
      pointSize: Style.fontSizeL
      font.weight: Style.fontWeightBold
      Layout.topMargin: Style.marginM
    }

    NTextInput {
      id: binInput
      Layout.fillWidth: true
      label: "mem-top path"
      description: "Script that emits the ranking as JSON. Run it in a terminal to see the same list."
      placeholderText: "~/.local/bin/mem-top"
      text: root.val("binPath", "~/.local/bin/mem-top")
    }

    NSpinBox {
      id: intervalSpin
      Layout.fillWidth: true
      label: "Scan interval"
      description: "Seconds between memory scans."
      from: 3
      to: 120
      value: Math.round(root.val("intervalMs", 10000) / 1000)
      suffix: " s"
    }

    NSpinBox {
      id: limitSpin
      Layout.fillWidth: true
      label: "Entries shown"
      description: "How many consumers to list. The remainder is summed as \"everything else\"."
      from: 5
      to: 40
      value: root.val("limit", 14)
    }
  }
}
