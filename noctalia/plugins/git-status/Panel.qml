// Panel.qml — the detail view opened by clicking the bar pill.
//
// Lists the repos that need attention (uncommitted / unpushed / unpulled) with
// one-click pull, push and open-to-commit. Clean repos are summarised as a count
// rather than listed, to keep it compact.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi
  readonly property var svc: pluginApi ? pluginApi.mainInstance : null

  property int contentPreferredWidth: 460
  property int contentPreferredHeight: Math.min(760, layout.implicitHeight + Style.marginL * 2)
  property color panelBackgroundColor: Color.mSurface
  property bool commitsOpen: true

  readonly property var attentionRepos: {
    if (!svc || !svc.repos)
      return [];
    return svc.repos.filter(function (r) {
      return r.dirty > 0 || r.ahead > 0 || r.behind > 0;
    });
  }
  readonly property int cleanCount: svc && svc.summary ? (svc.summary.total - svc.summary.attention) : 0

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
          text: "Git status"
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
          Layout.fillWidth: true
        }
      }

      NIconButton {
        icon: "refresh"
        tooltipText: "Re-scan repos now"
        baseSize: Style.baseWidgetSize * 0.8
        onClicked: if (root.svc)
          root.svc.refresh()
      }
    }

    // ── AI-commit breakdown (toggleable) ──────────────────────────────────────
    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      visible: root.svc !== null && root.svc.recentCommits.length > 0
      implicitHeight: aiCol.implicitHeight + Style.marginM * 2

      ColumnLayout {
        id: aiCol
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS

          MouseArea {
            Layout.fillWidth: true
            implicitHeight: aiHdrText.implicitHeight
            cursorShape: Qt.PointingHandCursor
            onClicked: root.commitsOpen = !root.commitsOpen
            NText {
              id: aiHdrText
              text: (root.commitsOpen ? "▾" : "▸") + "  AI commits  " + (root.svc ? root.svc.recentCommits.length : 0)
              pointSize: Style.fontSizeXS
              font.weight: Style.fontWeightSemiBold
              color: Color.mOnSurfaceVariant
            }
          }
          NIconButton {
            icon: "trash"
            tooltipText: "Clear the AI-commit history"
            baseSize: Style.baseWidgetSize * 0.65
            onClicked: if (root.svc)
              root.svc.clearActivity()
          }
        }

        Repeater {
          model: root.commitsOpen && root.svc ? root.svc.recentCommits : []

          ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 1

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginXS
              NText {
                text: modelData.name
                pointSize: Style.fontSizeXS
                font.weight: Style.fontWeightSemiBold
              }
              NText {
                text: modelData.pushed ? "pushed ✓" : "committed"
                pointSize: Style.fontSizeXXS
                color: modelData.pushed ? Color.mPrimary : Color.mSecondary
              }
              Item {
                Layout.fillWidth: true
              }
            }

            Repeater {
              model: modelData.commits
              NText {
                required property var modelData
                Layout.fillWidth: true
                text: "• " + modelData
                pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
                wrapMode: Text.WordWrap
              }
            }
          }
        }
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
          text: "git-status didn't run"
          font.weight: Style.fontWeightSemiBold
          color: Color.mError
        }
        NText {
          text: root.svc ? root.svc.command : ""
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
          elide: Text.ElideMiddle
          Layout.fillWidth: true
        }
      }
    }

    // ── all clean ─────────────────────────────────────────────────────────────
    NBox {
      Layout.fillWidth: true
      forceOpaque: true
      visible: root.svc !== null && root.svc.ok && root.attentionRepos.length === 0
      implicitHeight: cleanRow.implicitHeight + Style.marginM * 2
      RowLayout {
        id: cleanRow
        anchors.fill: parent
        anchors.margins: Style.marginM
        NText {
          text: "✓ all " + (root.svc && root.svc.summary ? root.svc.summary.total : 0) + " repos clean"
          color: Color.mPrimary
          font.weight: Style.fontWeightSemiBold
        }
      }
    }

    // ── repos needing attention ────────────────────────────────────────────────
    Repeater {
      model: root.attentionRepos

      NBox {
        id: repoBox
        required property var modelData
        Layout.fillWidth: true
        forceOpaque: true
        implicitHeight: repoCol.implicitHeight + Style.marginM * 2

        ColumnLayout {
          id: repoCol
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginXXS

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            ColumnLayout {
              spacing: 0
              Layout.fillWidth: true
              NText {
                text: repoBox.modelData.name
                pointSize: Style.fontSizeM
                font.weight: Style.fontWeightSemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
              NText {
                text: "⎇ " + repoBox.modelData.branch + (repoBox.modelData.upstream ? "" : "  · no upstream")
                pointSize: Style.fontSizeXXS
                color: Color.mOnSurfaceVariant
              }
            }

            // status badges
            RowLayout {
              spacing: Style.marginXS
              Layout.alignment: Qt.AlignVCenter

              NText {
                visible: repoBox.modelData.dirty > 0
                text: "● " + repoBox.modelData.dirty
                pointSize: Style.fontSizeXS
                color: Color.mSecondary
                font.weight: Style.fontWeightSemiBold
              }
              NText {
                visible: repoBox.modelData.ahead > 0
                text: "↑" + repoBox.modelData.ahead
                pointSize: Style.fontSizeXS
                color: Color.mSecondary
                font.weight: Style.fontWeightSemiBold
              }
              NText {
                visible: repoBox.modelData.behind > 0
                text: "↓" + repoBox.modelData.behind
                pointSize: Style.fontSizeXS
                color: Color.mError
                font.weight: Style.fontWeightSemiBold
              }
            }

            // actions — ✨ AI commit shows a spinner while its background Claude runs
            Item {
              Layout.preferredWidth: Style.baseWidgetSize * 0.75
              Layout.preferredHeight: Style.baseWidgetSize * 0.75
              Layout.alignment: Qt.AlignVCenter
              readonly property bool busy: root.svc ? root.svc.isWorking(repoBox.modelData.path) : false

              NBusyIndicator {
                anchors.centerIn: parent
                visible: parent.busy
                running: parent.busy
                size: Style.baseWidgetSize * 0.6
                color: Color.mSecondary
              }
              NIconButton {
                anchors.centerIn: parent
                visible: !parent.busy
                icon: "sparkles"
                tooltipText: "AI commit + push — a background Claude stages, writes a\nconventional message and pushes (notifies + lists them here when done)"
                baseSize: Style.baseWidgetSize * 0.7
                onClicked: if (root.svc)
                  root.svc.aiCommit(repoBox.modelData.path)
              }
            }
            NIconButton {
              icon: "terminal-2"
              tooltipText: "Open a terminal here to commit by hand"
              baseSize: Style.baseWidgetSize * 0.7
              onClicked: if (root.svc)
                root.svc.openTerminal(repoBox.modelData.path)
            }
            Item {
              Layout.preferredWidth: Style.baseWidgetSize * 0.75
              Layout.preferredHeight: Style.baseWidgetSize * 0.75
              Layout.alignment: Qt.AlignVCenter
              readonly property bool busy: root.svc ? root.svc.isBusy(repoBox.modelData.path, "push") : false
              NBusyIndicator {
                anchors.centerIn: parent
                visible: parent.busy
                running: parent.busy
                size: Style.baseWidgetSize * 0.6
                color: Color.mSecondary
              }
              NIconButton {
                anchors.centerIn: parent
                visible: !parent.busy
                icon: "arrow-up"
                enabled: repoBox.modelData.ahead > 0
                tooltipText: "git push (" + repoBox.modelData.ahead + " commit(s))"
                baseSize: Style.baseWidgetSize * 0.7
                onClicked: if (root.svc)
                  root.svc.push(repoBox.modelData.path)
              }
            }
            Item {
              Layout.preferredWidth: Style.baseWidgetSize * 0.75
              Layout.preferredHeight: Style.baseWidgetSize * 0.75
              Layout.alignment: Qt.AlignVCenter
              readonly property bool busy: root.svc ? root.svc.isBusy(repoBox.modelData.path, "pull") : false
              NBusyIndicator {
                anchors.centerIn: parent
                visible: parent.busy
                running: parent.busy
                size: Style.baseWidgetSize * 0.6
                color: Color.mSecondary
              }
              NIconButton {
                anchors.centerIn: parent
                visible: !parent.busy
                icon: "arrow-down"
                enabled: repoBox.modelData.behind > 0
                tooltipText: "git pull --ff-only (" + repoBox.modelData.behind + " behind)"
                baseSize: Style.baseWidgetSize * 0.7
                onClicked: if (root.svc)
                  root.svc.pull(repoBox.modelData.path)
              }
            }
          }
        }
      }
    }

    // ── clean footer ────────────────────────────────────────────────────────
    NText {
      Layout.fillWidth: true
      visible: root.attentionRepos.length > 0 && root.cleanCount > 0
      text: "+ " + root.cleanCount + " more clean"
      pointSize: Style.fontSizeXXS
      color: Color.mOnSurfaceVariant
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
