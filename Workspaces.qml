import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Workspaces in number order. Each pill shows the workspace number and the
// apps on it: up to three app icons (repeats of one app grouped with a count),
// where a terminal shows the program running in it (e.g. "nvim"). The number sits inside a small drawing of the screen the
// workspace lives on: a monitor on its foot, or a laptop screen on its deck.
// Right-click opens a popup to pick each screen's shape and color.
BarWidget {
  id: root
  moduleName: "io.github.apopovicius.wherespace"

  // Sizes follow the bar's own icon tokens so everything matches the other
  // bar icons: the screen drawing (foot or deck included) fills the bar's icon
  // canvas, app icons use the same canvas, and glyphs use the bar icon font.
  readonly property int iconSize: Style.bar.iconCanvas
  readonly property real line: Math.max(1, Math.round(Style.font.body / 9))
  // The app icon matches the monitor's screen (not its foot) and lines up
  // with it, so both halves of a pill carry the same visual weight.
  readonly property int appSize: Math.round(iconSize - line * 2.5)
  // App icons are drawn a bit larger than the screen and centered on it.
  // App icons match the bar's other icons (tray, menu): the bar icon size.
  readonly property int appIconSize: Style.bar.iconFont
  // Window-count bubble at an app icon's bottom-right.
  // Kept smaller than the app icon so it reads as a badge, not a second icon.
  readonly property int bubbleFont: Math.max(7, Math.round(Style.font.caption * 0.7))
  readonly property int bubbleHeight: bubbleFont + 3

  function bubbleText(count) {
    return "\u00d7" + (count > 99 ? "99+" : String(count))
  }

  function bubbleWidth(count) {
    return Math.ceil(countMetrics.advanceWidth(bubbleText(count)))
  }

  // The bubble sits beside the icon (never over it); the pill grows by the
  // bubble plus a small gap.
  readonly property real bubbleGap: Math.max(1, Math.round(line))

  function bubbleOverhang(count) {
    return count >= 2 ? bubbleGap + bubbleWidth(count) : 0
  }
  // Same space on both sides of the box as between its two halves.
  readonly property real normalPadding: Style.spaceReal(4)
  readonly property real tightPadding: Style.spaceReal(2)
  readonly property real pillPadding: tight ? tightPadding : normalPadding
  readonly property real pillSpacing: tight ? Style.space(1) : Style.space(4)
  // Box padding above and below the screen. The foot/deck sits inside the
  // bottom padding, so the box is symmetric around the screen, which is what
  // lines up with the rest of the bar.
  readonly property real boxPadding: (iconSize - appSize) + Style.spaceReal(2)

  // address (no 0x) -> { cls, inner } from `hyprctl clients`, refreshed on
  // window events. Quickshell's model gives structure; this adds what it lacks:
  // the window class and the program running inside a terminal.
  property var clientInfo: ({})
  // address (no 0x) -> when the window was opened (ms), so apps are listed in
  // the order they were opened. Stamped when a window first shows up; windows
  // that predate the widget fall back to their process's start time. Saved in
  // the session's runtime dir so a shell restart keeps the order.
  property var openedAt: ({})
  property bool openedAtLoaded: false
  // port -> { model, transform } from `hyprctl monitors`; Quickshell's monitor
  // objects don't reliably carry the model.
  property var monitorInfo: ({})
  property var iconCache: ({})

  // Named colors from the active theme's colors.toml (green, blue, ...). Each
  // screen is drawn in its own one so laptop vs monitor reads at a glance.
  property var themeColors: ({})
  readonly property string defaultLaptopColor: "green"
  readonly property var defaultMonitorColors: ["blue", "magenta", "cyan", "yellow", "orange", "red"]
  readonly property var paletteNames: ["green", "blue", "magenta", "cyan", "yellow", "orange", "red", "foreground"]
  readonly property var shapeKinds: [
    { kind: "monitor", name: "Monitor" },
    { kind: "laptop", name: "Laptop" },
    { kind: "ultrawide", name: "Ultrawide" },
    { kind: "portrait", name: "Portrait" },
    { kind: "tv", name: "TV" }
  ]

  // Per-screen choices from the settings popup, keyed by the screen's model
  // (or "built-in" for the laptop panel) so they survive a change of port:
  // { "DELL P2725D": { shape, color } }.
  // Saved to this widget's entry in shell.json as "screens".
  property var screenChoices: setting("screens", ({}))
  // "showApps" in shell.json: false keeps only the screen outlines and numbers.
  property bool showApps: setting("showApps", true) !== false
  onSettingsChanged: {
    screenChoices = setting("screens", ({}))
    showApps = setting("showApps", true) !== false
  }

  function setShowApps(value) {
    root.showApps = value
    runCommand(["omarchy", "bar", "set", root.moduleName, "showApps", value ? "true" : "false", "--json"])
  }

  // Settings popup state; the open/close/opened shape is what the bar's popup
  // coordinator expects from a panel owner.
  property bool settingsOpen: false
  property bool popoutSwitchClosing: false
  readonly property bool opened: settingsOpen
  function open() { settingsOpen = true }
  function close() { settingsOpen = false }
  function toggle() { settingsOpen ? close() : open() }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  // Apps shown on a workspace that isn't focused; the focused workspace
  // shows all of them.
  readonly property int maxApps: 2
  // Window classes treated as terminals: a bare one (just a shell) is drawn
  // as a console glyph, one running a program shows that program instead.
  readonly property var terminalClasses: ["foot", "footclient", "Alacritty", "kitty", "com.mitchellh.ghostty", "org.wezfurlong.wezterm"]
  readonly property string terminalGlyph: "\uDB80\uDD8D"

  // When the bar is too narrow (e.g. a laptop), step down until the widget
  // fits before the centered widgets: 2 icons, 1 icon, 1 icon with tight
  // spacing, numbers only (no icons, no "+N"), numbers only with tight
  // spacing, then only the focused workspace. The focused workspace keeps its
  // apps throughout.
  readonly property var fitLevels: [
    { apps: maxApps, tight: false },
    { apps: 1, tight: false },
    { apps: 1, tight: true },
    { apps: 0, tight: false },
    { apps: 0, tight: true },
    // Ultra narrow, the last resort: only the focused workspace is shown.
    { apps: 0, tight: true, focusedOnly: true }
  ]
  property real availableWidth: Infinity
  readonly property var fitLevel: {
    root.revision
    for (var i = 0; i < fitLevels.length; i++) {
      if (requiredWidth(fitLevels[i].apps, fitLevels[i].tight, fitLevels[i].focusedOnly === true) <= availableWidth) return fitLevels[i]
    }
    return fitLevels[fitLevels.length - 1]
  }
  readonly property int appsLimit: fitLevel.apps
  readonly property bool tight: fitLevel.tight
  readonly property bool focusedOnly: fitLevel.focusedOnly === true

  // The pill under the pointer, and whether its hover card is showing.
  property var hoverPill: null
  property bool hoverCardShown: false

  // Bumped on any Hyprland event so the groups re-evaluate.
  property int revision: 0

  // Names from other programs (window classes, process names): no control
  // characters, bounded length.
  function cleanName(value) {
    return String(value || "").replace(/[\u0000-\u001f\u007f]/g, "").slice(0, 128)
  }

  function stripAddress(address) {
    return String(address || "").replace(/^0x/, "")
  }

  function isInternalPanel(name) {
    return /^(eDP|LVDS|DSI)/.test(String(name || ""))
  }

  // Workspaces in number order, split into runs of consecutive workspaces on
  // the same screen; every pill in a run is drawn as that screen.
  function groups() {
    root.revision
    var screens = {}
    var rows = screenRows()
    for (var m = 0; m < rows.length; m++) screens[rows[m].port] = rows[m]

    var workspaces = Hyprland.workspaces.values.filter(function(ws) { return ws.id > 0 && ws.monitor })
    workspaces.sort(function(a, b) { return a.id - b.id })

    var result = []
    for (var i = 0; i < workspaces.length; i++) {
      var ws = workspaces[i]
      var last = result.length > 0 ? result[result.length - 1] : null
      if (last && last.monitor === ws.monitor.name) {
        last.ids.push(ws.id)
      } else {
        var screen = screens[ws.monitor.name] || { kind: "monitor", color: Color.accent, title: ws.monitor.name }
        result.push({ monitor: ws.monitor.name, kind: screen.kind, color: screen.color, label: screen.title, ids: [ws.id] })
      }
    }
    return result
  }

  // Dark or light text, whichever reads on `fill`; themes and the
  // wallpaper-derived transparent-bar colors can make either one the accent.
  function contrastOn(fill) {
    var c = Qt.color(fill)
    var luminance = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    return luminance > 0.55 ? "#111111" : "#ffffff"
  }

  function parseThemeColors(raw) {
    var colors = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6,8})"/)
      if (match) colors[match[1]] = match[2]
    }
    return colors
  }

  function resolveColor(name) {
    var value = String(name || "")
    if (/^#[0-9a-fA-F]{6,8}$/.test(value)) return value
    if (value === "foreground") return root.themeColors.foreground || Color.foreground
    return root.themeColors[value] || Color.accent
  }

  // Built-in panel: laptop. Rotated: portrait. Very wide: ultrawide.
  function defaultKind(monitor) {
    if (isInternalPanel(monitor.name)) return "laptop"
    var info = root.monitorInfo[monitor.name] || {}
    if (info.transform !== undefined && info.transform % 2 === 1) return "portrait"
    if (monitor.height > 0 && monitor.width / monitor.height >= 2.1) return "ultrawide"
    return "monitor"
  }

  // One row per connected screen, left to right, with its effective shape
  // and color: the saved choice, or the default.
  function screenRows() {
    root.revision
    root.themeColors
    root.screenChoices
    root.monitorInfo
    var monitors = Hyprland.monitors.values.slice()
    monitors.sort(function(a, b) { return a.x - b.x || a.y - b.y })

    var rows = []
    var externalIndex = 0
    for (var i = 0; i < monitors.length; i++) {
      var monitor = monitors[i]
      var laptop = isInternalPanel(monitor.name)
      var model = String((root.monitorInfo[monitor.name] || {}).model || "").trim()
      var key = laptop ? "built-in" : (model || monitor.name)
      var choice = (root.screenChoices && root.screenChoices[key]) || {}
      var fallbackColor = laptop ? root.defaultLaptopColor
        : root.defaultMonitorColors[externalIndex % root.defaultMonitorColors.length]
      if (!laptop) externalIndex++
      var colorName = choice.color || fallbackColor
      rows.push({
        key: key,
        port: monitor.name,
        title: laptop ? "Built-in display" : (model || monitor.name),
        kind: choice.shape || defaultKind(monitor),
        colorName: colorName,
        color: resolveColor(colorName)
      })
    }
    return rows
  }

  function colorChoices() {
    root.themeColors
    return root.paletteNames
      .filter(function(name) { return name === "foreground" || root.themeColors[name] })
      .map(function(name) { return { name: name, color: root.resolveColor(name) } })
  }

  function setScreenChoice(key, field, value) {
    var next = JSON.parse(JSON.stringify(root.screenChoices || {}))
    if (!next[key]) next[key] = {}
    next[key][field] = value
    saveScreenChoices(next)
  }

  function resetScreenChoices() {
    saveScreenChoices({})
  }

  // Update at once for a responsive popup, then persist to shell.json.
  function saveScreenChoices(next) {
    root.screenChoices = next
    runCommand(["omarchy", "bar", "set", root.moduleName, "screens", JSON.stringify(next), "--json"])
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) if (values[i].id === id) return values[i]
    return null
  }

  // Only { "<hex address>": <number> } entries are kept from the saved file.
  function parseOpenedAt(raw) {
    var clean = {}
    try {
      var data = JSON.parse(raw)
      if (data && typeof data === "object" && !Array.isArray(data)) {
        for (var key in data) {
          if (/^[0-9a-fA-F]{1,16}$/.test(key) && typeof data[key] === "number" && isFinite(data[key])) clean[key] = data[key]
        }
      }
    } catch (e) {}
    return clean
  }

  function openedTime(toplevel) {
    var stamp = root.openedAt[stripAddress(toplevel.address)]
    return stamp === undefined ? Number.MAX_SAFE_INTEGER : stamp
  }

  // Reading order within one side of a split: top to bottom, then left to
  // right; windows at the same spot (stacked, tabbed) by open time, then address.
  function readingOrder(a, b) {
    return (a.y - b.y) || (a.x - b.x)
      || (root.openedTime(a.t) - root.openedTime(b.t))
      || (stripAddress(a.t.address) < stripAddress(b.t.address) ? -1 : 1)
  }

  // The workspace's main split: the line (vertical first, else horizontal)
  // that no window crosses, closest to the middle. Returns [before, after],
  // or null when the windows can't be split.
  function mainSplit(items, horizontalAxis) {
    var pos = horizontalAxis ? "y" : "x"
    var size = horizontalAxis ? "h" : "w"
    var lo = Infinity, hi = -Infinity
    for (var i = 0; i < items.length; i++) {
      lo = Math.min(lo, items[i][pos])
      hi = Math.max(hi, items[i][pos] + items[i][size])
    }
    var middle = (lo + hi) / 2
    var best = null
    for (var c = 0; c < items.length; c++) {
      var line = items[c][pos] + items[c][size]
      var before = [], after = []
      for (var j = 0; j < items.length; j++) {
        if (items[j][pos] + items[j][size] <= line + 1) before.push(items[j])
        else if (items[j][pos] >= line) after.push(items[j])
        else { before = null; break }
      }
      if (!before || before.length === 0 || after.length === 0) continue
      if (!best || Math.abs(line - middle) < Math.abs(best.line - middle)) best = { line: line, before: before, after: after }
    }
    return best ? [best.before, best.after] : null
  }

  // On-screen order that follows the main split: one window from each side
  // in turn (left, right, left, right...), each side in reading order. With
  // a left/right split, the first two icons are the two halves.
  function layoutOrder(toplevels) {
    var items = toplevels.map(function(t) {
      var info = root.clientInfo[stripAddress(t.address)] || {}
      return { t: t, x: info.x || 0, y: info.y || 0, w: info.w || 0, h: info.h || 0 }
    })
    var sides = mainSplit(items, false) || mainSplit(items, true)
    if (!sides) return items.sort(readingOrder).map(function(item) { return item.t })
    var first = sides[0].sort(readingOrder)
    var second = sides[1].sort(readingOrder)
    var result = []
    for (var k = 0; k < Math.max(first.length, second.length); k++) {
      if (k < first.length) result.push(first[k].t)
      if (k < second.length) result.push(second[k].t)
    }
    return result
  }

  // Windows on the workspace, each with its label and title, in on-screen order.
  function windowsOn(workspace) {
    if (!workspace || !root.clientsLoaded) return []
    var toplevels = workspace.toplevels.values.slice()
    toplevels = root.layoutOrder(toplevels)
    var result = []
    for (var i = 0; i < toplevels.length; i++) {
      var label = windowLabel(toplevels[i])
      result.push({
        icon: label.icon, glyph: label.glyph || "", text: label.text, name: label.name,
        title: String(toplevels[i].title || ""), address: "0x" + stripAddress(toplevels[i].address)
      })
    }
    return result
  }

  // Windows grouped by app, in order of first appearance:
  // { apps: [{ icon, text, name, count }] (at most `limit`), more: <hidden apps> }.
  function appGroups(workspace, limit) {
    if (!root.showApps) return { apps: [], hidden: [], more: 0 }
    var windows = windowsOn(workspace)
    var groups = []
    var byKey = {}
    for (var i = 0; i < windows.length; i++) {
      var w = windows[i]
      var key = w.icon || w.glyph || w.text || w.name
      if (byKey[key] !== undefined) {
        groups[byKey[key]].count++
        groups[byKey[key]].addresses.push(w.address)
      } else {
        byKey[key] = groups.length
        groups.push({ key: key, icon: w.icon, glyph: w.glyph, text: w.text, name: w.name, count: 1, addresses: [w.address] })
      }
    }
    var shown = limit === undefined ? root.maxApps : limit
    return { apps: groups.slice(0, shown), hidden: groups.slice(shown), more: Math.max(0, groups.length - shown) }
  }

  function shapeWidth(kind) {
    var aspect = { monitor: 1.4, laptop: 1.4, ultrawide: 2.0, portrait: 0.72, tv: 1.55 }
    var screenHeight = Math.round(root.iconSize - root.line * 2.5)
    var screenWidth = Math.round(screenHeight * (aspect[kind] || aspect.monitor))
    return kind === "laptop" ? screenWidth + root.line * 6 : screenWidth
  }

  // Width the widget needs when showing at most `limit` apps per workspace,
  // worked out from the data so it can be decided before anything is drawn.
  function requiredWidth(limit, tightLevel, focusedOnlyLevel) {
    root.showApps
    var padding = tightLevel ? root.tightPadding : root.normalPadding
    var spacing = tightLevel ? Style.space(1) : Style.space(4)
    var total = 0
    var pills = 0
    var runs = groups()
    for (var r = 0; r < runs.length; r++) {
      for (var i = 0; i < runs[r].ids.length; i++) {
        // The focused workspace is always fully open, so count all its apps.
        var focusedHere = Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === runs[r].ids[i]
        if (focusedOnlyLevel && !focusedHere) continue
        // The focused workspace shows all its apps, except in ultra narrow
        // where it shows the first few and "+X".
        var apps = appGroups(workspaceById(runs[r].ids[i]), focusedHere ? (focusedOnlyLevel ? root.maxApps : 999) : limit)
        var width = shapeWidth(runs[r].kind)
        var items = 1
        for (var a = 0; a < apps.apps.length; a++) {
          var app = apps.apps[a]
          width += app.icon !== "" || app.glyph !== "" ? root.appIconSize : textMetrics.advanceWidth(app.text)
          width += bubbleOverhang(app.count)
          items++
        }
        // At the numbers-only levels "+N" is hidden too.
        if (apps.more > 0 && (limit > 0 || focusedHere)) {
          width += countMetrics.advanceWidth("+" + apps.more)
          items++
        }
        total += width + padding * (items - 1) + padding * 2
        pills++
      }
    }
    return total + spacing * Math.max(0, pills - 1) + root.trailingGap
  }

  // Visible bar widgets on this widget's own bar window with one of `ids`.
  // The bar's moduleWidgets() lookup returns nothing to third-party plugins,
  // so walk the window's items and match each widget's moduleName instead.
  function barItemsNamed(window, ids) {
    var found = []
    var stack = [window.contentItem]
    while (stack.length > 0) {
      var item = stack.pop()
      if (!item) continue
      if (item !== root && item.moduleName !== undefined && ids.indexOf(item.moduleName) !== -1
          && item.visible && item.width > 0) {
        found.push(item)
        continue
      }
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) stack.push(kids[i])
    }
    return found
  }

  // Room between this widget's left edge and the first widget of the bar's
  // center section on the same screen (the clock, by default), minus whatever
  // follows this widget in the left section.
  function measureAvailableWidth() {
    var window = root.QsWindow.window
    if (!window || !root.bar || root.vertical) {
      root.availableWidth = Infinity
      return
    }
    var layout = root.bar.layoutConfig || {}
    var ids = function(section) { return (layout[section] || []).map(function(entry) { return entry && entry.id }) }
    var left = (layout.left || []).map(function(entry) { return entry && entry.id })
    var followerIds = left.slice(left.indexOf(root.moduleName) + 1)

    var limit = window.width / 2
    var centerItems = barItemsNamed(window, ids("center"))
    for (var c = 0; c < centerItems.length; c++) limit = Math.min(limit, centerItems[c].mapToItem(null, 0, 0).x)

    var followers = 0
    var followerItems = left.indexOf(root.moduleName) === -1 ? [] : barItemsNamed(window, followerIds)
    for (var f = 0; f < followerItems.length; f++) followers += followerItems[f].width + Style.space(8)

    root.availableWidth = limit - root.mapToItem(null, 0, 0).x - followers - Style.space(16)
  }


  function setHover(pill, hovered) {
    if (hovered) {
      root.hoverPill = pill
      if (root.hoverCardShown) return
      hoverDelay.restart()
    } else if (root.hoverPill === pill) {
      hoverDelay.stop()
      root.hoverCardShown = false
      root.hoverPill = null
    }
  }

  // Icons come from desktop entries; only local files and the icon theme are
  // allowed, never a network URL or another image provider.
  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file:///") === 0 || value.indexOf("image://icon/") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(value)) return ""
    return Quickshell.iconPath(value, true)
  }

  // Chromium web apps get a class like "chrome-soundcloud.com__-Default";
  // match the domain against the Exec line of the installed web-app entries.
  function webAppEntry(cls) {
    var domain = cls.replace(/^(chrome|chromium|brave|msedge)-/, "").split("__")[0]
    if (!domain || domain.indexOf(".") === -1) return null
    var entries = DesktopEntries.applications.values
    for (var i = 0; i < entries.length; i++) {
      if (String(entries[i].execString || "").indexOf(domain) !== -1) return entries[i]
    }
    return null
  }

  function entryFor(name) {
    if (!name) return null
    if (/^(chrome|chromium|brave|msedge)-/.test(name)) {
      var web = webAppEntry(name)
      if (web) return web
    }
    return DesktopEntries.heuristicLookup(name)
  }

  // { icon, text, name } for the window: icon wins, text is the fallback.
  function windowLabel(toplevel) {
    if (!toplevel) return { icon: "", glyph: "", text: "", name: "" }
    var info = root.clientInfo[stripAddress(toplevel.address)] || {}
    var cls = info.cls || (toplevel.wayland ? toplevel.wayland.appId : "")
    var key = cls + "|" + (info.inner || "")
    if (root.iconCache[key]) return root.iconCache[key]

    var label
    if (!info.inner && root.terminalClasses.indexOf(cls) !== -1) {
      label = { icon: "", glyph: root.terminalGlyph, text: "", name: "Terminal" }
    } else if (info.inner) {
      var innerEntry = entryFor(info.inner)
      label = innerEntry && innerEntry.icon
        ? { icon: iconSource(innerEntry.icon), text: "", name: innerEntry.name || info.inner }
        : { icon: "", glyph: root.terminalGlyph, text: "", name: info.inner }
    } else {
      var entry = entryFor(cls)
      label = entry && entry.icon
        ? { icon: iconSource(entry.icon), text: "", name: entry.name || cls }
        : { icon: "", text: cls ? cls.charAt(0).toUpperCase() : "", name: cls }
    }
    if (cls) {
      // Window classes are chosen by apps, so keep the cache bounded.
      if (Object.keys(root.iconCache).length >= 256) root.iconCache = ({})
      root.iconCache[key] = label
    }
    return label
  }

  // Clicking an app icon targets the app, not one window of it: focus its
  // first window on that workspace (in on-screen order).
  // Values are checked against strict formats before they reach Hyprland's
  // Lua dispatcher, and the command runs without a shell.
  function focusApp(app) {
    if (!app || !app.addresses || app.addresses.length === 0) return
    var address = String(app.addresses[0])
    if (!/^0x[0-9a-fA-F]{1,16}$/.test(address)) return
    runCommand(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"address:" + address + "\" })"])
  }

  function focusWorkspace(id) {
    var workspace = Number(id)
    if (!Number.isInteger(workspace) || workspace < 1 || workspace > 9999) return
    runCommand(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + workspace + "\" })"])
  }

  function refreshClients() {
    // Wait for the saved open times, or every window would look brand new.
    if (!root.openedAtLoaded) return
    if (!clientsProc.running) clientsProc.running = true
  }

  // Stamp windows seen for the first time and forget closed ones. The first
  // pass after start-up can't know when windows opened, so it uses their
  // process's start time; after that, a new window is stamped "now".
  property bool firstClientsPass: true
  // False until window positions have been read once; app icons wait for it
  // so they never show in a provisional order right after a (re)load.
  property bool clientsLoaded: false

  function stampOpened(map) {
    var next = {}
    var now = Date.now()
    var changed = false
    for (var address in map) {
      if (root.openedAt[address] !== undefined) {
        next[address] = root.openedAt[address]
      } else {
        next[address] = root.firstClientsPass ? now - map[address].age * 1000 : now
        changed = true
      }
    }
    for (var old in root.openedAt) if (next[old] === undefined) changed = true
    root.firstClientsPass = false
    if (!changed) return
    root.openedAt = next
    if (root.runtimeDir !== "") openedAtFile.setText(JSON.stringify(next))
  }

  function refreshMonitors() {
    if (!monitorsProc.running) monitorsProc.running = true
  }

  // Commands run one at a time from a queue, as argument lists (never through
  // a shell), so quick successive settings changes are all saved in order.
  property var commandQueue: []

  function runCommand(argv) {
    root.commandQueue = root.commandQueue.concat([argv])
    if (!commandProc.running) root.runNextCommand()
  }

  function runNextCommand() {
    if (root.commandQueue.length === 0) return
    commandProc.command = root.commandQueue[0]
    root.commandQueue = root.commandQueue.slice(1)
    commandProc.running = true
  }

  Process {
    id: commandProc
    onExited: Qt.callLater(root.runNextCommand)
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        var map = {}
        try {
          var list = JSON.parse(text)
          for (var i = 0; i < (Array.isArray(list) ? list.length : 0); i++) {
            var m = list[i]
            if (!m || typeof m.name !== "string") continue
            map[m.name] = { model: typeof m.model === "string" ? m.model.slice(0, 64) : "", transform: Number(m.transform) || 0 }
          }
        } catch (e) {}
        root.monitorInfo = map
      }
    }
  }

  Process {
    id: clientsProc
    // One line per window: address, class, and for terminals the first
    // non-shell program in its process tree (empty for a bare shell).
    command: ["bash", "-c", `
      terminals=" foot footclient Alacritty kitty com.mitchellh.ghostty org.wezfurlong.wezterm "
      shells=" bash zsh fish sh dash nu "
      hyprctl clients -j | jq -r '.[] | [.address, .pid, .class, .at[0], .at[1], .size[0], .size[1]] | @tsv' |
      while IFS=$'\\t' read -r address pid cls x y w h; do
        inner=""
        if [[ $terminals == *" $cls "* ]]; then
          kid=$(pgrep -oP "$pid")
          while [[ -n $kid ]]; do
            comm=$(ps -o comm= -p "$kid")
            if [[ $shells == *" $comm "* ]]; then
              kid=$(pgrep -oP "$kid")
            else
              inner=$comm
              break
            fi
          done
        fi
        age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
        printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$address" "$cls" "$inner" "\${age:-0}" "$x" "$y" "$w" "$h"
      done
    `]
    stdout: StdioCollector {
      onStreamFinished: {
        var map = {}
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          if (parts.length < 2 || !parts[0]) continue
          map[root.stripAddress(parts[0])] = {
            cls: root.cleanName(parts[1]), inner: root.cleanName(parts[2]), age: Number(parts[3] || 0),
            x: Number(parts[4] || 0), y: Number(parts[5] || 0),
            w: Number(parts[6] || 0), h: Number(parts[7] || 0)
          }
        }
        root.clientInfo = map
        root.stampOpened(map)
        root.clientsLoaded = true
        root.revision++
      }
    }
  }

  // Window events arrive in bursts; coalesce before re-reading clients.
  Timer {
    id: refreshDebounce
    interval: 250
    onTriggered: root.refreshClients()
  }

  // Programs started inside an already-open terminal don't always change its
  // title, and some layout changes aren't announced, so poll as a fallback:
  // every 5 s while a terminal is open, every 15 s otherwise.
  readonly property bool hasTerminals: {
    for (var address in root.clientInfo) {
      if (root.terminalClasses.indexOf(root.clientInfo[address].cls) !== -1) return true
    }
    return false
  }

  Timer {
    interval: root.hasTerminals ? 5000 : 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshClients()
  }

  // Saved only in the per-user runtime dir; without one, open times stay in
  // memory (never a shared location like /tmp).
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""

  FileView {
    id: openedAtFile
    path: root.runtimeDir !== "" ? root.runtimeDir + "/omarchy-wherespace-opened.json" : ""
    printErrors: false
    onLoaded: {
      root.openedAt = root.parseOpenedAt(text())
      root.openedAtLoaded = true
      root.refreshClients()
    }
    onLoadFailed: {
      root.openedAtLoaded = true
      root.refreshClients()
    }
  }

  FileView {
    id: themeColorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.themeColors = root.parseThemeColors(text())
  }

  // Theme switches reach the shell over IPC and may swap the theme directory
  // without a file event; re-read whenever the shell's palette changes.
  Connections {
    target: Color
    function onAccentChanged() { themeColorsFile.reload() }
    function onForegroundChanged() { themeColorsFile.reload() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      root.revision++
      if (/window|workspace|monitor/.test(event.name)) refreshDebounce.restart()
      if (/monitor/.test(event.name)) root.refreshMonitors()
    }
  }

  Component.onCompleted: refreshMonitors()

  // Installed apps changed: forget cached icons so new apps get theirs.
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.iconCache = ({})
      root.revision++
    }
  }

  FontMetrics {
    id: countMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: root.bubbleFont
    font.bold: true
  }

  FontMetrics {
    id: textMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  // Positions settle after layout, so measure shortly after anything changes.
  Timer {
    id: measureTimer
    interval: 150
    onTriggered: root.measureAvailableWidth()
  }
  onRevisionChanged: measureTimer.restart()
  onXChanged: measureTimer.restart()
  onWidthChanged: measureTimer.restart()

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.measureAvailableWidth()
  }

  Timer {
    id: hoverDelay
    interval: 900
    onTriggered: root.hoverCardShown = root.hoverPill !== null && !root.settingsOpen
  }

  HoverCard {
    host: root
    pill: root.hoverPill
    shown: root.hoverCardShown && root.hoverPill !== null && !root.settingsOpen
  }

  SettingsPanel {
    host: root
    anchorItem: layout
    bar: root.bar
    owner: root
    open: root.settingsOpen
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: layout.implicitWidth + trailingGap
  implicitHeight: layout.implicitHeight

  GridLayout {
    id: layout
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rows: root.vertical ? -1 : 1
    columns: root.vertical ? 1 : -1
    columnSpacing: root.pillSpacing
    rowSpacing: root.pillSpacing

    Repeater {
      model: root.groups()

      GridLayout {
        id: group
        required property var modelData
        required property int index

        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: root.vertical ? -1 : 1
        columns: root.vertical ? 1 : -1
        columnSpacing: root.pillSpacing
        rowSpacing: root.pillSpacing

        Repeater {
          model: group.modelData.ids

          WidgetButton {
            id: pill
            required property int modelData

            readonly property var workspace: { root.revision; return root.workspaceById(modelData) }
            readonly property var apps: {
              root.revision
              return root.appGroups(workspace, root.focusedOnly && focused ? root.maxApps : root.appsLimit)
            }
            readonly property var screen: group.modelData
            readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
            readonly property bool shown: workspace !== null && workspace.active
            readonly property color tint: root.bar ? root.bar.barForeground : Color.foreground
            // The focused workspace shows all its apps; others show the first few.
            readonly property bool expanded: focused && !root.focusedOnly && pill.apps.hidden.length > 0

            bar: root.bar
            // Ultra narrow: only the focused workspace is shown.
            visible: !root.focusedOnly || focused
            hasVisualContent: true
            labelVisible: false
            // The hover card replaces the bar's plain-text tooltip.
            tooltipText: ""
            // The widget can be torn down before its pills (bar reload).
            Component.onDestruction: if (root) root.setHover(pill, false)

            HoverHandler {
              onHoveredChanged: root.setHover(pill, hovered)
            }
            // Everything is drawn at full strength in the bar's colors, like the
            // clock and tray; focus is shown by the filled screen alone.
            readonly property real artOpacity: 1
            fixedWidth: root.vertical ? root.barSize : Math.round(content.implicitWidth + root.pillPadding * 2)
            fixedHeight: root.vertical ? content.implicitHeight + Style.spaceReal(4) * 2 : root.barSize
            onPressed: function(button) {
              if (button === Qt.RightButton) root.settingsOpen ? root.close() : root.open()
              else root.focusWorkspace(modelData)
            }

            Row {
              id: content
              // Pinned to the left edge (not centered) so a sliding reveal only
              // grows to the right instead of re-centering everything each frame.
              anchors.left: parent.left
              anchors.leftMargin: root.pillPadding
              anchors.verticalCenter: parent.verticalCenter
              // Put the screen (not screen + foot) on the bar's center line, so
              // the numbers sit level with the text of the other bar widgets.
              anchors.verticalCenterOffset: Math.round((root.iconSize - root.appSize) / 2)
              // Fixed height: the reveal only ever changes the width, so opening
              // it slides sideways instead of re-centering everything vertically.
              height: root.iconSize
              spacing: root.pillPadding

              // The workspace number inside a drawing of its screen, in that
              // screen's color; the focused workspace is filled.
              ScreenShape {
                anchors.verticalCenter: parent.verticalCenter
                kind: group.modelData.kind
                color: group.modelData.color
                // Outline in the bar's text color, filled with the screen's color.
                borderColor: pill.tint
                filled: pill.focused
                label: pill.modelData === 10 ? "0" : String(pill.modelData)
                // Same color as the bar's window title text.
                labelColor: Util.alpha(pill.tint, 0.85)
                filledLabelColor: root.contrastOn(group.modelData.color)
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                fontSize: Math.round(Style.font.caption * 0.85)
                artOpacity: pill.artOpacity
                size: root.iconSize
                line: root.line
              }

              Repeater {
                model: pill.apps.apps

                AppIcon {
                  required property var modelData
                  anchors.top: parent.top
                  anchors.topMargin: Math.round((root.appSize - root.appIconSize) / 2)
                  host: root
                  app: modelData
                  tint: pill.tint
                  screenColor: pill.screen.color
                  focused: pill.focused
                  artOpacity: pill.artOpacity
                  onActivated: root.focusApp(modelData)
                }
              }

              // The other apps, shown while this is the focused workspace.
              // Hidden (and spacing-free) otherwise.
              Item {
                id: reveal
                visible: width > 0.5
                anchors.top: parent.top
                anchors.topMargin: Math.round((root.appSize - root.appIconSize) / 2)
                implicitWidth: pill.expanded ? hiddenApps.implicitWidth : 0
                // Whole pixels while animating, so neighbours don't jitter.
                width: Math.round(implicitWidth)
                height: root.appIconSize + root.bubbleHeight
                clip: true

                Row {
                  id: hiddenApps
                  spacing: root.pillPadding


                  Repeater {
                    model: pill.apps.hidden

                    AppIcon {
                      required property var modelData
                      host: root
                      app: modelData
                      tint: pill.tint
                      screenColor: pill.screen.color
                      focused: pill.focused
                      artOpacity: pill.artOpacity
                      onActivated: root.focusApp(modelData)
                    }
                  }
                }
              }

              // "+N" for the apps not shown, while the workspace isn't focused.
              Item {
                visible: width > 0.5
                anchors.top: parent.top
                anchors.topMargin: Math.round((root.appSize - height) / 2)
                implicitWidth: pill.apps.more > 0 && !pill.expanded && (root.appsLimit > 0 || pill.focused) ? moreText.implicitWidth : 0
                width: Math.round(implicitWidth)
                height: moreText.implicitHeight
                clip: true

                Text {
                  // Plain text only: titles and names come from other apps and must
                  // never be parsed as rich text (an <img> would make the shell fetch it).
                  textFormat: Text.PlainText
                  id: moreText
                  text: "+" + pill.apps.more
                  color: pill.tint
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  renderType: Text.NativeRendering
                }
              }
            }
          }
        }
      }
    }
  }
}
