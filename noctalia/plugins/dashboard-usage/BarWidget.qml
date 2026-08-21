// BarWidget.qml — the pill in the Noctalia bar.
//
// Pure presentation: every value comes from Main.qml via pluginApi.mainInstance.
// Uses ClaudePill rather than Noctalia's BarPill because the capsule leads with
// the Claude mark, and BarPill can only draw glyphs from the icon font.
// Left click toggles this plugin's own panel, right click opens a context menu,
// middle click forces a fresh pull from the dashboard server.

import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  // Injected by BarWidgetLoader.
  property ShellScreen screen
  property var pluginApi
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var svc: pluginApi ? pluginApi.mainInstance : null

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId] ?? ({})
  readonly property string screenName: screen ? screen.name : ""

  // Per-instance overrides the user set in the bar editor, if any.
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length)
        return widgets[sectionWidgetIndex];
    }
    return {};
  }

  // The logo carries the state colour, so only the label honours a configured
  // text colour; the pill is always shown rather than hover-collapsed.
  readonly property string textColorKey: widgetSettings.textColor !== undefined ? widgetSettings.textColor : widgetMetadata.textColor

  // same as the built-in widgets: track the pill's laid-out size, not its
  // implicit size, so the capsule centres against the full bar height
  implicitWidth: pill.width
  implicitHeight: pill.height

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": "Refresh now",
        "action": "refresh",
        "icon": "refresh"
      },
      {
        "label": "Open dashboard",
        "action": "open",
        "icon": "external-link"
      },
      {
        "label": "Widget settings",
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "refresh") {
                     if (root.svc)
                       root.svc.refresh(true);
                   } else if (action === "open") {
                     if (root.svc)
                       root.svc.openInBrowser();
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  ClaudePill {
    id: pill

    screen: root.screen

    text: root.svc ? root.svc.barLabel : "…"
    tooltipText: root.svc ? root.svc.tooltipText : ""

    // Orange while the dashboard is answering, grey the moment it isn't.
    logoColor: root.svc ? root.svc.logoColor : Color.mOutline

    // Label goes amber then red as a limit is approached, otherwise it honours
    // whatever bar text colour is configured.
    labelColor: {
      if (root.svc && root.svc.colorBySeverity && root.svc.severity > 0)
        return root.svc.severityColor;
      var configured = Color.resolveColorKeyOptional(root.textColorKey);
      return configured.a > 0 ? configured : Color.mOnSurface;
    }

    onClicked: {
      if (root.pluginApi)
        root.pluginApi.togglePanel(root.screen, this);
    }
    onMiddleClicked: {
      if (root.svc)
        root.svc.refresh(true);
    }
    onRightClicked: PanelService.showContextMenu(contextMenu, pill, screen)
  }
}
