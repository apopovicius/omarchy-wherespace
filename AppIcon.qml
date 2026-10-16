import QtQuick
import QtQuick.Effects
import qs.Commons

// One app on a workspace: its icon (or, for a bare terminal, a console glyph),
// with its window count ("×5") beside it when it has 2+ windows; the item
// is that much wider.
Item {
  id: appSlot

  property var host: null
  property var app: ({ icon: "", glyph: "", text: "", name: "", count: 1 })
  property color tint: "white"
  property color screenColor: "white"
  // Count bubble styled like the screens: outlined, filled only when focused.
  property bool focused: false
  property real artOpacity: 1

  readonly property string fontFamily: host && host.bar ? host.bar.fontFamily : Style.font.family
  // Decided from the app data, not from what is visible: inside a hidden
  // reveal nothing is visible yet, which would make the icon zero-wide and
  // keep the reveal hidden.
  readonly property bool hasIcon: app.icon !== "" || (app.glyph || "") !== ""
  readonly property real iconWidth: hasIcon ? host.appIconSize : appText.implicitWidth

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

  // Every icon is clipped to the same rounded shape, so full-bleed square
  // icons (SoundCloud) carry the same visual weight as round ones.
  Image {
    id: iconImage
    visible: false
    width: appSlot.host.appIconSize
    height: appSlot.host.appIconSize
    fillMode: Image.PreserveAspectFit
    sourceSize.width: Math.round(appSlot.host.appIconSize * Screen.devicePixelRatio)
    sourceSize.height: Math.round(appSlot.host.appIconSize * Screen.devicePixelRatio)
    source: appSlot.app.icon
    smooth: true
  }

  Rectangle {
    id: iconMask
    visible: false
    layer.enabled: true
    width: appSlot.host.appIconSize
    height: appSlot.host.appIconSize
    radius: width * 0.3
  }

  MultiEffect {
    visible: appSlot.app.icon !== ""
    width: appSlot.host.appIconSize
    height: appSlot.host.appIconSize
    source: iconImage
    maskEnabled: true
    maskSource: iconMask
    opacity: appSlot.artOpacity
  }

  Text {
    // Plain text only: titles and names come from other apps and must
    // never be parsed as rich text (an <img> would make the shell fetch it).
    textFormat: Text.PlainText
    id: appGlyph
    visible: appSlot.app.icon === "" && (appSlot.app.glyph || "") !== ""
    x: Math.round((appSlot.iconWidth - width) / 2)
    anchors.verticalCenter: parent.verticalCenter
    text: appSlot.app.glyph || ""
    color: appSlot.tint
    opacity: appSlot.artOpacity
    font.family: appSlot.fontFamily
    // Same scale as the image icons.
    font.pixelSize: appSlot.host.appIconSize
    renderType: Text.NativeRendering
  }

  Text {
    textFormat: Text.PlainText
    id: appText
    visible: appSlot.app.icon === "" && !appGlyph.visible
    anchors.verticalCenter: parent.verticalCenter
    text: appSlot.app.text || ""
    color: appSlot.tint
    font.family: appSlot.fontFamily
    font.pixelSize: Style.font.bodySmall
    renderType: Text.NativeRendering
  }

  // Window count as plain text ("×5") beside the icon, low like a subscript.
  Text {
    textFormat: Text.PlainText
    visible: appSlot.app.count >= 2
    x: appSlot.iconWidth + appSlot.host.bubbleGap
    y: parent.height - height + Math.round(appSlot.host.line * 2)
    text: appSlot.host.bubbleText(appSlot.app.count)
    color: appSlot.tint
    font.family: appSlot.fontFamily
    font.pixelSize: appSlot.host.bubbleFont
    renderType: Text.NativeRendering
  }
}
