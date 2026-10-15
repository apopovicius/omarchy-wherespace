import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Card shown while hovering a workspace: its screen and number, then every
// window on it with the app icon, app name and window title. Styled with the
// theme's tooltip colors, placed like the bar's own tooltips.
PopupWindow {
  id: card

  property var host: null
  property var pill: null
  property bool shown: false

  readonly property var screenInfo: pill ? pill.screen : null
  readonly property var windows: {
    if (!host || !pill) return []
    host.revision
    return host.windowsOn(pill.workspace)
  }
  readonly property real iconSize: Math.round(Style.font.body * 1.4)
  readonly property real titleWidth: Style.space(260)
  readonly property color textColor: Color.tooltip.text
  readonly property color mutedColor: Util.alpha(Color.tooltip.text, 0.6)

  visible: shown && pill !== null
  color: "transparent"
  // One spare pixel on every side: with fractional scaling a border drawn
  // right on the window's edge can land on a cut-off device pixel.
  readonly property int edge: 1
  implicitWidth: Math.ceil(bubble.width) + edge * 2
  implicitHeight: Math.ceil(bubble.height) + edge * 2

  anchor {
    id: cardAnchor
    window: card.pill ? card.pill.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      var target = card.pill
      if (!target || !target.QsWindow.window) return
      var bottomBar = card.host && card.host.bar && card.host.bar.position === "bottom"
      var localX = target.width / 2 - card.implicitWidth / 2
      var localY = bottomBar ? -card.implicitHeight - 6 : target.height + 6
      var point = target.QsWindow.window.contentItem.mapFromItem(target, localX, localY)
      cardAnchor.rect.x = Math.round(point.x)
      cardAnchor.rect.y = Math.round(point.y)
    }
  }

  BorderSurface {
    id: bubble
    x: card.edge
    y: card.edge
    width: Math.ceil(content.implicitWidth + Style.space(24))
    height: Math.ceil(content.implicitHeight + Style.space(20))
    color: Color.tooltip.background
    borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
    radius: Style.cornerRadius

    Column {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(10)

      // Header: the screen drawing, workspace number and screen name.
      Row {
        id: header
        spacing: Style.space(10)

        ScreenShape {
          anchors.verticalCenter: parent.verticalCenter
          kind: card.screenInfo ? card.screenInfo.kind : "monitor"
          color: card.screenInfo ? card.screenInfo.color : Color.accent
          borderColor: card.textColor
          filled: true
          label: card.pill ? (card.pill.modelData === 10 ? "0" : String(card.pill.modelData)) : ""
          filledLabelColor: card.host && card.screenInfo ? card.host.contrastOn(card.screenInfo.color) : "white"
          fontFamily: Style.font.family
          fontSize: Math.round(Style.font.body * 0.8)
          size: Math.round(Style.font.body * 1.7)
          line: card.host ? card.host.line : 1
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter

          Text {
            text: card.pill ? "Workspace " + (card.pill.modelData === 10 ? "0" : card.pill.modelData) : ""
            color: card.textColor
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            text: card.screenInfo ? card.screenInfo.label : ""
            color: card.mutedColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      Rectangle {
        width: Math.max(header.implicitWidth, windowList.implicitWidth)
        height: 1
        color: Util.alpha(card.textColor, 0.12)
      }

      Text {
        visible: card.windows.length === 0
        text: "No windows"
        color: card.mutedColor
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Column {
        id: windowList
        visible: card.windows.length > 0
        spacing: Style.space(8)

        Repeater {
          model: card.windows

          Row {
            id: windowRow
            required property var modelData
            spacing: Style.space(10)

            Item {
              anchors.verticalCenter: parent.verticalCenter
              width: card.iconSize
              height: card.iconSize

              Image {
                id: windowIcon
                visible: windowRow.modelData.icon !== ""
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.round(card.iconSize * Screen.devicePixelRatio)
                sourceSize.height: Math.round(card.iconSize * Screen.devicePixelRatio)
                source: windowRow.modelData.icon
                smooth: true
              }

              Text {
                id: windowGlyph
                visible: !windowIcon.visible && (windowRow.modelData.glyph || "") !== ""
                anchors.centerIn: parent
                text: windowRow.modelData.glyph || ""
                color: card.textColor
                font.family: Style.font.family
                font.pixelSize: card.iconSize
              }

              // Programs without an icon (e.g. a terminal app) get a letter tile.
              Rectangle {
                visible: !windowIcon.visible && !windowGlyph.visible
                anchors.fill: parent
                radius: Style.space(4)
                color: Util.alpha(card.screenInfo ? card.screenInfo.color : card.textColor, 0.25)

                Text {
                  anchors.centerIn: parent
                  text: String(windowRow.modelData.name || "?").charAt(0).toUpperCase()
                  color: card.textColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter

              Text {
                text: windowRow.modelData.name
                color: card.textColor
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              Text {
                visible: text !== "" && text !== windowRow.modelData.name
                width: Math.min(implicitWidth, card.titleWidth)
                elide: Text.ElideRight
                text: windowRow.modelData.title
                color: card.mutedColor
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
