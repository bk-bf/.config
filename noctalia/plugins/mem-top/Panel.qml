// Panel.qml — the detail view opened by clicking the bar pill.
//
// Ranks what holds memory by name rather than by pid: applications, systemd
// services, and each Claude Code session under its own session name. Each row
// is committed memory (RSS + swap) with a bar scaled to the largest consumer.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi
  readonly property var svc: pluginApi ? pluginApi.mainInstance : null

  property int contentPreferredWidth: 480
  property int contentPreferredHeight: Math.min(780, layout.implicitHeight + Style.marginL * 2)
  property color panelBackgroundColor: Color.mSurface

  // which row is expanded, and which close button is armed (SIGTERM needs two
  // clicks — a bar widget must not kill an app on a stray click)
  property string expandedName: ""
  property string armedName: ""

  Timer {
    id: disarm
    interval: 4000
    onTriggered: root.armedName = ""
  }

  function fmt(mb) {
    return root.svc ? root.svc.fmtMb(mb) : "–";
  }

  // Claude sessions get their own accent so the thing you can actually close is
  // distinguishable at a glance from apps and services.
  function kindColor(kind) {
    if (kind === "claude")
      return Color.mSecondary;
    if (kind === "service")
      return Color.mTertiary !== undefined ? Color.mTertiary : Color.mPrimary;
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
        width: 10
        height: 10
        radius: 5
        Layout.alignment: Qt.AlignVCenter
        color: root.svc ? root.svc.stateColor : Color.mOutline
      }

      ColumnLayout {
        spacing: 0
        Layout.fillWidth: true
        NText {
          text: "Memory"
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
        }
        NText {
          text: {
            if (!root.svc)
              return "";
            if (!root.svc.ok)
              return root.svc.errorText || "no data";
            return "updated " + root.svc.lastOkLabel;
          }
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
          elide: Text.ElideRight
        }
      }

      // Session-wide reclaim: frees the coldest pages across every app at once.
      NIconButton {
        icon: "download"
        baseSize: Style.baseWidgetSize * 0.7
        Layout.alignment: Qt.AlignVCenter
        tooltipText: "Free 1 GB now — evicts the coldest pages across the whole session into zram. Nothing is killed."
        onClicked: {
          if (root.svc)
            root.svc.compactSession();
        }
      }
      NIconButton {
        icon: "refresh"
        baseSize: Style.baseWidgetSize * 0.7
        Layout.alignment: Qt.AlignVCenter
        onClicked: {
          if (root.svc)
            root.svc.refresh();
        }
      }
    }

    // ── system summary ───────────────────────────────────────────────────────
    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      implicitHeight: summary.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: summary
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        RowLayout {
          Layout.fillWidth: true
          NText {
            text: root.fmt(root.svc ? root.svc.usedMb : 0) + " used"
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
          }
          Item {
            Layout.fillWidth: true
          }
          NText {
            text: root.fmt(root.svc ? root.svc.availableMb : 0) + " available"
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
        }

        NLinearGauge {
          Layout.fillWidth: true
          Layout.preferredHeight: 6
          orientation: Qt.Horizontal
          ratio: root.svc && root.svc.totalMb > 0 ? Math.min(1, root.svc.usedMb / root.svc.totalMb) : 0
          fillColor: root.svc ? root.svc.stateColor : Color.mOutline
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS
          NText {
            text: "swap " + root.fmt(root.svc ? root.svc.swapUsedMb : 0) + " / " + root.fmt(root.svc ? root.svc.swapTotalMb : 0)
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
          Item {
            Layout.fillWidth: true
          }
          NText {
            text: "committed " + root.fmt(root.svc ? root.svc.committedMb : 0)
            pointSize: Style.fontSizeXS
            color: root.svc && root.svc.overcommitted ? Color.mError : Color.mOnSurfaceVariant
            font.weight: root.svc && root.svc.overcommitted ? Style.fontWeightSemiBold : Style.fontWeightRegular
          }
        }

        // Committed beyond physical RAM is why the machine feels slow even when
        // "used" looks survivable -- the overflow lives compressed in zram.
        NText {
          visible: root.svc ? root.svc.overcommitted : false
          Layout.fillWidth: true
          text: "More is committed than this machine has RAM — the overflow is compressed in zram."
          pointSize: Style.fontSizeXS
          color: Color.mError
          wrapMode: Text.WordWrap
        }
      }
    }

    // ── the ranking ──────────────────────────────────────────────────────────
    NText {
      text: "By committed memory (RSS + swap)"
      pointSize: Style.fontSizeXS
      color: Color.mOnSurfaceVariant
      Layout.topMargin: Style.marginXS
    }

    Repeater {
      model: root.svc ? root.svc.entries : []

      NBox {
        id: entryBox
        required property var modelData
        readonly property bool expanded: root.expandedName === modelData.name
        readonly property bool busy: root.svc ? root.svc.isBusy(modelData.name) : false

        Layout.fillWidth: true
        forceOpaque: true
        implicitHeight: row.implicitHeight + Style.marginS * 2

        ColumnLayout {
          id: row
          anchors.fill: parent
          anchors.margins: Style.marginS
          spacing: 2

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            // expand chevron — only where there is something to break down
            NText {
              text: entryBox.modelData.procs > 1 ? (entryBox.expanded ? "▾" : "▸") : " "
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            NText {
              Layout.fillWidth: true
              text: entryBox.modelData.name
              pointSize: Style.fontSizeS
              font.weight: Style.fontWeightSemiBold
              elide: Text.ElideRight
              color: Color.mOnSurface
            }
            NText {
              text: entryBox.busy ? "working…" : (entryBox.modelData.procs > 1 ? (entryBox.modelData.procs + " procs") : ("pid " + entryBox.modelData.pid))
              pointSize: Style.fontSizeXXS
              color: Color.mOnSurfaceVariant
            }
            NText {
              text: root.fmt(entryBox.modelData.mb)
              pointSize: Style.fontSizeS
              font.weight: Style.fontWeightBold
              color: root.kindColor(entryBox.modelData.kind)
            }

            // Compact: push cold pages to zram, nothing dies.
            NIconButton {
              icon: "download"
              baseSize: Style.baseWidgetSize * 0.55
              enabled: entryBox.modelData.compactable && !entryBox.busy
              opacity: enabled ? 1 : 0.35
              tooltipText: entryBox.modelData.compactable ? "Compact — push this consumer's cold pages out to zram. Nothing is killed." : "Shares the graphical session cgroup, so it cannot be compacted alone — use the Free button in the header."
              onClicked: {
                if (root.svc)
                  root.svc.compact(entryBox.modelData.name);
              }
            }
            // Close: SIGTERM. Armed by a first click, fired by a second.
            NIconButton {
              icon: "close"
              baseSize: Style.baseWidgetSize * 0.55
              enabled: !entryBox.busy
              colorBg: root.armedName === entryBox.modelData.name ? Color.mError : Color.smartAlpha(Color.mSurfaceVariant)
              tooltipText: root.armedName === entryBox.modelData.name ? "Click again to send SIGTERM" : "Close — SIGTERM, letting it save and exit"
              onClicked: {
                if (root.armedName === entryBox.modelData.name) {
                  root.armedName = "";
                  if (root.svc)
                    root.svc.terminate(entryBox.modelData.name);
                } else {
                  root.armedName = entryBox.modelData.name;
                  disarm.restart();
                }
              }
            }
          }

          NLinearGauge {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            orientation: Qt.Horizontal
            ratio: root.svc && root.svc.topMb > 0 ? (entryBox.modelData.mb / root.svc.topMb) : 0
            fillColor: root.kindColor(entryBox.modelData.kind)
          }

          // ── the breakdown ───────────────────────────────────────────────────
          Repeater {
            model: entryBox.expanded ? entryBox.modelData.children : []

            RowLayout {
              required property var modelData
              Layout.fillWidth: true
              Layout.leftMargin: Style.marginM
              spacing: Style.marginS

              NText {
                text: modelData.pct + "%"
                pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
                Layout.preferredWidth: 34
                horizontalAlignment: Text.AlignRight
              }
              NText {
                Layout.fillWidth: true
                text: modelData.label
                pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
                elide: Text.ElideRight
              }
              NText {
                text: "pid " + modelData.pid
                pointSize: Style.fontSizeXXS
                color: Color.mOutline
              }
              NText {
                text: root.fmt(modelData.mb)
                pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
              }
            }
          }

          NText {
            visible: entryBox.expanded && entryBox.modelData.hiddenChildren > 0
            Layout.leftMargin: Style.marginM
            text: "+ " + entryBox.modelData.hiddenChildren + " smaller processes"
            pointSize: Style.fontSizeXXS
            color: Color.mOutline
          }
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          z: -1
          onClicked: {
            if (entryBox.modelData.procs > 1)
              root.expandedName = entryBox.expanded ? "" : entryBox.modelData.name;
          }
        }
      }
    }

    NText {
      visible: root.svc ? root.svc.otherMb > 0 : false
      Layout.fillWidth: true
      text: "everything else — " + root.fmt(root.svc ? root.svc.otherMb : 0)
      pointSize: Style.fontSizeXS
      color: Color.mOnSurfaceVariant
    }
  }
}
