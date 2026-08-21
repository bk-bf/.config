// Main.qml — the plugin's single data source and shared state.
//
// Runs `mem-top --json` on an interval and exposes the parsed consumer list.
// BarWidget.qml and Panel.qml read this instance through pluginApi.mainInstance,
// so one scan runs per interval no matter how many bars show the widget.
//
// The list is COMMITTED memory (RSS + swap), not RSS. On a zram-only machine an
// idle process has its heap compressed out of the resident set while still
// occupying the pool, so an RSS ranking hides the very consumers you are looking
// for.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
  id: root

  property var pluginApi

  // ── settings ────────────────────────────────────────────────────────────────
  readonly property var cfg: pluginApi ? pluginApi.pluginSettings : ({})
  readonly property string binPath: String((cfg && cfg.binPath) || "~/.local/bin/mem-top").trim()
  readonly property int intervalMs: Math.max(3000, (cfg && cfg.intervalMs) || 10000)
  readonly property int limit: Math.max(5, (cfg && cfg.limit) || 14)
  readonly property int warnPct: (cfg && cfg.warnPct) || 75
  readonly property int critPct: (cfg && cfg.critPct) || 88

  // Run through `sh -c` so a leading ~ in the configured path expands.
  readonly property string command: binPath + " --json --limit " + limit

  // ── state ───────────────────────────────────────────────────────────────────
  property var payload: null
  property string errorText: ""
  property bool loading: false
  property double lastOkMs: 0
  property int tick: 0

  readonly property bool ok: payload !== null && errorText === ""
  readonly property var system: (payload && payload.system) || null
  readonly property var entries: (payload && payload.entries) || []
  readonly property int otherMb: (payload && payload.otherMb) || 0
  readonly property int committedMb: (payload && payload.committedMb) || 0

  readonly property real usedPct: system ? (system.usedPct || 0) : 0
  readonly property int usedMb: system ? (system.usedMb || 0) : 0
  readonly property int swapUsedMb: system ? (system.swapUsedMb || 0) : 0
  readonly property int swapTotalMb: system ? (system.swapTotalMb || 0) : 0
  readonly property int availableMb: system ? (system.availableMb || 0) : 0
  readonly property int totalMb: system ? (system.totalMb || 0) : 0

  // The largest single entry, used to scale the panel's bars.
  readonly property int topMb: entries.length > 0 ? (entries[0].mb || 1) : 1

  // ── bar presentation ────────────────────────────────────────────────────────
  readonly property string barIconName: "activity"
  readonly property string barLabel: ok ? (Math.round(usedPct) + "%") : "…"

  // Committed memory beyond physical RAM is the honest pressure signal: it means
  // the machine is only coping because zram is compressing the overflow.
  readonly property bool overcommitted: ok && totalMb > 0 && committedMb > totalMb

  readonly property color stateColor: {
    if (!ok)
      return Color.mError;
    if (usedPct >= critPct)
      return Color.mError;
    if (usedPct >= warnPct || overcommitted)
      return Color.mSecondary;
    return Color.mPrimary;
  }

  // ── actions ─────────────────────────────────────────────────────────────────
  // Both go through `mem-top <verb> <name>` so the safety rules (never touch the
  // compositor, never reclaim the shared session cgroup) live in one place and
  // apply whether they are triggered from here or from a terminal.
  property var busyOp: ({})   // consumer name -> verb while in flight

  function isBusy(name) {
    return busyOp[name] !== undefined;
  }
  function _q(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
  }
  function _act(verb, name) {
    var b = busyOp;
    b[name] = verb;
    busyOp = b;      // reassign so the spinner shows immediately
    Quickshell.execDetached(["sh", "-c", root.binPath + " " + verb + " " + _q(name)]);
    settle.restart();
  }
  // Push cold pages out to zram. Nothing is killed; the process faults back in
  // whatever it still needs.
  function compact(name) {
    _act("reclaim", name);
  }
  function terminate(name) {
    _act("kill", name);
  }
  // Session-wide reclaim. Most GUI apps share one cgroup and cannot be compacted
  // individually, but reclaiming their common parent still works — the kernel
  // evicts the coldest pages across the session and kills nothing.
  function compactSession() {
    _act("reclaim-all", "1024");
  }

  function fmtMb(mb) {
    if (mb === undefined || mb === null)
      return "–";
    return mb >= 1024 ? (mb / 1024).toFixed(1) + " GB" : Math.round(mb) + " MB";
  }

  readonly property string tooltipText: {
    tick;
    if (!ok || !system)
      return "mem-top unavailable\n" + (errorText || "no data") + "\n" + command;
    var lines = [fmtMb(usedMb) + " of " + fmtMb(totalMb) + " used · " + fmtMb(availableMb) + " available", "swap " + fmtMb(swapUsedMb) + " of " + fmtMb(swapTotalMb), "committed " + fmtMb(committedMb) + (overcommitted ? "  ⚠ over physical RAM" : "")];
    for (var i = 0; i < Math.min(3, entries.length); i++)
      lines.push("  " + fmtMb(entries[i].mb) + "  " + entries[i].name);
    return lines.join("\n");
  }

  function fmtAge(ms) {
    if (!ms)
      return "never";
    var s = Math.max(0, Math.round((Date.now() - ms) / 1000));
    if (s < 60)
      return s + "s ago";
    if (s < 3600)
      return Math.floor(s / 60) + "m ago";
    return Math.floor(s / 3600) + "h ago";
  }
  readonly property string lastOkLabel: {
    tick;
    return fmtAge(lastOkMs);
  }

  // ── running the scan ────────────────────────────────────────────────────────
  function refresh() {
    if (loading || proc.running)
      return;
    loading = true;
    proc.running = true;
  }

  function _ingest(text) {
    var s = String(text || "").trim();
    if (s === "")
      return;
    try {
      root.payload = JSON.parse(s);
      root.errorText = "";
      root.lastOkMs = Date.now();
    } catch (e) {
      root.errorText = "invalid JSON from mem-top";
      Logger.w("mem-top", "parse failed:", e);
    }
  }

  Process {
    id: proc
    command: ["sh", "-c", root.command]

    stdout: StdioCollector {
      onStreamFinished: root._ingest(this.text)
    }
    stderr: StdioCollector {
      id: errCollector
    }
    onExited: exitCode => {
                root.loading = false;
                if (exitCode === 0)
                  return;
                var err = String(errCollector.text || "").trim();
                root.errorText = err !== "" ? err.split("\n").pop() : ("exited " + exitCode);
              }
  }

  Timer {
    interval: root.intervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
  // reclaim/kill settle, then re-scan so the row shows the new figure
  Timer {
    id: settle
    interval: 2500
    onTriggered: {
      root.busyOp = ({});
      root.refresh();
    }
  }
  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.tick++
  }

  Component.onCompleted: {
    Logger.i("mem-top", "plugin started, running:", command);

    // BarWidgetSettingsDialog resolves its page through
    // BarWidgetRegistry.widgetSettingsMap, which is populated with core widget
    // ids only — so right-clicking ANY plugin pill and choosing "Widget
    // settings" opens an empty dialog. Registering our page here gives the
    // dialog something to load. Harmless if a future shell version populates it.
    try {
      BarWidgetRegistry.widgetSettingsMap["plugin:mem-top"] = Qt.resolvedUrl("WidgetSettings.qml");
      Logger.i("mem-top", "registered widget settings page");
    } catch (e) {
      Logger.w("mem-top", "could not register widget settings page:", e);
    }
  }
}
