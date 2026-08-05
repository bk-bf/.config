// Main.qml — the plugin's single data source and shared state.
//
// Runs `claude-status --json` on an interval. BarWidget.qml and Panel.qml read
// this instance through pluginApi.mainInstance, so one scan runs per interval
// no matter how many bars show the widget.
//
// The figure that matters is `idleSec` per session, not "is the process alive".
// A headless run that has wedged has the same process, the same RSS and the
// same uptime as one that is working; the only honest difference is whether its
// transcript is still growing. claude-status derives that, this shows it.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var pluginApi

  // ── settings ────────────────────────────────────────────────────────────────
  readonly property var cfg: pluginApi ? pluginApi.pluginSettings : ({})
  readonly property string binPath: String((cfg && cfg.binPath) || "~/.local/bin/claude-status").trim()
  readonly property int intervalMs: Math.max(5000, (cfg && cfg.intervalMs) || 15000)
  readonly property int idleWarnSec: Math.max(30, (cfg && cfg.idleWarnSec) || 300)
  readonly property bool hideWhenIdle: (cfg && cfg.hideWhenIdle) === true
  readonly property string terminalCmd: String((cfg && cfg.terminalCmd) || "kitty").trim()

  readonly property string command: binPath + " --json --compact"

  // ── state ───────────────────────────────────────────────────────────────────
  property var payload: null
  property string errorText: ""
  property bool loading: false
  property double lastOkMs: 0
  property int tick: 0

  readonly property bool ok: payload !== null && errorText === ""
  readonly property var agents: (payload && payload.agents) || null
  readonly property var running: (agents && agents.running) || []
  readonly property var recent: (agents && agents.recent) || []
  readonly property var triggers: (payload && payload.triggers) || []
  readonly property var jobs: (payload && payload.jobs) || []
  readonly property var alerts: (payload && payload.alerts) || []
  readonly property var interactive: (payload && payload.interactive) || null
  readonly property var sessions: (payload && payload.sessions) || []

  readonly property int runningCount: running.length

  // A trigger that is not armed is the worst state this widget can report:
  // nothing is watching, and nothing will tell you so.
  readonly property bool triggersArmed: {
    if (triggers.length === 0)
      return false;
    for (var i = 0; i < triggers.length; i++)
      if (!triggers[i].armed)
        return false;
    return true;
  }

  readonly property int stalledCount: {
    var n = 0;
    for (var i = 0; i < running.length; i++) {
      var t = running[i].transcript;
      var idle = t ? t.idle_sec : -1;
      if (idle !== undefined && idle >= 0 && idle > root.idleWarnSec)
        n++;
    }
    return n;
  }

  readonly property bool jobsHealthy: {
    for (var i = 0; i < jobs.length; i++)
      if (!jobs[i].ok)
        return false;
    return true;
  }

  // ── bar presentation ────────────────────────────────────────────────────────
  readonly property string barIconName: "brain"
  // The count is agents, not sessions. Zero is the normal, correct answer.
  readonly property string barLabel: ok ? String(runningCount) : "…"

  readonly property color stateColor: {
    if (!ok)
      return Color.mError;
    if (!triggersArmed || stalledCount > 0)
      return Color.mError;
    if (!jobsHealthy || alerts.length > 0)
      return Color.mSecondary;
    if (runningCount > 0)
      return Color.mPrimary;
    return Color.mOnSurfaceVariant;
  }

  // ── helpers shared with the panel ───────────────────────────────────────────
  function idleOf(s) {
    var t = s && s.transcript ? s.transcript : null;
    if (!t)
      return -1;
    return t.idle_sec !== undefined ? t.idle_sec : (t.idleSec !== undefined ? t.idleSec : -1);
  }

  function fmtAgo(sec) {
    if (sec === undefined || sec === null || sec < 0)
      return "–";
    sec = Math.round(sec);
    if (sec < 60)
      return sec + "s";
    if (sec < 3600)
      return Math.floor(sec / 60) + "m";
    if (sec < 86400)
      return Math.floor(sec / 3600) + "h";
    return Math.floor(sec / 86400) + "d";
  }

  function fmtMb(mb) {
    if (mb === undefined || mb === null)
      return "–";
    return mb >= 1024 ? (mb / 1024).toFixed(1) + "G" : Math.round(mb) + "M";
  }

  function _q(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
  }

  // Open the full report for a triage run in a terminal. `watcher report` prints
  // the whole transcript, which is far more than a panel should try to render.
  function openReport(id) {
    Quickshell.execDetached(["sh", "-c", root.terminalCmd + " -e sh -c " + _q("watcher report " + id + "; echo; read -n1 -p 'enter to close'")]);
  }
  function openStatus() {
    Quickshell.execDetached(["sh", "-c", root.terminalCmd + " -e sh -c " + _q("watch -c -n5 " + root.binPath)]);
  }

  // Bring a session into the foreground.
  //
  // Both go through `claude-status open`, which owns terminal detection. That
  // used to be built here as `<term> -e sh -c ...`, which silently did nothing
  // under kitty — kitty has no -e flag, its form is `kitty [options] program`.
  // Keeping it in the CLI means it can be run and fixed from a shell instead of
  // guessed at through the bar.
  //
  // A RUNNING agent cannot be resumed: it is headless, there is no terminal to
  // join, and --resume on a live id would put a second writer on its
  // transcript. So live gets follow, finished gets resume.
  function followAgent(sessionId) {
    if (!sessionId)
      return;
    Quickshell.execDetached(["sh", "-c", root.binPath + " open --follow " + sessionId + " --term " + root.terminalCmd]);
  }

  function resumeSession(sessionId, cwd) {
    if (!sessionId)
      return;
    var extra = cwd && cwd !== "" ? " --cwd " + _q(cwd) : "";
    Quickshell.execDetached(["sh", "-c", root.binPath + " open --resume " + sessionId + extra + " --term " + root.terminalCmd]);
  }

  // Focus an existing herdr pane. No terminal, no nesting — herdr raises it.
  function focusPane(paneId) {
    if (!paneId)
      return;
    Quickshell.execDetached(["sh", "-c", root.binPath + " open --focus " + _q(paneId)]);
  }

  function openHerdr(cwd, name) {
    Quickshell.execDetached(["sh", "-c", root.binPath + " open --herdr " + _q(name || "claude") + " --cwd " + _q(cwd || "~") + " --term " + root.terminalCmd]);
  }

  // Runs the suggested fix in a terminal rather than silently: the command is
  // visible, its output is visible, and the click is the authorisation.
  function runAction(cmd, cwd) {
    if (!cmd)
      return;
    Quickshell.execDetached(["sh", "-c", root.binPath + " open --run " + _q(cmd) + " --cwd " + _q(cwd || "~") + " --term " + root.terminalCmd]);
  }

  function openScript(path) {
    if (!path)
      return;
    Quickshell.execDetached(["sh", "-c", root.binPath + " open --edit " + _q(path) + " --term " + root.terminalCmd]);
  }

  // Anything the agent already finished can be reopened; a live one cannot.
  function canResume(r) {
    return !!(r && r.session_id);
  }

  readonly property string tooltipText: {
    tick;
    if (!ok)
      return "claude-status unavailable\n" + (errorText || "no data") + "\n" + command;
    var lines = [];
    for (var t = 0; t < triggers.length; t++) {
      var tr = triggers[t];
      lines.push((tr.armed ? "● " : "✗ ") + tr.name + " · " + (tr.armed ? "armed" : "NOT ARMED"));
      if (!tr.armed && tr.why)
        lines.push("    " + tr.why);
    }
    lines.push(runningCount === 0 ? "no agent running" : runningCount + " agent(s) running");
    for (var i = 0; i < running.length && i < 3; i++)
      lines.push("  " + (running[i].project || "?") + " · out " + fmtAgo(idleOf(running[i])) + " ago");
    for (var j = 0; j < alerts.length && j < 3; j++)
      lines.push("! " + alerts[j]);
    return lines.join("\n");
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
      root.errorText = "invalid JSON from claude-status";
      Logger.w("claude-status", "parse failed:", e);
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
  // Re-evaluates the relative times in the tooltip without re-running the scan.
  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.tick++
  }

  Component.onCompleted: Logger.i("claude-status", "plugin started, running:", command)
}
