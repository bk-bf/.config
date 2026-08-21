// ClaudePill.qml — a bar capsule that leads with the Claude mark.
//
// Noctalia's stock BarPill draws its icon from the Tabler icon font, so it can
// only ever show a glyph. To lead with the actual Claude logo the capsule is
// rebuilt here, deliberately mirroring BarPillHorizontal's geometry so it lines
// up with every other widget in the bar:
//
//   * the root takes the FULL bar height (height: parent.height) and centres a
//     capsule of pillHeight inside it — a root that is only capsule-tall gets
//     laid out differently from its neighbours and visibly sits off;
//   * the logo occupies a square of pillHeight at the leading edge, the same
//     box BarPillHorizontal gives its icon, so the label starts where every
//     other widget's label starts.
//
// The logo is an SVG built per-render with its fill baked in, which is what
// lets it be orange when the dashboard is live and grey when it isn't.

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets
import "claudeLogo.js" as ClaudeLogo

Item {
  id: root

  required property ShellScreen screen

  property string text: ""
  property var tooltipText
  property color logoColor: Color.mOnSurface
  property color labelColor: Color.mOnSurface

  signal clicked
  signal rightClicked
  signal middleClicked

  readonly property string screenName: screen ? screen.name : ""
  readonly property int pillHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)
  readonly property real logoSize: Style.toOdd(pillHeight * 0.48)
  readonly property int padTrailing: Math.round(pillHeight * 0.34)

  readonly property bool hasText: text !== ""
  readonly property real contentWidth: pillHeight + (hasText ? label.implicitWidth + padTrailing : 0)

  property bool hovered: false

  // Match BarPill: content-sized width, full bar height, capsule centred inside.
  width: contentWidth
  height: parent ? parent.height : pillHeight
  implicitWidth: contentWidth
  implicitHeight: pillHeight

  Rectangle {
    id: bg
    width: root.width
    height: root.pillHeight
    anchors.verticalCenter: parent.verticalCenter
    radius: Style.radiusM
    color: root.hovered ? Color.mHover : Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    Behavior on color {
      enabled: !Color.isTransitioning
      ColorAnimation {
        duration: Style.animationFast
        easing.type: Easing.InOutQuad
      }
    }
  }

  // Square leading box, the same one BarPillHorizontal reserves for its icon.
  Item {
    id: logoBox
    width: root.pillHeight
    height: root.pillHeight
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter

    Image {
      anchors.centerIn: parent
      width: root.logoSize
      height: root.logoSize
      // rasterise above nominal size so the mark stays crisp on scaled bars
      sourceSize.width: Math.round(root.logoSize * 3)
      sourceSize.height: Math.round(root.logoSize * 3)
      smooth: true
      fillMode: Image.PreserveAspectFit
      source: ClaudeLogo.svg(root.hovered ? Color.mOnHover : root.logoColor)
    }
  }

  NText {
    id: label
    visible: root.hasText
    text: root.text
    family: Settings.data.ui.fontFixed
    pointSize: root.barFontSize
    applyUiScale: false
    color: root.hovered ? Color.mOnHover : root.labelColor
    anchors.left: logoBox.right
    anchors.verticalCenter: parent.verticalCenter
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onEntered: {
      root.hovered = true;
      if (root.tooltipText)
        TooltipService.show(root, root.tooltipText, "", Style.tooltipDelay);
    }
    onExited: {
      root.hovered = false;
      TooltipService.hide(root);
    }
    onClicked: mouse => {
                 TooltipService.hideImmediately();
                 if (mouse.button === Qt.RightButton)
                 root.rightClicked();
                 else if (mouse.button === Qt.MiddleButton)
                 root.middleClicked();
                 else
                 root.clicked();
               }
  }

  Connections {
    target: root
    function onTooltipTextChanged() {
      if (root.hovered)
        TooltipService.updateText(root.tooltipText);
    }
  }
}
