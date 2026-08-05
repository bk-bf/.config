// Panel.qml — the detail view opened by clicking the bar pill.
//
// Layout: a two-column top row (trigger state beside a square system tracker),
// then full-width stacked cards, then the pit crew as a two-column grid.
//
// SESSIONS shows four rows and hides the rest behind a toggle — the list is
// unbounded and a panel that grows with your history is unusable.
//
// Titles come from herdr where the session lives in a pane, because that is the
// title Claude actually generated for it; otherwise they are derived from the
// first prompt. A session in a herdr pane is FOCUSED rather than reopened —
// launching herdr inside herdr is refused ("nested herdr is disabled").
//
// Every card is an opaque NBox: noctalia honours a user-set panel background
// opacity, so anything placed straight on the panel is unreadable over a busy
// wallpaper.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi
  readonly property var svc: pluginApi ? pluginApi.mainInstance : null

  property int contentPreferredWidth: 620
  property int contentPreferredHeight: Math.min(880, col.implicitHeight + Style.marginL * 2)
  property color panelBackgroundColor: Color.mSurface

  readonly property color cMuted: Color.mOnSurfaceVariant
  property bool showAllSessions: false

  readonly property int sessionCount: svc ? svc.sessions.length : 0
  readonly property var shownSessions: {
    if (!svc)
      return [];
    return showAllSessions ? svc.sessions : svc.sessions.slice(0, 4);
  }

  function agentColor(a) {
    var idle = svc ? svc.idleOf(a) : -1;
    if (idle < 0)
      return Color.mSecondary;
    return idle > (svc ? svc.idleWarnSec : 300) ? Color.mError : Color.mPrimary;
  }

  ColumnLayout {
    id: col
    x: Style.marginL
    y: Style.marginL
    width: root.width - Style.marginL * 2
    spacing: Style.marginM

    // ── top row: trigger state | system tracker ──────────────────────────────
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: 132
        forceOpaque: true

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: 2

          NText {
            text: "TRIGGER"
            pointSize: Style.fontSizeXS
            font.weight: Style.fontWeightSemiBold
            color: root.cMuted
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
                  font.weight: Style.fontWeightSemiBold
                  color: Color.mOnSurface
                }
                NText {
                  text: modelData.armed ? "armed" : "NOT ARMED"
                  pointSize: Style.fontSizeXS
                  color: modelData.armed ? root.cMuted : Color.mError
                }
              }
              NText {
                Layout.fillWidth: true
                text: "starts an agent when: " + ((modelData.watches || []).join(", ") || "nothing")
                pointSize: Style.fontSizeXS
                color: root.cMuted
                wrapMode: Text.WordWrap
              }
              NText {
                Layout.fillWidth: true
                text: modelData.authority + " · " + (modelData.model || "")
                pointSize: Style.fontSizeXS
                color: modelData.authority === "read-only" ? Color.mSecondary : root.cMuted
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
          Item {
            Layout.fillHeight: true
          }
        }
      }

      // The square tracker: the whole system in a handful of numbers.
      NBox {
        Layout.preferredWidth: 132
        Layout.preferredHeight: 132
        forceOpaque: true

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: 1

          NText {
            text: "SYSTEM"
            pointSize: Style.fontSizeXS
            font.weight: Style.fontWeightSemiBold
            color: root.cMuted
          }
          NText {
            Layout.alignment: Qt.AlignHCenter
            text: svc ? String(svc.runningCount) : "–"
            pointSize: Style.fontSizeXXL
            font.weight: Style.fontWeightBold
            color: svc && svc.runningCount > 0 ? Color.mPrimary : root.cMuted
          }
          NText {
            Layout.alignment: Qt.AlignHCenter
            text: "agents running"
            pointSize: Style.fontSizeXS
            color: root.cMuted
          }
          Item {
            Layout.fillHeight: true
          }
          NText {
            Layout.fillWidth: true
            text: root.sessionCount + " sessions"
            pointSize: Style.fontSizeXS
            color: root.cMuted
          }
          NText {
            Layout.fillWidth: true
            text: {
              if (!svc || !svc.triggers.length)
                return "no trigger";
              var b = svc.triggers[0].budget || {};
              return "budget " + (b.used !== undefined ? b.used : "?") + "/" + (b.cap !== undefined ? b.cap : "?");
            }
            pointSize: Style.fontSizeXS
            color: root.cMuted
          }
          NText {
            Layout.fillWidth: true
            text: svc ? (svc.alerts.length + " alert" + (svc.alerts.length === 1 ? "" : "s")) : ""
            pointSize: Style.fontSizeXS
            color: svc && svc.alerts.length ? Color.mError : root.cMuted
          }
        }
      }
    }

    // ── sessions ─────────────────────────────────────────────────────────────
    RowLayout {
      Layout.fillWidth: true
      NText {
        text: "SESSIONS"
        pointSize: Style.fontSizeXS
        font.weight: Style.fontWeightSemiBold
        color: root.cMuted
      }
      Item {
        Layout.fillWidth: true
      }
      NText {
        visible: root.sessionCount > 4
        text: root.showAllSessions ? "show less" : ("show all " + root.sessionCount)
        pointSize: Style.fontSizeXS
        color: Color.mPrimary

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.showAllSessions = !root.showAllSessions
        }
      }
    }

    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      implicitHeight: sessCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: sessCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        NText {
          Layout.fillWidth: true
          visible: root.sessionCount === 0
          text: "No sessions on disk."
          pointSize: Style.fontSizeXS
          color: root.cMuted
        }

        Repeater {
          model: root.shownSessions
          delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            Rectangle {
              Layout.alignment: Qt.AlignVCenter
              implicitWidth: 8
              implicitHeight: 8
              radius: 4
              color: modelData.agent_status === "working" ? Color.mPrimary : (modelData.live ? Color.mSecondary : root.cMuted)
            }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              NText {
                Layout.fillWidth: true
                text: modelData.title && modelData.title !== "" ? modelData.title : (modelData.session_id || "").substring(0, 8)
                pointSize: Style.fontSizeXS
                color: modelData.exists ? Color.mOnSurface : root.cMuted
                elide: Text.ElideRight
              }
              NText {
                Layout.fillWidth: true
                text: (modelData.project || "?") + (modelData.pane_id ? "  ·  in herdr" : "")
                pointSize: Style.fontSizeXS
                color: root.cMuted
                elide: Text.ElideMiddle
              }
            }
            NText {
              text: svc ? svc.fmtAgo(modelData.age_sec) : ""
              pointSize: Style.fontSizeXS
              color: root.cMuted
              Layout.preferredWidth: 40
              horizontalAlignment: Text.AlignRight
            }
            // In a herdr pane → focus it, which is a true foreground switch and
            // avoids launching herdr inside herdr. Otherwise reopen it in a
            // terminal. A live session is never resumed: that would put a
            // second writer on its transcript.
            NIconButton {
              icon: "trash"
              baseSize: Style.baseWidgetSize * 0.5
              enabled: !modelData.live
              opacity: enabled ? 0.7 : 0.25
              tooltipText: enabled ? "Delete this session" : "cannot delete a running session"
              onClicked: {
                if (svc)
                  svc.removeSession(modelData.session_id);
              }
            }
            NIconButton {
              icon: modelData.pane_id ? "arrow-right" : (modelData.live ? "eye" : "player-play")
              baseSize: Style.baseWidgetSize * 0.55
              tooltipText: modelData.pane_id ? "Jump to this session in herdr" : (modelData.live ? "Watch this session's output" : "Reopen in a terminal")
              onClicked: {
                if (!svc)
                  return;
                if (modelData.pane_id)
                  svc.focusPane(modelData.pane_id);
                else if (modelData.live)
                  svc.followAgent(modelData.session_id);
                else
                  svc.resumeSession(modelData.session_id, modelData.cwd);
              }
            }
          }
        }
      }
    }

    // ── agents running ───────────────────────────────────────────────────────
    NText {
      visible: svc && svc.runningCount > 0
      text: "AGENTS RUNNING"
      pointSize: Style.fontSizeXS
      font.weight: Style.fontWeightSemiBold
      color: root.cMuted
    }

    NBox {
      Layout.fillWidth: true
      visible: svc && svc.runningCount > 0
      forceOpaque: true
      implicitHeight: runCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: runCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

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
              pointSize: Style.fontSizeXS
              color: Color.mOnSurface
              elide: Text.ElideMiddle
            }
            NText {
              text: svc ? ("up " + svc.fmtAgo(modelData.runtime_sec)) : ""
              pointSize: Style.fontSizeXS
              color: root.cMuted
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
            }
            NIconButton {
              icon: "eye"
              baseSize: Style.baseWidgetSize * 0.55
              enabled: !!modelData.session_id
              opacity: enabled ? 1 : 0.35
              tooltipText: "Watch this agent's output"
              onClicked: {
                if (svc)
                  svc.followAgent(modelData.session_id);
              }
            }
          }
        }
      }
    }

    // ── triage results ───────────────────────────────────────────────────────
    NText {
      visible: svc && svc.recent.length > 0
      text: "TRIAGE RESULTS"
      pointSize: Style.fontSizeXS
      font.weight: Style.fontWeightSemiBold
      color: root.cMuted
    }

    NBox {
      Layout.fillWidth: true
      visible: svc && svc.recent.length > 0
      forceOpaque: true
      implicitHeight: recCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: recCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        Repeater {
          model: svc ? svc.recent.slice(0, 4) : []
          delegate: RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            NText {
              text: modelData.verdict === "fixed" ? "✓" : (modelData.verdict === "needs-human" ? "✋" : "·")
              color: modelData.verdict === "fixed" ? Color.mPrimary : (modelData.verdict === "needs-human" ? Color.mError : root.cMuted)
              pointSize: Style.fontSizeXS
              Layout.preferredWidth: 14
            }
            NText {
              Layout.fillWidth: true
              text: modelData.summary || modelData.subject || ""
              pointSize: Style.fontSizeXS
              color: root.cMuted
              elide: Text.ElideRight
            }
            NIconButton {
              icon: "trash"
              baseSize: Style.baseWidgetSize * 0.5
              opacity: 0.7
              tooltipText: "Delete this result"
              onClicked: {
                if (svc)
                  svc.removeRun(modelData.id);
              }
            }
            NIconButton {
              icon: "player-play"
              baseSize: Style.baseWidgetSize * 0.55
              enabled: svc ? svc.canResume(modelData) : false
              opacity: enabled ? 1 : 0.3
              tooltipText: enabled ? "Reopen this run" : "no session id recorded"
              onClicked: {
                if (svc)
                  svc.resumeSession(modelData.session_id, modelData.cwd);
              }
            }
          }
        }
      }
    }

    // ── scripts ─────────────────────────────────────────────────────────────
    NText {
      text: "SCRIPTS"
      pointSize: Style.fontSizeXS
      font.weight: Style.fontWeightSemiBold
      color: root.cMuted
    }

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.marginM
      rowSpacing: Style.marginM

      Repeater {
        model: svc ? svc.jobs : []
        delegate: NBox {
          Layout.fillWidth: true
          Layout.preferredHeight: crewCol.implicitHeight + Style.marginM * 2
          forceOpaque: true

          ColumnLayout {
            id: crewCol
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: 1

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              // A plain dot, not a pill. A pill has to size itself around its
              // own label, and the label clipped out of it as the state text
              // grew.
              Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 8
                implicitHeight: 8
                radius: 4
                color: modelData.ok ? Color.mPrimary : Color.mError
              }
              NText {
                Layout.fillWidth: true
                text: modelData.name
                pointSize: Style.fontSizeXS
                font.weight: Style.fontWeightSemiBold
                color: Color.mOnSurface
                elide: Text.ElideRight
              }
              NIconButton {
                icon: "trash"
                baseSize: Style.baseWidgetSize * 0.5
                opacity: 0.7
                tooltipText: "Stop and disable this script"
                onClicked: {
                  if (svc)
                    svc.disableJob(modelData.unit);
                }
              }
              NIconButton {
                icon: "edit"
                baseSize: Style.baseWidgetSize * 0.5
                enabled: !!modelData.script
                opacity: enabled ? 1 : 0.3
                tooltipText: modelData.script || "no script for this unit"
                onClicked: {
                  if (svc)
                    svc.openScript(modelData.script);
                }
              }
            }
            NText {
              Layout.fillWidth: true
              text: modelData.ok ? "online" : (modelData.state || "failing")
              pointSize: Style.fontSizeXS
              color: modelData.ok ? Color.mPrimary : Color.mError
            }
            // The plain sentence, not the journal line. Raw log text tells you
            // the mechanism and leaves you to work out both what it means and
            // what to do about it.
            NText {
              Layout.fillWidth: true
              visible: !modelData.ok && modelData.problem
              text: modelData.problem || ""
              pointSize: Style.fontSizeXS
              color: Color.mError
              wrapMode: Text.WordWrap
              maximumLineCount: 3
              elide: Text.ElideRight
            }
            NButton {
              Layout.fillWidth: true
              visible: !modelData.ok && modelData.action && modelData.action.label
              text: (modelData.action && modelData.action.label) || ""
              onClicked: {
                if (svc && modelData.action)
                  svc.runAction(modelData.action.cmd, modelData.action.cwd);
              }
            }
          }
        }
      }
    }
  }
}
