import QtQuick
import qs.Commons

// One app on a workspace: its icon (or, for a bare terminal, a console glyph),
// with a window-count bubble at the bottom-right when it has 2+ windows. The
// bubble sticks out past the icon, and the item is that much wider.
Item {
  id: appSlot

  property var host: null
  property var app: ({ icon: "", glyph: "", text: "", name: "", count: 1 })
  property color tint: "white"
  property color screenColor: "white"
  property real artOpacity: 1

  readonly property string fontFamily: host && host.bar ? host.bar.fontFamily : Style.font.family
  readonly property real iconWidth: app.icon !== "" || appGlyph.visible ? host.appIconSize : appText.implicitWidth

  signal activated()

  width: iconWidth + host.bubbleOverhang(app.count)
  height: host.appIconSize

  // Left-click focuses the app's window; other buttons fall through to the
  // workspace (right-click still opens the settings).
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: appSlot.activated()
  }

  Image {
    visible: appSlot.app.icon !== ""
    width: appSlot.iconWidth
    height: parent.height
    fillMode: Image.PreserveAspectFit
    sourceSize.width: Math.round(appSlot.host.appIconSize * Screen.devicePixelRatio)
    sourceSize.height: Math.round(appSlot.host.appIconSize * Screen.devicePixelRatio)
    source: appSlot.app.icon
    smooth: true
    opacity: appSlot.artOpacity
  }

  Text {
    id: appGlyph
    visible: appSlot.app.icon === "" && (appSlot.app.glyph || "") !== ""
    x: Math.round((appSlot.iconWidth - width) / 2)
    anchors.verticalCenter: parent.verticalCenter
    text: appSlot.app.glyph || ""
    color: appSlot.tint
    opacity: appSlot.artOpacity
    font.family: appSlot.fontFamily
    font.pixelSize: Style.bar.iconFont
    renderType: Text.NativeRendering
  }

  Text {
    id: appText
    visible: appSlot.app.icon === "" && !appGlyph.visible
    anchors.verticalCenter: parent.verticalCenter
    text: appSlot.app.text || ""
    color: appSlot.tint
    font.family: appSlot.fontFamily
    font.pixelSize: Style.font.bodySmall
    renderType: Text.NativeRendering
  }

  Rectangle {
    visible: appSlot.app.count >= 2
    z: 2
    x: appSlot.iconWidth + appSlot.host.bubbleOverhang(appSlot.app.count) - width
    y: parent.height - height + Math.round(appSlot.host.line * 3)
    width: appSlot.host.bubbleWidth(appSlot.app.count)
    height: appSlot.host.bubbleHeight
    radius: height / 2
    color: appSlot.screenColor
    border.width: 1
    border.color: appSlot.host.bar ? appSlot.host.bar.background : Color.background

    Text {
      anchors.centerIn: parent
      text: appSlot.host.bubbleText(appSlot.app.count)
      color: appSlot.host.contrastOn(appSlot.screenColor)
      font.family: appSlot.fontFamily
      font.pixelSize: appSlot.host.bubbleFont
      font.bold: true
      renderType: Text.NativeRendering
    }
  }
}
