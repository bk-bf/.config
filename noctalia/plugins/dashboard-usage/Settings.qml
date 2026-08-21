// Settings.qml — shown by Noctalia's plugin settings popup.
// The popup calls saveSettings() on Apply; everything else is plain binding.

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi
  property int preferredWidth: 460

  readonly property var cfg: pluginApi ? pluginApi.pluginSettings : ({})

  implicitWidth: preferredWidth
  implicitHeight: col.implicitHeight

  function saveSettings() {
    if (!pluginApi)
      return;
    var s = pluginApi.pluginSettings || {};
    s.baseUrl = urlInput.text.trim().replace(/\/+$/, "");
    s.intervalMs = Math.max(5, intervalSpin.value) * 1000;
    s.barMetric = metricCombo.currentKey || "auto";
    s.warnPct = warnSpin.value;
    s.critPct = critSpin.value;
    s.colorBySeverity = colorToggle.checked;
    pluginApi.pluginSettings = s;
    pluginApi.saveSettings();
  }

  ColumnLayout {
    id: col
    width: parent.width
    spacing: Style.marginM

    NTextInput {
      id: urlInput
      Layout.fillWidth: true
      label: "Dashboard URL"
      description: "Base URL of the dashboard server — e.g. http://127.0.0.1:8787 or your tailnet HTTPS address."
      placeholderText: "http://127.0.0.1:8787"
      text: (root.cfg && root.cfg.baseUrl) || ""
    }

    NComboBox {
      id: metricCombo
      Layout.fillWidth: true
      label: "Bar shows"
      description: "Which number the pill displays."
      model: [
        {
          "key": "auto",
          "name": "Auto — plan % if available, else window spend"
        },
        {
          "key": "plan",
          "name": "Plan / cap percentage"
        },
        {
          "key": "tokens",
          "name": "Tokens used this 5-hour window"
        },
        {
          "key": "spend",
          "name": "Spent this 5-hour window"
        },
        {
          "key": "burn",
          "name": "Burn rate ($/hour)"
        },
        {
          "key": "projected",
          "name": "Projected window cost"
        },
        {
          "key": "remaining",
          "name": "Time left in window"
        }
      ]
      currentKey: (root.cfg && root.cfg.barMetric) || "auto"
      onSelected: key => metricCombo.currentKey = key
    }

    NSpinBox {
      id: intervalSpin
      Layout.fillWidth: true
      label: "Refresh interval"
      description: "How often to poll /api/usage. The server caches aggressively, so short intervals are cheap."
      from: 5
      to: 900
      stepSize: 5
      suffix: " s"
      value: Math.max(5, Math.round(((root.cfg && root.cfg.intervalMs) || 30000) / 1000))
    }

    NSpinBox {
      id: warnSpin
      Layout.fillWidth: true
      label: "Warning threshold"
      description: "Percentage of your plan/cap at which the widget turns amber."
      from: 1
      to: 100
      stepSize: 5
      suffix: " %"
      value: (root.cfg && root.cfg.warnPct) || 75
    }

    NSpinBox {
      id: critSpin
      Layout.fillWidth: true
      label: "Critical threshold"
      description: "Percentage at which the widget turns red."
      from: 1
      to: 100
      stepSize: 5
      suffix: " %"
      value: (root.cfg && root.cfg.critPct) || 90
    }

    NToggle {
      id: colorToggle
      Layout.fillWidth: true
      label: "Colour the pill by severity"
      description: "When off, the widget always uses your configured bar colours."
      checked: (root.cfg && root.cfg.colorBySeverity !== undefined) ? root.cfg.colorBySeverity : true
      onToggled: checked => colorToggle.checked = checked
    }
  }
}
