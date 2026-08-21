// Panel.qml — the detail view opened by clicking the bar pill.
//
// Ordered by what actually governs a working session: limits first (how close
// am I to being cut off), then tokens, and cost last. Cards are forced opaque
// rather than inheriting the panel's translucency, which keeps small figures
// legible over a busy wallpaper.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi
  readonly property var svc: pluginApi ? pluginApi.mainInstance : null

  property int contentPreferredWidth: 440
  property int contentPreferredHeight: Math.min(780, layout.implicitHeight + Style.marginL * 2)
  property color panelBackgroundColor: Color.mSurface

  // Only limits Anthropic actually enforces, each with the time until it
  // refreshes — that countdown is the number you act on. The USD figures under
  // `limits` are locally-invented caps from the server's config.json, not real
  // quotas, so they are deliberately not shown here.
  readonly property var gaugeModel: {
    var out = [];
    if (!svc || !svc.ok)
      return out;

    svc.tick; // re-evaluate so the reset countdowns keep ticking down

    var p = svc.plan;
    if (!p)
      return out;

    function push(obj, label) {
      if (obj && obj.pct !== null && obj.pct !== undefined)
        out.push({
                   "label": label,
                   "pct": obj.pct,
                   "resets": svc.fmtResetIn(obj.resets_at)
                 });
    }

    push(p.five_hour, "5-hour");
    push(p.seven_day, "7-day");
    push(p.seven_day_opus, "7-day Opus");
    push(p.seven_day_sonnet, "7-day Sonnet");

    // Per-model weekly windows the account carries (Fable today, more later).
    var scoped = p.scoped || [];
    for (var i = 0; i < scoped.length; i++) {
      var s = scoped[i];
      if (s && s.pct !== null && s.pct !== undefined)
        out.push({
                   "label": "7-day " + (s.model || "model"),
                   "pct": s.pct,
                   "resets": svc.fmtResetIn(s.resets_at)
                 });
    }
    return out;
  }

  function gaugeColor(pct) {
    if (!svc)
      return Color.mPrimary;
    if (pct >= svc.critPct)
      return Color.mError;
    if (pct >= svc.warnPct)
      return Color.mSecondary;
    return Color.mPrimary;
  }

  ColumnLayout {
    id: layout
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginS

    // ── header ───────────────────────────────────────────────────────────────
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      Rectangle {
        // liveness dot, same orange/grey as the bar logo
        width: 10
        height: 10
        radius: 5
        Layout.alignment: Qt.AlignVCenter
        color: root.svc ? root.svc.logoColor : Color.mOutline
      }

      ColumnLayout {
        spacing: 0
        Layout.fillWidth: true

        NText {
          text: "Dashboard"
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
        }
        NText {
          text: {
            if (!root.svc)
              return "";
            return root.svc.ok ? ("updated " + root.svc.lastOkLabel) : (root.svc.errorText || "no data");
          }
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      NIconButton {
        icon: "refresh"
        tooltipText: "Force a fresh pull from every collector"
        baseSize: Style.baseWidgetSize * 0.8
        onClicked: if (root.svc)
          root.svc.refresh(true)
      }
      NIconButton {
        icon: "external-link"
        tooltipText: "Open the dashboard in a browser"
        baseSize: Style.baseWidgetSize * 0.8
        onClicked: if (root.svc)
          root.svc.openInBrowser()
      }
    }

    // ── unreachable ──────────────────────────────────────────────────────────
    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      visible: root.svc !== null && !root.svc.ok
      implicitHeight: errCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: errCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXXS

        NText {
          text: "Can't reach the dashboard server"
          font.weight: Style.fontWeightSemiBold
          color: Color.mError
        }
        NText {
          text: root.svc ? (root.svc.baseUrl || "no URL configured") : ""
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
          elide: Text.ElideMiddle
          Layout.fillWidth: true
        }
      }
    }

    // ── 1. limits ────────────────────────────────────────────────────────────
    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      visible: root.gaugeModel.length > 0
      implicitHeight: limitsCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: limitsCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        NText {
          text: "Limits"
          pointSize: Style.fontSizeXS
          font.weight: Style.fontWeightSemiBold
          color: Color.mOnSurfaceVariant
        }

        Repeater {
          model: root.gaugeModel

          ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginXS

              NText {
                text: modelData.label
                pointSize: Style.fontSizeXS
              }
              Item {
                Layout.fillWidth: true
              }
              // the countdown to refresh — the number you actually plan around
              NText {
                visible: modelData.resets !== ""
                text: modelData.resets
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
              }
              NText {
                text: root.svc ? root.svc.fmtPct(modelData.pct) : "—"
                pointSize: Style.fontSizeS
                font.weight: Style.fontWeightBold
                color: root.gaugeColor(modelData.pct)
              }
            }

            NLinearGauge {
              Layout.fillWidth: true
              implicitHeight: 7
              orientation: Qt.Horizontal
              ratio: Math.max(0, Math.min(1, Number(modelData.pct) / 100))
              fillColor: root.gaugeColor(modelData.pct)
            }
          }
        }
      }
    }

    // ── 2. tokens ────────────────────────────────────────────────────────────
    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      visible: root.svc !== null && root.svc.ok && root.svc.activeWindow !== null
      implicitHeight: tokCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: tokCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        NText {
          text: "Tokens · this 5-hour window"
          pointSize: Style.fontSizeXS
          font.weight: Style.fontWeightSemiBold
          color: Color.mOnSurfaceVariant
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          NText {
            text: root.svc ? root.svc.fmtTokens(root.svc.tokensUsed) : "—"
            pointSize: Style.fontSizeXXL
            font.weight: Style.fontWeightBold
          }
          Item {
            Layout.fillWidth: true
          }
          ColumnLayout {
            spacing: 0
            NText {
              text: {
                if (!root.svc || !root.svc.activeWindow || !root.svc.activeWindow.tokensPerMinute)
                  return "idle";
                return root.svc.fmtTokens(root.svc.activeWindow.tokensPerMinute) + "/min";
              }
              pointSize: Style.fontSizeM
              font.weight: Style.fontWeightSemiBold
              horizontalAlignment: Text.AlignRight
              Layout.fillWidth: true
            }
            NText {
              text: "throughput"
              pointSize: Style.fontSizeXXS
              color: Color.mOnSurfaceVariant
              horizontalAlignment: Text.AlignRight
              Layout.fillWidth: true
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: root.svc && root.svc.activeWindow && root.svc.activeWindow.projectedTokens
          NText {
            text: "projected by window end"
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
          Item {
            Layout.fillWidth: true
          }
          NText {
            text: root.svc && root.svc.activeWindow ? root.svc.fmtTokens(root.svc.activeWindow.projectedTokens) : "—"
            pointSize: Style.fontSizeXS
            font.weight: Style.fontWeightSemiBold
          }
        }
      }
    }

    // ── 3. cost ──────────────────────────────────────────────────────────────
    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      visible: root.svc !== null && root.svc.ok && root.svc.activeWindow !== null
      implicitHeight: costCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: costCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXXS

        NText {
          text: "Cost"
          pointSize: Style.fontSizeXS
          font.weight: Style.fontWeightSemiBold
          color: Color.mOnSurfaceVariant
        }

        GridLayout {
          Layout.fillWidth: true
          columns: 2
          columnSpacing: Style.marginM
          rowSpacing: Style.marginXXS

          NText {
            text: "spent"
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
          NText {
            text: root.svc && root.svc.activeWindow ? root.svc.fmtMoney(root.svc.activeWindow.costUSD) : "—"
            pointSize: Style.fontSizeXS
            font.weight: Style.fontWeightSemiBold
            horizontalAlignment: Text.AlignRight
            Layout.fillWidth: true
          }

          NText {
            text: "burn rate"
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
          NText {
            text: root.svc && root.svc.activeWindow && root.svc.activeWindow.costPerHour ? (root.svc.fmtMoney(root.svc.activeWindow.costPerHour) + "/h") : "idle"
            pointSize: Style.fontSizeXS
            horizontalAlignment: Text.AlignRight
            Layout.fillWidth: true
          }

          NText {
            text: "projected"
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
          NText {
            text: root.svc && root.svc.activeWindow ? root.svc.fmtMoney(root.svc.activeWindow.projectedCostUSD) : "—"
            pointSize: Style.fontSizeXS
            horizontalAlignment: Text.AlignRight
            Layout.fillWidth: true
          }
        }
      }
    }

    // ── nightshift ─────────────────────────────────────────────────────────────
    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      visible: root.svc !== null && root.svc.nsHave
      implicitHeight: nsCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: nsCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS
          NText {
            text: "Nightshift"
            pointSize: Style.fontSizeXS
            font.weight: Style.fontWeightSemiBold
            color: Color.mOnSurfaceVariant
          }
          Item {
            Layout.fillWidth: true
          }
          Rectangle {
            width: 8
            height: 8
            radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: root.svc && root.svc.shiftOn ? Color.mPrimary : Color.mOutline
          }
          NText {
            text: root.svc && root.svc.shiftOn ? "on" : "off"
            pointSize: Style.fontSizeXS
            color: root.svc && root.svc.shiftOn ? Color.mPrimary : Color.mOnSurfaceVariant
          }
          NIconButton {
            icon: "external-link"
            tooltipText: "Open Nightshift"
            baseSize: Style.baseWidgetSize * 0.7
            onClicked: if (root.svc)
              root.svc.openTab("agents")
          }
        }

        NText {
          Layout.fillWidth: true
          text: {
            if (!root.svc)
              return "";
            var v = root.svc.nsAllow ? "▸ will run" : "· holding";
            return root.svc.nsReason ? (v + " — " + root.svc.nsReason) : v;
          }
          pointSize: Style.fontSizeXS
          color: root.svc && root.svc.nsAllow ? Color.mPrimary : Color.mOnSurfaceVariant
          elide: Text.ElideRight
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginL

          Repeater {
            model: root.svc ? [
              { "n": root.svc.nsPending, "l": "pending" },
              { "n": root.svc.effectCount("memory"), "l": "memory" },
              { "n": root.svc.effectCount("job"), "l": "jobs" },
              { "n": root.svc.effectCount("skill"), "l": "skills" },
              { "n": root.svc.nsRuns, "l": "runs" }
            ] : []

            ColumnLayout {
              required property var modelData
              spacing: 0
              NText {
                text: String(modelData.n)
                pointSize: Style.fontSizeL
                font.weight: Style.fontWeightBold
              }
              NText {
                text: modelData.l
                pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
              }
            }
          }
          Item {
            Layout.fillWidth: true
          }
        }
      }
    }

    // ── git productivity ─────────────────────────────────────────────────────
    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      visible: root.svc !== null && root.svc.commits !== null && root.svc.gitCommitCount > 0
      implicitHeight: gitCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: gitCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        RowLayout {
          Layout.fillWidth: true
          NText {
            text: root.svc ? ("Git · last " + root.svc.gitWindowDays + " days") : "Git"
            pointSize: Style.fontSizeXS
            font.weight: Style.fontWeightSemiBold
            color: Color.mOnSurfaceVariant
          }
          Item {
            Layout.fillWidth: true
          }
          NIconButton {
            icon: "external-link"
            tooltipText: "Open Git productivity"
            baseSize: Style.baseWidgetSize * 0.7
            onClicked: if (root.svc)
              root.svc.openTab("git")
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginL

          Repeater {
            model: root.svc ? [
              { "n": String(root.svc.gitCommitCount), "l": "commits" },
              { "n": String(root.svc.gitActiveDays), "l": "active days" },
              { "n": String(root.svc.gitRepoCount), "l": "repos" }
            ] : []

            ColumnLayout {
              required property var modelData
              spacing: 0
              NText {
                text: modelData.n
                pointSize: Style.fontSizeL
                font.weight: Style.fontWeightBold
              }
              NText {
                text: modelData.l
                pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
              }
            }
          }
          Item {
            Layout.fillWidth: true
          }
          ColumnLayout {
            spacing: 0
            NText {
              text: root.svc && root.svc.gitLastMs ? root.svc.fmtAge(root.svc.gitLastMs) : "—"
              pointSize: Style.fontSizeM
              font.weight: Style.fontWeightSemiBold
              horizontalAlignment: Text.AlignRight
              Layout.fillWidth: true
            }
            NText {
              text: "last commit"
              pointSize: Style.fontSizeXXS
              color: Color.mOnSurfaceVariant
              horizontalAlignment: Text.AlignRight
              Layout.fillWidth: true
            }
          }
        }
      }
    }

    // ── machines ─────────────────────────────────────────────────────────────
    Flow {
      Layout.fillWidth: true
      spacing: Style.marginS
      visible: root.svc !== null && root.svc.sources.length > 0

      Repeater {
        model: root.svc ? root.svc.sources : []

        Row {
          required property var modelData
          spacing: 4

          Rectangle {
            width: 7
            height: 7
            radius: 3.5
            anchors.verticalCenter: parent.verticalCenter
            color: modelData.ok ? Color.mPrimary : (modelData.stale || modelData.offline ? Color.mSecondary : Color.mError)
          }
          NText {
            text: modelData.name || "?"
            pointSize: Style.fontSizeXXS
            color: modelData.ok ? Color.mOnSurfaceVariant : Color.mError
          }
        }
      }
    }
  }
}
