// Settings.qml — shown by Noctalia's plugin settings popup.

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
    s.binPath = binInput.text.trim();
    s.intervalMs = Math.max(15, intervalSpin.value) * 1000;
    s.terminalCmd = termInput.text.trim() || "kitty";
    pluginApi.pluginSettings = s;
    pluginApi.saveSettings();
  }

  ColumnLayout {
    id: col
    width: parent.width
    spacing: Style.marginM

    NTextInput {
      id: binInput
      Layout.fillWidth: true
      label: "git-status path"
      description: "The scanner script that emits JSON. Edit ~/.config/git-status/roots.json to change which repos it scans."
      placeholderText: "~/.local/bin/git-status"
      text: (root.cfg && root.cfg.binPath) || "~/.local/bin/git-status"
    }

    NSpinBox {
      id: intervalSpin
      Layout.fillWidth: true
      label: "Re-scan interval"
      description: "How often to scan your repos. Scans are cheap (~0.2s), but they still shell out per repo."
      from: 15
      to: 900
      stepSize: 15
      suffix: " s"
      value: Math.max(15, Math.round(((root.cfg && root.cfg.intervalMs) || 60000) / 1000))
    }

    NTextInput {
      id: termInput
      Layout.fillWidth: true
      label: "Terminal"
      description: "Opened at a repo when you click the commit button (must accept --directory)."
      placeholderText: "kitty"
      text: (root.cfg && root.cfg.terminalCmd) || "kitty"
    }
  }
}
