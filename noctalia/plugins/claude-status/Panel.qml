// Panel.qml — the detail view opened by clicking the bar pill.
//
// Ordered by what you cannot find out any other way:
//   1. TRIGGERS  — what is armed to start an agent. If nothing is watching,
//                  nothing will tell you that; it has to be the first thing.
//   2. AGENTS    — background runs happening now, and whether each is actually
//                  producing output. A wedged headless run has the same uptime
//                  and memory as a working one; only its transcript separates
//                  them, so "last output" gets its own column and drives the dot.
//   3. RUNS      — what recent agents concluded, and what they cost.
//   4. JOBS      — the Claude housekeeping that does NOT start agents, listed
//                  separately so it never inflates the trigger count. A failing
//                  one is usually what produces the incident a trigger reacts to.
//
// Interactive sessions are a one-line footnote on purpose. You are looking at
// those already; they are not what this panel is for.
//
// Every section sits inside an opaque NBox. Noctalia panels honour a
// user-configured background opacity, so content placed directly on the panel
// shows the desktop through it and becomes unreadable over a busy wallpaper.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi
  readonly property var svc: pluginApi ? pluginApi.mainInstance : null

  property int contentPreferredWidth: 580
  property int contentPreferredHeight: Math.min(860, col.implicitHeight + Style.marginL * 2)
  property color panelBackgroundColor: Color.mSurface

  readonly property color cMuted: Color.mOnSurfaceVariant

  function agentColor(a) {
    var idle = svc ? svc.idleOf(a) : -1;
    if (idle < 0)
      return Color.mSecondary;
    return idle > (svc ? svc.idleWarnSec : 300) ? Color.mError : Color.mPrimary;
  }

  function verdictIcon(v) {
    return v === "fixed" ? "✓" : (v === "needs-human" ? "✋" : (v === "still failing" ? "✗" : "·"));
  }
  function verdictColor(v) {
    return v === "fixed" ? Color.mPrimary : ((v === "needs-human" || v === "still failing") ? Color.mError : root.cMuted);
  }

  ColumnLayout {
    id: col
    x: Style.marginL
    y: Style.marginL
    width: root.width - Style.marginL * 2
    spacing: Style.marginM

    // ── header ───────────────────────────────────────────────────────────────
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NText {
        text: "Background agents"
        pointSize: Style.fontSizeL
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
      }
      Item {
        Layout.fillWidth: true
      }
      NIconButton {
        icon: "refresh"
        baseSize: Style.baseWidgetSize * 0.7
        onClicked: {
          if (svc)
            svc.refresh();
        }
      }
    }

    // ── alerts ───────────────────────────────────────────────────────────────
    NBox {
      Layout.fillWidth: true
      visible: svc && svc.alerts.length > 0
      forceOpaque: true
      implicitHeight: alertCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: alertCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        Repeater {
          model: svc ? svc.alerts : []
          delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            NText {
              text: "!"
              color: Color.mError
              font.weight: Style.fontWeightBold
              pointSize: Style.fontSizeS
            }
            NText {
              Layout.fillWidth: true
              text: modelData
              pointSize: Style.fontSizeXS
              color: Color.mOnSurface
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }

    // ── 1. triggers ──────────────────────────────────────────────────────────
    NText {
      text: "TRIGGERS"
      pointSize: Style.fontSizeXS
      font.weight: Style.fontWeightSemiBold
      color: root.cMuted
    }

    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      implicitHeight: trgCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: trgCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginS

        NText {
          Layout.fillWidth: true
          visible: svc && svc.triggers.length === 0
          text: "Nothing is wired to start an agent."
          pointSize: Style.fontSizeXS
          color: Color.mError
        }

        Repeater {
          model: svc ? svc.triggers : []
          delegate: ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 8
                implicitHeight: 8
                radius: 4
                color: modelData.armed ? Color.mPrimary : Color.mError
              }
              NText {
                text: modelData.name
                pointSize: Style.fontSizeS
                color: Color.mOnSurface
                font.weight: Style.fontWeightSemiBold
              }
              NText {
                text: modelData.armed ? "armed" : "NOT ARMED"
                pointSize: Style.fontSizeXS
                color: modelData.armed ? root.cMuted : Color.mError
              }
              Item {
                Layout.fillWidth: true
              }
              NText {
                text: modelData.authority || ""
                pointSize: Style.fontSizeXS
                color: root.cMuted
              }
            }
            NText {
              Layout.fillWidth: true
              text: modelData.via || ""
              pointSize: Style.fontSizeXS
              color: root.cMuted
            }
            NText {
              Layout.fillWidth: true
              text: "watches " + ((modelData.watches || []).join(", ") || "nothing")
              pointSize: Style.fontSizeXS
              color: root.cMuted
              wrapMode: Text.WordWrap
            }
            NText {
              Layout.fillWidth: true
              text: {
                var b = modelData.budget || {};
                return "budget " + (b.used !== undefined ? b.used : "?") + "/" + (b.cap !== undefined ? b.cap : "?") + " today · cooldown " + (modelData.cooldown_min || "?") + "min · " + (modelData.model || "");
              }
              pointSize: Style.fontSizeXS
              color: root.cMuted
            }
            NText {
              Layout.fillWidth: true
              visible: !modelData.armed && modelData.why
              text: modelData.why || ""
              pointSize: Style.fontSizeXS
              color: Color.mError
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }

    // ── 2. agents running ────────────────────────────────────────────────────
    NText {
      text: svc ? ("AGENTS RUNNING · " + svc.runningCount) : "AGENTS RUNNING"
      pointSize: Style.fontSizeXS
      font.weight: Style.fontWeightSemiBold
      color: root.cMuted
    }

    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      implicitHeight: runCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: runCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        NText {
          Layout.fillWidth: true
          visible: svc && svc.runningCount === 0
          text: "None. Nothing is running unattended right now."
          pointSize: Style.fontSizeXS
          color: root.cMuted
        }

        Repeater {
          model: svc ? svc.running : []
          delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            Rectangle {
              Layout.alignment: Qt.AlignVCenter
              implicitWidth: 8
              implicitHeight: 8
              radius: 4
              color: root.agentColor(modelData)
            }
            NText {
              Layout.fillWidth: true
              text: modelData.project || "?"
              pointSize: Style.fontSizeS
              color: Color.mOnSurface
              elide: Text.ElideMiddle
            }
            NText {
              text: svc ? ("up " + svc.fmtAgo(modelData.runtime_sec)) : ""
              pointSize: Style.fontSizeXS
              color: root.cMuted
              Layout.preferredWidth: 52
              horizontalAlignment: Text.AlignRight
            }
            NText {
              text: svc ? svc.fmtMb(modelData.rss_mb) : ""
              pointSize: Style.fontSizeXS
              color: root.cMuted
              Layout.preferredWidth: 48
              horizontalAlignment: Text.AlignRight
            }
            NText {
              text: {
                if (!svc)
                  return "";
                var idle = svc.idleOf(modelData);
                return idle < 0 ? "no output" : ("out " + svc.fmtAgo(idle));
              }
              pointSize: Style.fontSizeXS
              color: root.agentColor(modelData)
              Layout.preferredWidth: 76
              horizontalAlignment: Text.AlignRight
            }
            // A live agent is headless — there is no terminal to attach to, so
            // this follows its transcript instead of pretending to join it.
            NIconButton {
              icon: "eye"
              baseSize: Style.baseWidgetSize * 0.55
              enabled: !!modelData.session_id
              opacity: enabled ? 1 : 0.35
              tooltipText: "Follow this agent's output"
              onClicked: {
                if (svc)
                  svc.followAgent(modelData.session_id);
              }
            }
          }
        }
      }
    }

    // ── 3. recent runs ───────────────────────────────────────────────────────
    NText {
      text: "RECENT RUNS"
      pointSize: Style.fontSizeXS
      font.weight: Style.fontWeightSemiBold
      color: root.cMuted
    }

    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      implicitHeight: recCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: recCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        NText {
          Layout.fillWidth: true
          visible: svc && svc.recent.length === 0
          text: "No agent has run yet."
          pointSize: Style.fontSizeXS
          color: root.cMuted
        }

        Repeater {
          model: svc ? svc.recent.slice(0, 5) : []
          delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NText {
              text: root.verdictIcon(modelData.verdict)
              color: root.verdictColor(modelData.verdict)
              pointSize: Style.fontSizeS
              Layout.preferredWidth: 16
            }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              NText {
                Layout.fillWidth: true
                text: modelData.subject || "?"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                elide: Text.ElideMiddle
              }
              NText {
                Layout.fillWidth: true
                text: modelData.summary || ""
                pointSize: Style.fontSizeXS
                color: root.cMuted
                elide: Text.ElideRight
              }
            }
            NText {
              text: modelData.cost_usd ? ("$" + modelData.cost_usd.toFixed(2)) : "—"
              pointSize: Style.fontSizeXS
              color: root.cMuted
              Layout.preferredWidth: 44
              horizontalAlignment: Text.AlignRight
            }
            // Reopen a finished run as a real interactive session, in the
            // directory it ran in. Runs from before session ids were recorded
            // have nothing to resume, so the button greys out rather than
            // silently doing nothing.
            NIconButton {
              icon: "player-play"
              baseSize: Style.baseWidgetSize * 0.55
              enabled: svc ? svc.canResume(modelData) : false
              opacity: enabled ? 1 : 0.3
              tooltipText: enabled ? "Resume this session in a terminal" : "no session id recorded for this run"
              onClicked: {
                if (svc)
                  svc.resumeSession(modelData.session_id, modelData.cwd);
              }
            }
            NIconButton {
              icon: "external-link"
              baseSize: Style.baseWidgetSize * 0.55
              tooltipText: "Open the full report"
              onClicked: {
                if (svc)
                  svc.openReport(modelData.id);
              }
            }
          }
        }
      }
    }

    // ── 4. jobs ──────────────────────────────────────────────────────────────
    NText {
      text: "CLAUDE JOBS · do not start agents"
      pointSize: Style.fontSizeXS
      font.weight: Style.fontWeightSemiBold
      color: root.cMuted
    }

    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      implicitHeight: jobCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: jobCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        Repeater {
          model: svc ? svc.jobs : []
          delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            NText {
              text: modelData.ok ? "✓" : "✗"
              color: modelData.ok ? Color.mPrimary : Color.mError
              pointSize: Style.fontSizeXS
              Layout.preferredWidth: 14
            }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              NText {
                Layout.fillWidth: true
                text: modelData.name
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
              }
              NText {
                Layout.fillWidth: true
                visible: !modelData.ok && modelData.detail
                text: modelData.detail || ""
                pointSize: Style.fontSizeXS
                color: Color.mError
                wrapMode: Text.WordWrap
              }
            }
            NText {
              text: modelData.state || ""
              pointSize: Style.fontSizeXS
              color: root.cMuted
            }
          }
        }
      }
    }

    // ── footnote ─────────────────────────────────────────────────────────────
    NText {
      Layout.fillWidth: true
      text: {
        if (!svc || !svc.interactive)
          return "";
        var d = svc.interactive.desktop;
        return svc.interactive.count + " interactive session(s) open" + (d ? " · Claude Desktop " + d.procs + " procs" : "") + " — not agents.";
      }
      pointSize: Style.fontSizeXS
      color: root.cMuted
      wrapMode: Text.WordWrap
    }
  }
}
