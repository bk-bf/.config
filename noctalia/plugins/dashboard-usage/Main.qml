// Main.qml — the plugin's single data source and shared state.
//
// This addon owns no data of its own: it polls the dashboard server's
// /api/usage endpoint (exactly the payload the Svelte UI consumes) and exposes
// the parsed result plus display-ready strings. BarWidget.qml and Panel.qml
// both read this instance through pluginApi.mainInstance, so there is one timer
// and one in-flight request no matter how many bars/screens show the widget.
//
// Everything user-visible is derived here as a *property* rather than a
// function, so QML's binding engine re-evaluates the bar label the moment new
// JSON lands.

import QtQuick
import Quickshell
import qs.Commons

Item {
  id: root

  // Injected by PluginService when the entry point is instantiated.
  property var pluginApi

  // ── settings ────────────────────────────────────────────────────────────────
  // PluginService merges manifest metadata.defaultSettings underneath the saved
  // settings, so these resolve even on a fresh install.
  readonly property var cfg: pluginApi ? pluginApi.pluginSettings : ({})
  readonly property string baseUrl: String((cfg && cfg.baseUrl) || "").replace(/\/+$/, "")
  readonly property int intervalMs: Math.max(5000, (cfg && cfg.intervalMs) || 30000)
  readonly property string barMetric: (cfg && cfg.barMetric) || "auto"
  readonly property int warnPct: (cfg && cfg.warnPct) || 75
  readonly property int critPct: (cfg && cfg.critPct) || 90
  readonly property bool colorBySeverity: (cfg && cfg.colorBySeverity !== undefined) ? cfg.colorBySeverity : true

  // ── state ───────────────────────────────────────────────────────────────────
  property var payload: null // last good /api/usage body
  property string errorText: ""
  property bool loading: false
  property double lastOkMs: 0

  readonly property bool ok: payload !== null && errorText === ""

  readonly property var activeWindow: (payload && payload.active_window) || null
  readonly property var limits: (payload && payload.limits) || null
  readonly property var plan: (payload && payload.plan) || null
  readonly property var sources: (payload && payload.sources) || []

  // ── nightshift + git (the dashboard's other two tabs) ───────────────────────
  // Polled alongside usage so the panel can break down all three services. Each
  // is best-effort: a missing/erroring endpoint just leaves its card hidden.
  property var agents: null       // /api/agents  (governor + shift + status)
  property var proposals: null    // /api/agents/proposals
  property var effect: null       // /api/agents/effect
  property var commits: null      // /api/commits?range=rolling

  readonly property var shift: (agents && agents.shift) || null
  readonly property var governor: (agents && agents.governor) || null
  readonly property var nsStatus: (agents && agents.status) || null
  readonly property bool nsHave: agents !== null
  readonly property bool shiftOn: shift ? !!shift.master_enabled : false
  readonly property bool nsAllow: governor ? governor.allow === true : false
  readonly property string nsReason: governor ? (governor.reason || "") : ""
  readonly property var nsNext: governor ? governor.next : null
  readonly property var nsRunTimes: (shift && shift.run_times) || []
  readonly property int nsWeeklyPct: (governor && governor.weekly_pct !== null && governor.weekly_pct !== undefined) ? Math.round(governor.weekly_pct) : -1
  readonly property int nsWindowPct: (governor && governor.window_pct !== null && governor.window_pct !== undefined) ? Math.round(governor.window_pct) : -1
  readonly property int nsRuns: (nsStatus && nsStatus.totals) ? (nsStatus.totals.runs || 0) : 0
  readonly property var nsLastRun: (nsStatus && nsStatus.recent_runs && nsStatus.recent_runs.length) ? nsStatus.recent_runs[0] : null
  readonly property int nsPending: (proposals && proposals.items) ? proposals.items.length : 0
  readonly property var effectItems: (effect && effect.items) || []
  function effectCount(t) {
    var n = 0;
    for (var i = 0; i < effectItems.length; i++)
      if (effectItems[i].type === t)
        n++;
    return n;
  }

  // git productivity — the endpoint returns ~12 months; window it to a recent
  // slice client-side (the Git tab does the same) so the numbers mean "lately".
  readonly property var gitCommits: (commits && commits.commits) || []
  readonly property int gitWindowDays: 30
  readonly property double _gitCutoff: Date.now() - gitWindowDays * 86400000
  readonly property int gitCommitCount: {
    var n = 0;
    for (var i = 0; i < gitCommits.length; i++) {
      var t = parseIso(gitCommits[i].ts);
      if (t && t >= _gitCutoff)
        n++;
    }
    return n;
  }
  readonly property int gitActiveDays: {
    var days = {};
    for (var i = 0; i < gitCommits.length; i++) {
      var t = parseIso(gitCommits[i].ts);
      if (t && t >= _gitCutoff) {
        var d = new Date(t);
        days[d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate()] = 1;
      }
    }
    return Object.keys(days).length;
  }
  readonly property int gitRepoCount: {
    var r = {};
    for (var i = 0; i < gitCommits.length; i++) {
      var t = parseIso(gitCommits[i].ts);
      if (t && t >= _gitCutoff && gitCommits[i].repo)
        r[gitCommits[i].repo] = 1;
    }
    return Object.keys(r).length;
  }
  readonly property double gitLastMs: {
    var m = 0;
    for (var i = 0; i < gitCommits.length; i++) {
      var t = parseIso(gitCommits[i].ts);
      if (t && t > m)
        m = t;
    }
    return m;
  }

  // Headline percentage: prefer Anthropic's own plan number when the server has
  // it; otherwise fall back to the user's configured USD cap for the 5h window
  // (there is no plan-quota API, so those caps live in the server's config.json).
  readonly property var headlinePct: {
    if (plan && plan.five_hour && plan.five_hour.pct !== null && plan.five_hour.pct !== undefined)
      return plan.five_hour.pct;
    if (limits && limits.window_5h && limits.window_5h.pct !== null && limits.window_5h.pct !== undefined)
      return limits.window_5h.pct;
    return null;
  }

  // 0 fine · 1 warn · 2 critical · 3 no data / unreachable
  readonly property int severity: {
    if (!ok)
      return 3;
    var p = headlinePct;
    if (p === null || p === undefined)
      return 0;
    if (p >= critPct)
      return 2;
    if (p >= warnPct)
      return 1;
    return 0;
  }

  // Tint for the pill's *label* as a limit is approached. The logo carries
  // liveness (orange/grey); this carries "how close am I to being cut off".
  readonly property color severityColor: {
    switch (severity) {
    case 2:
      return Color.mError;
    case 1:
      return Color.mSecondary;
    default:
      return Color.mOnSurface;
    }
  }

  // Claude's own orange, used literally rather than via a palette token so the
  // mark stays recognisable under any colour scheme. Grey when the server is
  // not answering — the logo doubles as the liveness indicator.
  readonly property color colorLive: "#d97757"
  readonly property color logoColor: ok ? colorLive : Color.mOutline

  // Ticks so relative timestamps ("updated 2m ago") keep counting up without a
  // new fetch. Bindings that want live ages read `tick` to register a dependency.
  property int tick: 0

  // ── formatting helpers (also used by Panel.qml) ─────────────────────────────
  function fmtMoney(v) {
    if (v === null || v === undefined || isNaN(v))
      return "—";
    var n = Number(v);
    if (n >= 100)
      return "$" + n.toFixed(0);
    if (n >= 10)
      return "$" + n.toFixed(1);
    return "$" + n.toFixed(2);
  }

  function fmtPct(v) {
    return (v === null || v === undefined || isNaN(v)) ? "—" : Math.round(Number(v)) + "%";
  }

  function fmtTokens(n) {
    if (n === null || n === undefined || isNaN(n))
      return "—";
    var v = Number(n);
    if (v >= 1e9)
      return (v / 1e9).toFixed(2) + "B";
    if (v >= 1e6)
      return (v / 1e6).toFixed(1) + "M";
    if (v >= 1e3)
      return (v / 1e3).toFixed(0) + "k";
    return String(Math.round(v));
  }

  readonly property var tokensUsed: activeWindow ? activeWindow.totalTokens : null

  // The server emits timestamps like 2026-07-23T06:39:59.589520+00:00. Date
  // parsing is only specified for three fractional digits, so trim the rest
  // rather than risk an implementation-dependent NaN.
  function parseIso(s) {
    if (!s)
      return null;
    var ms = Date.parse(String(s).replace(/(\.\d{3})\d+/, "$1"));
    return isNaN(ms) ? null : ms;
  }

  function fmtResetIn(iso) {
    var ms = parseIso(iso);
    if (ms === null)
      return "";
    var mins = Math.round((ms - Date.now()) / 60000);
    if (mins <= 0)
      return "resetting";
    // Weekly windows sit days out; minutes at that distance are noise.
    if (mins >= 1440) {
      var d = Math.floor(mins / 1440);
      var hh = Math.round((mins % 1440) / 60);
      if (hh === 24) {
        d += 1;
        hh = 0;
      }
      return "resets in " + d + "d" + (hh < 10 ? "0" : "") + hh + "h";
    }
    return "resets in " + fmtMinutes(mins);
  }

  function fmtMinutes(m) {
    if (m === null || m === undefined || isNaN(m))
      return "—";
    var t = Math.max(0, Math.round(Number(m)));
    var h = Math.floor(t / 60);
    var mm = t % 60;
    return h > 0 ? (h + "h" + (mm < 10 ? "0" : "") + mm + "m") : (mm + "m");
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
    tick; // dependency: re-evaluate on each tick
    return fmtAge(lastOkMs);
  }

  // ── bar presentation ────────────────────────────────────────────────────────
  readonly property string barLabel: {
    if (!ok)
      return "offline";
    var w = activeWindow;
    switch (barMetric) {
    case "tokens":
      return fmtTokens(tokensUsed);
    case "spend":
      return fmtMoney(w ? w.costUSD : null);
    case "burn":
      return (w && w.costPerHour) ? (fmtMoney(w.costPerHour) + "/h") : "idle";
    case "projected":
      return fmtMoney(w ? w.projectedCostUSD : null);
    case "remaining":
      return fmtMinutes(w ? w.remainingMinutes : null);
    case "plan":
      return fmtPct(headlinePct);
    default:
      // auto — the plan/cap percentage is the most actionable number when the
      // server has one; otherwise show what this window has actually cost.
      if (headlinePct !== null && headlinePct !== undefined)
        return fmtPct(headlinePct);
      return fmtMoney(w ? w.costUSD : null);
    }
  }

  readonly property string tooltipText: {
    tick;
    if (!ok)
      return "Dashboard unreachable\n" + (errorText || "no data") + "\n" + (baseUrl || "no URL configured");
    var w = activeWindow;
    var lines = [];
    lines.push("5-hour window" + (w && w.host ? "  ·  " + w.host : ""));
    if (w) {
      lines.push("spent " + fmtMoney(w.costUSD) + "   projected " + fmtMoney(w.projectedCostUSD));
      if (w.costPerHour)
        lines.push("burn " + fmtMoney(w.costPerHour) + "/h   " + fmtMinutes(w.remainingMinutes) + " left");
    } else {
      lines.push("no active window");
    }
    if (headlinePct !== null && headlinePct !== undefined)
      lines.push("plan " + fmtPct(headlinePct));
    lines.push("updated " + fmtAge(lastOkMs));
    return lines.join("\n");
  }

  // ── fetching ────────────────────────────────────────────────────────────────
  // force=true appends ?sync=1, which makes the aggregator skip its
  // stale-while-revalidate cache and pull every collector now.
  function refresh(force) {
    if (loading)
      return;
    if (!baseUrl) {
      errorText = "no dashboard URL configured";
      return;
    }
    loading = true;
    var url = baseUrl + "/api/usage" + (force ? "?sync=1" : "");
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return;
      root.loading = false;
      if (xhr.status === 200) {
        try {
          root.payload = JSON.parse(xhr.responseText);
          root.errorText = "";
          root.lastOkMs = Date.now();
        } catch (e) {
          root.errorText = "invalid JSON from server";
          Logger.w("dashboard-usage", "parse failed:", e);
        }
      } else {
        // status 0 == connection refused / DNS failure / TLS error
        root.errorText = (xhr.status === 0) ? "unreachable" : ("HTTP " + xhr.status);
      }
    };
    try {
      xhr.open("GET", url);
      xhr.send();
    } catch (e) {
      root.loading = false;
      root.errorText = String(e);
    }
  }

  // Best-effort GET of a secondary endpoint → assign the parsed body to a
  // property (or null on any failure). These never touch errorText/loading, so
  // a nightshift/git hiccup can't make the whole widget read "offline".
  function _getJson(path, apply) {
    if (!baseUrl)
      return;
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return;
      if (xhr.status === 200) {
        try {
          apply(JSON.parse(xhr.responseText));
        } catch (e) {
          Logger.w("dashboard-usage", "extra parse failed", path, e);
        }
      } else {
        apply(null);
      }
    };
    try {
      xhr.open("GET", baseUrl + path);
      xhr.send();
    } catch (e) {}
  }

  // nightshift + git-productivity, polled together with the usage refresh.
  function refreshExtras() {
    _getJson("/api/agents", function (j) {
      root.agents = j;
    });
    _getJson("/api/agents/proposals", function (j) {
      root.proposals = j;
    });
    _getJson("/api/agents/effect", function (j) {
      root.effect = j;
    });
    _getJson("/api/commits?range=rolling", function (j) {
      root.commits = j;
    });
  }

  function openInBrowser() {
    if (baseUrl)
      Quickshell.execDetached(["xdg-open", baseUrl]);
  }

  function openTab(tab) {
    if (baseUrl)
      Quickshell.execDetached(["xdg-open", baseUrl + "/" + (tab || "")]);
  }

  onBaseUrlChanged: {
    payload = null;
    errorText = "";
    refresh(false);
    refreshExtras();
  }

  Timer {
    interval: root.intervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refresh(false);
      root.refreshExtras();
    }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.tick++
  }

  Component.onCompleted: Logger.i("dashboard-usage", "plugin started, polling", baseUrl)
}
