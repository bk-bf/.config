// Main.qml — the plugin's single data source and shared state.
//
// Runs `git-status --json` (~/.local/bin/git-status) on an interval and exposes
// the parsed repo list + summary. BarWidget.qml and Panel.qml read this instance
// through pluginApi.mainInstance, so one scan runs per interval regardless of how
// many bars show the widget. Actions (pull/push/open-to-commit) are fire-and-
// forget with a short delayed re-scan so the panel reflects the new state.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var pluginApi

  // ── settings ────────────────────────────────────────────────────────────────
  readonly property var cfg: pluginApi ? pluginApi.pluginSettings : ({})
  readonly property string binPath: String((cfg && cfg.binPath) || "~/.local/bin/git-status").trim()
  readonly property int intervalMs: Math.max(15000, (cfg && cfg.intervalMs) || 60000)
  readonly property string terminalCmd: String((cfg && cfg.terminalCmd) || "kitty").trim()

  // Run through `sh -c` so a leading ~ in the configured path expands.
  readonly property string command: binPath + " --json"

  // ── state ───────────────────────────────────────────────────────────────────
  property var payload: null
  property string errorText: ""
  property bool loading: false
  property double lastOkMs: 0
  property int tick: 0

  readonly property bool ok: payload !== null && errorText === ""
  readonly property var summary: (payload && payload.summary) || null
  readonly property var repos: (payload && payload.repos) || []
  readonly property int attention: summary ? (summary.attention || 0) : 0

  // ── AI-commit activity (from ~/.cache/git-ai-commit state files) ─────────────
  readonly property var activity: (payload && payload.activity) || []
  property var localWorking: ({})   // path → click-time; drives the spinner before the first poll sees "running"

  function _actFor(path) {
    for (var i = 0; i < activity.length; i++)
      if (activity[i].path === path)
        return activity[i];
    return null;
  }
  function isWorking(path) {
    var a = _actFor(path);
    if (a && a.state === "running")
      return true;
    if (a && (a.ts || 0) >= (localWorking[path] || 0))
      return false; // a run finished after our click
    return !!localWorking[path];
  }
  readonly property bool anyWorking: {
    for (var i = 0; i < activity.length; i++)
      if (activity[i].state === "running")
        return true;
    for (var k in localWorking)
      if (isWorking(k))
        return true;
    return false;
  }
  // completed AI commits with their messages, newest first — the breakdown card
  readonly property var recentCommits: {
    var out = [];
    for (var i = 0; i < activity.length; i++) {
      var a = activity[i];
      if (a.state === "done" && a.commits && a.commits.length)
        out.push(a);
    }
    return out;
  }

  // ── bar presentation ────────────────────────────────────────────────────────
  // the official Git logo carries liveness: its own orange when the scanner runs,
  // grey when it can't; the count label (stateColor) carries clean/pending/behind.
  readonly property color logoColor: ok ? "#DE4C36" : Color.mOutline
  // git-commit in every state, chosen deliberately — do not make this
  // conditional again. The label and stateColor already carry
  // clean/pending/behind; swapping the silhouette on top of that only made the
  // icon look like it changed on its own as repos moved.
  readonly property string barIconName: "git-commit"
  readonly property string barLabel: {
    if (!ok)
      return "…";
    return attention > 0 ? String(attention) : "✓";
  }
  // green clean · amber uncommitted/unpushed · red unpulled (someone moved ahead) or error
  readonly property color stateColor: {
    if (!ok)
      return Color.mError;
    if (!summary)
      return Color.mOnSurface;
    if (summary.behind > 0)
      return Color.mError;
    if (summary.ahead > 0 || summary.dirty > 0)
      return Color.mSecondary;
    return Color.mPrimary;
  }
  readonly property string tooltipText: {
    tick;
    if (!ok)
      return "git-status unavailable\n" + (errorText || "no data") + "\n" + command;
    if (!summary || summary.attention === 0)
      return summary ? (summary.total + " repos · all clean") : "…";
    return summary.attention + " of " + summary.total + " repos need attention\n" + summary.dirty + " uncommitted · " + summary.ahead + " to push · " + summary.behind + " to pull";
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

  // ── running the scan ──────────────────────────────────────────────────────
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
      root.errorText = "invalid JSON from git-status";
      Logger.w("git-status", "parse failed:", e);
    }
  }

  // ── actions ────────────────────────────────────────────────────────────────
  // push/pull go through `git-status <op>` so they raise a desktop notification
  // with the outcome (success/error) instead of failing silently.
  // push/pull are quick; show a spinner optimistically, cleared by the re-scan.
  property var busyOp: ({})   // path → "push" | "pull" while in flight
  function isBusy(path, op) {
    return busyOp[path] === op;
  }
  function _q(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
  }
  function _act(op, path) {
    var b = busyOp;
    b[path] = op;
    busyOp = b;      // reassign so the spinner shows immediately
    Quickshell.execDetached(["sh", "-c", root.binPath + " " + op + " " + _q(path)]);
    delayed.restart();
  }
  function pull(path) {
    _act("pull", path);
  }
  function push(path) {
    _act("push", path);
  }
  // fire a background Claude that stages properly, writes a conventional-commit
  // message and pushes; it reports state to ~/.cache/git-ai-commit + notifies.
  function aiCommit(path) {
    var w = localWorking;
    w[path] = Date.now() / 1000;
    localWorking = w;      // reassign so the spinner shows immediately
    Quickshell.execDetached(["sh", "-c", "git-ai-commit " + _q(path)]);
    root.refresh();        // pick up the "running" state promptly
  }
  function openTerminal(path) {
    Quickshell.execDetached([terminalCmd, "--directory", path]);
  }
  // wipe the recorded AI-commit history (the breakdown card)
  function clearActivity() {
    Quickshell.execDetached(["sh", "-c", root.binPath + " clear"]);
    root.refresh();
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

    onExited: (exitCode, exitStatus) => {
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
  // push/pull settle before we re-scan; also clears their spinners
  Timer {
    id: delayed
    interval: 4000
    onTriggered: {
      root.busyOp = ({});
      root.refresh();
    }
  }
  // while an AI commit is running, poll fast so the spinner clears + the commit
  // breakdown appears the moment it finishes (~30–60s)
  Timer {
    id: fastPoll
    interval: 4000
    repeat: true
    running: root.anyWorking
    onTriggered: root.refresh()
  }
  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.tick++
  }

  Component.onCompleted: Logger.i("git-status", "plugin started, running:", command)
}
