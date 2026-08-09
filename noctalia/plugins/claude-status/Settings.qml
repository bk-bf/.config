// Settings.qml — shown by Noctalia's plugin settings popup.
// The popup calls saveSettings() on Apply.

import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi
  property int preferredWidth: 480

  readonly property var cfg: pluginApi ? pluginApi.pluginSettings : ({})

  implicitWidth: preferredWidth
  implicitHeight: col.implicitHeight

  function saveSettings() {
    if (!pluginApi)
      return;
    var s = pluginApi.pluginSettings || {};
    s.binPath = binInput.text.trim();
    s.intervalMs = Math.max(5, intervalSpin.value) * 1000;
    s.idleWarnSec = Math.max(30, idleSpin.value);
    s.terminalCmd = termInput.text.trim();
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
      label: "claude-status path"
      description: "A leading ~ is expanded; the path must not contain spaces."
      placeholderText: "~/.local/bin/claude-status"
      text: (root.cfg && root.cfg.binPath) || ""
    }

    NSpinBox {
      id: intervalSpin
      Layout.fillWidth: true
      label: "Scan interval"
      description: "Seconds between scans. Each scan reads /proc and asks systemd about a handful of units — cheap, but there is no reason to do it every second."
      from: 5
      to: 300
      stepSize: 5
      suffix: "s"
      value: Math.max(5, Math.round(((root.cfg && root.cfg.intervalMs) || 15000) / 1000))
    }

    NSpinBox {
      id: idleSpin
      Layout.fillWidth: true
      label: "Silent-session threshold"
      description: "A headless session whose transcript has not grown for this long is treated as stalled and turns the bar icon red. Long tool calls are normal, so leave enough room for one."
      from: 30
      to: 3600
      stepSize: 30
      suffix: "s"
      value: Math.max(30, (root.cfg && root.cfg.idleWarnSec) || 300)
    }

    NTextInput {
      id: termInput
      Layout.fillWidth: true
      label: "Terminal"
      description: "Used to open a triage report or watch the full status output."
      placeholderText: "kitty"
      text: (root.cfg && root.cfg.terminalCmd) || ""
    }
  }
}
