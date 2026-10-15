import QtQuick

// A small drawing of a screen with a label (the workspace number) inside it.
// `size` is the full height, foot/deck/legs included; the screen itself is
// `screenHeight` tall and sits at the top, so callers can line it up.
Item {
  id: shape

  // monitor | laptop | ultrawide | portrait | tv
  property string kind: "monitor"
  property color color: "white"
  // Outline, foot and deck. Defaults to the screen color.
  property color borderColor: color
  property bool filled: false
  property string label: ""
  property color labelColor: color
  property color filledLabelColor: "white"
  property string fontFamily: ""
  property real fontSize: 10
  // Fades the drawing only; the label keeps its full color.
  property real artOpacity: 1
  property real size: 20
  property real line: 1

  // Monitor and laptop share one screen frame so their numbers read the same;
  // only what sits under the screen differs. Wider/taller kinds change the
  // proportion on purpose.
  readonly property var aspect: ({ monitor: 1.4, laptop: 1.4, ultrawide: 2.0, portrait: 0.72, tv: 1.55 })
  readonly property real screenHeight: Math.round(size - line * 2.5)
  readonly property real screenWidth: Math.round(screenHeight * (aspect[kind] || aspect.monitor))
  readonly property real deckWidth: screenWidth + line * 6

  function snap(value) {
    var ratio = Screen.devicePixelRatio || 1
    return Math.round(value * ratio) / ratio
  }

  width: kind === "laptop" ? deckWidth : screenWidth
  height: size

  Rectangle {
    id: screenFrame
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    width: shape.screenWidth
    height: shape.screenHeight
    radius: shape.line * 2
    // Filled with the screen's color only when focused; otherwise just the outline.
    color: shape.filled ? shape.color : "transparent"
    border.width: shape.line
    border.color: shape.borderColor
    opacity: shape.artOpacity
  }

  // Monitor, ultrawide, portrait: a short flat foot just under the screen.
  Rectangle {
    visible: shape.kind === "monitor" || shape.kind === "ultrawide" || shape.kind === "portrait"
    anchors.top: screenFrame.bottom
    anchors.topMargin: shape.line
    anchors.horizontalCenter: parent.horizontalCenter
    width: shape.screenWidth * (shape.kind === "portrait" ? 0.7 : shape.kind === "ultrawide" ? 0.3 : 0.45)
    height: shape.line * 1.5
    radius: shape.line
    color: shape.borderColor
    opacity: shape.artOpacity
  }

  // Laptop: keyboard deck that sticks out on both sides, in the same band
  // under the screen as the monitor's foot.
  Rectangle {
    visible: shape.kind === "laptop"
    anchors.top: screenFrame.bottom
    anchors.topMargin: Math.round(shape.line * 0.5)
    anchors.horizontalCenter: parent.horizontalCenter
    width: shape.deckWidth
    height: shape.line * 2
    radius: shape.line
    color: shape.borderColor
    opacity: shape.artOpacity
  }

  // TV: two short legs near the corners.
  Repeater {
    model: shape.kind === "tv" ? [0.16, 0.84] : []

    Rectangle {
      required property real modelData
      anchors.top: screenFrame.bottom
      x: Math.round(shape.screenWidth * modelData - width / 2)
      width: shape.line * 1.5
      height: shape.line * 2
      radius: shape.line / 2
      color: shape.borderColor
      opacity: shape.artOpacity
    }
  }

  // Center the digits' actual ink, not the text line box (which leaves room
  // for descenders and would sit the number off-center).
  TextMetrics {
    id: labelMetrics
    font: labelText.font
    text: shape.label
  }

  Text {
    id: labelText
    visible: shape.label !== ""
    // Snap to physical pixels: with fractional scaling a whole logical pixel
    // is more than one device pixel, which visibly shifts a small digit.
    x: shape.snap(screenFrame.x + screenFrame.width / 2 - (labelMetrics.tightBoundingRect.x + labelMetrics.tightBoundingRect.width / 2))
    y: shape.snap(screenFrame.y + screenFrame.height / 2 - (baselineOffset + labelMetrics.tightBoundingRect.y + labelMetrics.tightBoundingRect.height / 2))
    text: shape.label
    color: shape.filled ? shape.filledLabelColor : shape.labelColor
    font.family: shape.fontFamily
    font.pixelSize: shape.fontSize
    renderType: Text.NativeRendering
  }
}
