import QtQuick
import QtQuick.Effects
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons

// Radial presentation of the Omarchy menu: the current menu's rows sit on a
// ring of round buttons around a hub. All state (rows, cursor, navigation,
// activation) stays in Menu.qml; this file only draws it.
Item {
  id: radial

  property var menu: null
  property var model: null

  readonly property int count: radial.model ? radial.model.count : 0
  readonly property bool atRoot: !radial.menu || radial.menu.activeMenu === "root"
  // The hub shows the Apps entry (and the open category) while its rings are out.
  readonly property bool hubRoot: radial.atRoot && !radial.appsOpen
  readonly property var hubEntry: radial.appsOpen ? (radial.menu ? radial.menu.item(radial.ringId) : null) : radial.activeEntry
  // On the rings the hub mirrors the focused button's icon.
  readonly property var hubFocus: radial.appsOpen && !radial.carry ? radial.focusItem : null
  readonly property string hubImage: radial.hubFocus && radial.hubFocus.kind === "app" && radial.hubFocus.appIcon && radial.menu && radial.menu.appLibrary
    ? radial.menu.appLibrary.iconSource(radial.hubFocus.appIcon) : ""
  readonly property string hubGlyph: radial.hubFocus ? String(radial.hubFocus.glyph || radial.hubFocus.icon || "") : ""
  readonly property var activeEntry: radial.menu ? radial.menu.item(radial.menu.activeMenu) : null

  // Geometry. The ring grows with the number of items so labels never
  // collide, and the whole disc scales down if it would overflow the screen
  // (whichever of width or height is tighter, for portrait/narrow monitors).
  readonly property real buttonSize: Style.space(60)
  readonly property real labelHeight: Style.font.subtitle + Style.space(10)
  readonly property real ringRadius: Math.max(Style.space(150), radial.count * (radial.buttonSize + Style.space(40)) / (2 * Math.PI))
  readonly property real discRadius: radial.animOuter + radial.buttonSize / 2 + radial.labelHeight + Style.space(20)
  readonly property real hubRadius: Style.space(64)
  readonly property real fit: Math.min(1, (Math.min(radial.width, radial.height) - Style.space(80)) / (radial.discRadius * 2))

  // ------------------------------------------------- apps category rings
  //
  // Apps has too many entries for one ring. Clicking its node grows a second
  // ring of category buttons around the first; picking a category grows a
  // third ring holding just that category's apps.
  // The same rings serve Install: its submenus become the categories.
  // `ringId` is the root node that is fanned out ("apps" or "install").
  property bool appsOpen: false
  property string ringId: "apps"
  property string catId: ""
  property var groups: []
  property int focusLevel: 1   // 1 = category ring, 2 = app ring
  property int catIndex: 0
  property int appIndex: 0      // index into the whole category, not the page
  property int appPage: 0
  property string query: ""
  // Ten per page so keys 1–9 and 0 reach every button.
  readonly property int pageSize: 10
  property real catReveal: 0
  property real appReveal: 0

  // Rearranging the Apps groups. Only one of these is ever active:
  //  carry       — an app picked up (Ctrl+X / "Move to…"), waiting for a group
  //  naming      — typing a group name, or a Favourites command and its name
  //  actionTarget — the right-click / Menu-key options ring is out
  property var carry: null          // { row, fromCat }
  // { mode: "new" | "rename" | "cmdLine" | "cmdName", text, groupId?, cmdId?, command? }
  property var naming: null
  property var actionTarget: null   // { kind: "app" | "command", row } | { kind: "group", group }
  property int actionIndex: 0
  // The last Remove / Delete group, for Ctrl+Z: { label, fields, focus }.
  property var undoInfo: null
  readonly property bool modal: radial.naming !== null || radial.actionTarget !== null

  // The key cheat-sheet over the disc (? or F1).
  property bool helpOpen: false
  readonly property var helpSections: [
    { title: "Moving around", rows: [
      ["← →  Tab  wheel", "Move around the ring"],
      ["Enter  click", "Open or run"],
      ["1–9  0", "Pick a numbered item"],
      ["Home  End", "First / last item"],
      ["PgUp  PgDn  dots", "Turn pages (10 per ring)"],
      ["Esc  Backspace", "Go back"],
      ["Right-click disc", "Go back"],
      ["Click the hub", "Back out / close"],
      ["Type", "Search"]
    ] },
    { title: "Apps & groups", rows: [
      ["Ctrl+P", "Pin or unpin a favourite"],
      ["Ctrl+← →", "Move a favourite"],
      ["Shift+Enter", "New window of an open app"],
      ["Right-click  Menu", "Options for an app or group"],
      ["Ctrl+X … Enter", "Move an app to a group"],
      ["Ctrl+N", "New group"],
      ["F2", "Rename your group"],
      ["Menu → Add command", "Put a command in that group"],
      ["Delete", "Delete your group"],
      ["Ctrl+Z", "Undo a delete or remove"],
      ["Delete on an app", "Uninstall (asks first)"],
      ["?  F1", "Show / hide this help"]
    ] }
  ]

  // Keys for the help sheet, ahead of everything else on the rings.
  // Returns true when the key was consumed.
  function helpKey(event) {
    var k = event.key
    // "?" only while nothing is being typed, so it can still be searched for.
    var toggle = k === Qt.Key_F1 || (event.text === "?" && !radial.query && !radial.naming)
    if (radial.helpOpen) {
      // Any key closes the sheet without doing anything else.
      if (k !== Qt.Key_Shift && k !== Qt.Key_Control && k !== Qt.Key_Alt && k !== Qt.Key_Meta) radial.helpOpen = false
      return true
    }
    if (!toggle) return false
    radial.helpOpen = true
    return true
  }

  // The line under the disc: what's going on, or what the focused item is.
  readonly property string statusText: {
    if (radial.naming)
      return radial.namingPrompt[radial.naming.mode] + "“" + radial.naming.text + "▌”"
    if (radial.actionTarget)
      return "Options for " + (radial.actionTarget.row ? radial.actionTarget.row.label : radial.actionTarget.group.label)
    if (radial.carry) {
      var g = radial.groups[radial.catIndex]
      return "Move " + radial.carry.row.label + " to " + (g ? (g.newSlot ? "a new group" : g.label) : "…")
    }
    if (radial.undoInfo)
      return radial.undoInfo.label + "  ·  Ctrl+Z or click to undo"
    var f = radial.focusItem
    if (!f) return ""
    if (radial.appFocus && f.kind === "app" && radial.windowFor(f))
      return "Open  ·  Enter switches to it  ·  Shift+Enter starts another"
    if (f.detail || radial.appFocus || !f.apps) return String(f.detail || "")
    return f.apps.length + (f.apps.length === 1 ? " item" : " items")
  }

  readonly property var namingPrompt: ({
    "new": "New group: ", "rename": "Rename group: ",
    "cmdLine": "Command: ", "cmdName": "Name it: "
  })

  readonly property var allCatApps: {
    for (var i = 0; i < radial.groups.length; i++)
      if (radial.groups[i].id === radial.catId) return radial.groups[i].apps
    return []
  }
  readonly property int pageCount: Math.max(1, Math.ceil(radial.allCatApps.length / radial.pageSize))
  readonly property int pageStart: radial.appPage * radial.pageSize
  // What the app ring shows: one page of the open category.
  readonly property var catApps: radial.allCatApps.slice(radial.pageStart, radial.pageStart + radial.pageSize)
  readonly property var catEntry: {
    for (var i = 0; i < radial.groups.length; i++)
      if (radial.groups[i].id === radial.catId) return radial.groups[i]
    return null
  }
  readonly property int catPos: {
    for (var i = 0; i < radial.groups.length; i++)
      if (radial.groups[i].id === radial.catId) return i
    return 0
  }
  readonly property bool appFocus: radial.appsOpen && radial.catId !== "" && radial.focusLevel === 2
  readonly property var focusItem: {
    if (!radial.appsOpen) return null
    if (radial.actionTarget) return radial.actions[radial.actionIndex] || null
    if (radial.appFocus) return radial.allCatApps[radial.appIndex] || null
    return radial.groups[radial.catIndex] || null
  }
  readonly property bool searching: radial.query.trim() !== ""
  readonly property bool crowded: radial.groups.length > 8 || radial.fit < 1

  readonly property real ringGap: radial.buttonSize + radial.labelHeight + Style.space(24)
  // The categories take over the main ring's place; the apps ring goes around them.
  // Ring radius at which n neighbours sit `chord` apart (labels included).
  function radiusFor(n, chord) { return n < 3 ? 0 : chord / (2 * Math.sin(Math.PI / n)) }
  readonly property real labelChord: radial.buttonSize * 1.9 + Style.space(14)
  readonly property real catRadius: Math.max(radial.ringRadius, radial.radiusFor(radial.groups.length, radial.labelChord))
  readonly property bool appLabels: radial.catApps.length <= 10
  readonly property real appRadius: Math.max(radial.catRadius + radial.ringGap,
    radial.radiusFor(radial.catApps.length, radial.appLabels ? radial.labelChord : radial.buttonSize + Style.space(24)))
  readonly property real outerRadius: radial.catId !== "" ? radial.appRadius : (radial.appsOpen ? radial.catRadius : radial.ringRadius)
  // The disc grows and shrinks with the outermost ring instead of jumping.
  property real animOuter: radial.outerRadius
  Behavior on animOuter { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

  NumberAnimation on catReveal { id: catAnim; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic; running: false }
  NumberAnimation on appReveal { id: appAnim; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic; running: false }

  // Freedesktop "Categories" → the handful of groups worth a button. The
  // first matching rule wins, so a game that is also "Network" lands in Games.
  readonly property var categoryDefs: [
    { id: "ai",       label: "AI",       icon: "\udb81\udea9", keys: ["ArtificialIntelligence"],
      names: /^(claude|hermes|open ?code|chatgpt|perplexity|gemini|grok|copilot|ollama|lm ?studio|deepseek|mistral|le chat|alpaca|open ?webui)\b/i },
    { id: "games",    label: "Games",    icon: "\udb80\ude97", keys: ["Game"] },
    { id: "dev",      label: "Develop",  icon: "\udb80\udd74", keys: ["Development", "IDE"] },
    { id: "graphics", label: "Graphics", icon: "\udb80\udfd8", keys: ["Graphics"] },
    { id: "media",    label: "Media",    icon: "\udb81\udc0d", keys: ["AudioVideo", "Audio", "Video", "Player", "Music"] },
    { id: "internet", label: "Internet", icon: "\udb81\udd9f", keys: ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging"] },
    { id: "office",   label: "Office",   icon: "\udb80\ude19", keys: ["Office", "Spreadsheet", "WordProcessor"] },
    { id: "system",   label: "System",   icon: "\udb81\udc93", keys: ["System", "Settings", "Monitor", "TerminalEmulator", "PackageManager"] },
    { id: "utility",  label: "Utilities", icon: "\udb81\uddb7", keys: ["Utility", "Accessibility", "Archiving", "FileManager"] }
  ]

  // Loose actions of a ring menu share one category; its name per menu.
  readonly property var looseLabels: ({ install: "Packages", remove: "Packages" })

  // A menu's own children, grouped: each submenu is a category, and the loose
  // actions (Package, AUR, Web App, Theme…) share one category.
  function buildMenuGroups(id) {
    var m = radial.menu
    if (!m) return []
    var out = []
    var loose = { id: id + ".__loose", label: radial.looseLabels[id] || "General", icon: "", iconFont: "", apps: [] }
    var order = m.itemOrder

    function toRow(e) {
      return {
        itemId: e.id,
        kind: e.kind,
        target: String(e.target || e.id),
        action: String(e.action || ""),
        appId: "",
        appIcon: "",
        glyph: String(e.icon || "•"),
        iconFont: String(e.iconFont || ""),
        label: String(m.labelFor(e) || e.label || ""),
        detail: String(e.description || "")
      }
    }

    for (var i = 0; i < order.length; i++) {
      var e = m.item(order[i])
      if (!e || e.parent !== id || !m.isVisible(e)) continue
      if (e.kind === "menu" || e.kind === "link") {
        var tid = e.kind === "link" ? e.target : e.id
        var g = { id: e.id, label: String(e.label || ""), icon: String(e.icon || "•"), iconFont: String(e.iconFont || ""), apps: [] }
        for (var j = 0; j < order.length; j++) {
          var c = m.item(order[j])
          if (c && c.parent === tid && m.isVisible(c)) g.apps.push(toRow(c))
        }
        if (g.apps.length > 0) out.push(g)
        // A provider-backed menu (Font) has no static children to fan out.
        else if (e.provider) {
          if (!loose.icon) { loose.icon = String(e.icon || ""); loose.iconFont = String(e.iconFont || "") }
          loose.apps.push(toRow(e))
        }
      } else {
        if (!loose.icon) { loose.icon = String(e.icon || ""); loose.iconFont = String(e.iconFont || "") }
        loose.apps.push(toRow(e))
      }
    }
    if (loose.apps.length > 0) out.unshift(loose)
    return out
  }

  // Most-launched-lately apps: launch count, halved every two weeks.
  function recentIds() {
    var u = radial.menu ? radial.menu.usage : null
    if (!u) return []
    var now = Date.now()
    var scored = []
    for (var id in u) {
      var ageDays = Math.max(0, (now - (u[id].t || 0)) / 86400000)
      scored.push({ id: id, score: (u[id].n || 0) * Math.pow(0.5, ageDays / 14) })
    }
    scored.sort(function(a, b) { return b.score - a.score })
    return scored.slice(0, 8).map(function(x) { return x.id })
  }

  function buildGroups() {
    if (radial.ringId !== "apps") return radial.buildMenuGroups(radial.ringId)
    var defs = radial.categoryDefs
    var byId = ({})
    var byApp = ({})
    var out = []
    var rows = radial.menu && radial.menu.appLibrary ? radial.menu.appLibrary.sortedEntries("") : []
    var custom = radial.menu.menuState.groups || []
    var assign = radial.menu.menuState.assign || {}
    var customById = ({})
    for (var u = 0; u < custom.length; u++)
      customById[custom[u].id] = { id: custom[u].id, label: custom[u].label, icon: radial.initialOf(custom[u].label), custom: true }

    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue

      var cats = []
      try { for (var c = 0; c < entry.categories.length; c++) cats.push(String(entry.categories[c])) } catch (e) { }

      var def = null
      // Desktop files rarely say "AI" (Perplexity claims Utility), so match AI apps by name too.
      var name = String(radial.menu.appLibrary.entryName(entry) || entry.name || "")
      for (var n = 0; n < defs.length && !def; n++)
        if (defs[n].names && defs[n].names.test(name)) def = defs[n]
      for (var d = 0; d < defs.length && !def; d++)
        for (var k = 0; k < defs[d].keys.length; k++)
          if (cats.indexOf(defs[d].keys[k]) >= 0) { def = defs[d]; break }
      // Category-less launchers from Omarchy's web-app installer.
      if (!def && /webapp/.test(String(entry.execString || ""))) def = radial.webDef
      if (!def) def = radial.otherDef
      var auto = def
      // The user's own choice beats the rules; a deleted group is ignored.
      var want = assign[appId]
      if (want) def = customById[want] || radial.builtinDef(want) || auto

      if (!byId[def.id]) {
        byId[def.id] = { id: def.id, label: def.label, icon: def.icon, custom: !!def.custom, apps: [] }
        out.push(byId[def.id])
      }
      var row = {
        itemId: "apps." + appId,
        kind: "app",
        appId: appId,
        glyph: "",
        iconFont: "",
        label: String(radial.menu.appLibrary.entryName(entry) || appId),
        appIcon: String(entry.icon || ""),
        detail: String(radial.menu.appLibrary.entrySubtext(entry) || ""),
        search: radial.entrySearch(entry),
        wmClasses: [String(entry.startupClass || ""), appId].filter(function(c) { return c }).map(function(c) { return c.toLowerCase() }),
        groupId: def.id,
        autoCat: auto.id,
        autoLabel: auto.label
      }
      byId[def.id].apps.push(row)
      byApp[appId] = row
    }

    // Web Apps always exists: it carries the "New Web App…" shortcut.
    var addWeb = radial.menu.item("install.webapp")
    if (!byId.web && addWeb) {
      byId.web = { id: "web", label: radial.webDef.label, icon: radial.webDef.icon, apps: [] }
      out.push(byId.web)
    }

    // User groups show even while empty, so a new one can be filled.
    for (var c2 = 0; c2 < custom.length; c2++) {
      var cg = customById[custom[c2].id]
      if (!byId[cg.id]) { byId[cg.id] = { id: cg.id, label: cg.label, icon: cg.icon, custom: true, apps: [] }; out.push(byId[cg.id]) }
    }

    // Commands placed in a group join its apps; any whose group is gone
    // (or was never set) go to Favourites.
    var favCmds = []
    var allCmds = radial.menu.menuState.commands || []
    for (var uc = 0; uc < allCmds.length; uc++) {
      var gid = allCmds[uc].group || "fav"
      if (gid !== "fav" && !byId[gid]) {
        var bd = customById[gid] || radial.builtinDef(gid)
        if (bd) { byId[gid] = { id: gid, label: bd.label, icon: bd.icon, custom: !!bd.custom, apps: [] }; out.push(byId[gid]) }
      }
      if (gid !== "fav" && byId[gid]) byId[gid].apps.push(radial.commandRow(allCmds[uc], gid))
      else favCmds.push(allCmds[uc])
    }

    // Stable category order: user groups first as created, then the defs'
    // order with "Other" last; apps alphabetical.
    var order = custom.map(function(g) { return g.id })
      .concat(["ai", "games", "dev", "graphics", "media", "internet", "web", "office", "system", "utility", "other"])
    out.sort(function(a, b) { return order.indexOf(a.id) - order.indexOf(b.id) })
    for (var g = 0; g < out.length; g++)
      out[g].apps.sort(function(a, b) { return a.label.toLowerCase() < b.label.toLowerCase() ? -1 : (a.label.toLowerCase() > b.label.toLowerCase() ? 1 : 0) })

    if (byId.web && addWeb) byId.web.apps.push({
      itemId: addWeb.id,
      kind: "action",
      target: String(addWeb.id),
      action: String(addWeb.action || ""),
      appId: "",
      appIcon: "",
      glyph: String(addWeb.icon || "+"),
      iconFont: String(addWeb.iconFont || ""),
      label: "New Web App…",
      detail: "Create a launcher for a website"
    })

    var recent = radial.recentIds().filter(function(id) { return byApp[id] }).map(function(id) { return byApp[id] })
    if (recent.length > 0) out.unshift({ id: "recent", label: "Recent", icon: "󰋚", apps: recent })
    var pins = radial.sortFav(radial.menu.menuState.pins.filter(function(id) { return byApp[id] }).map(function(id) { return byApp[id] })
      .concat(favCmds.map(function(c) { return radial.commandRow(c, "fav") })))
    if (pins.length > 0) out.unshift({ id: "fav", label: "Favourites", icon: "\uf005", apps: pins })
    return out
  }

  // Favourites in the user's order; anything not yet placed keeps its spot at the end.
  function sortFav(items) {
    var order = radial.menu.menuState.favOrder || []
    var keyed = items.map(function(it, i) {
      var at = order.indexOf(it.itemId)
      return { it: it, k: at >= 0 ? at : order.length + i }
    })
    keyed.sort(function(a, b) { return a.k - b.k })
    return keyed.map(function(x) { return x.it })
  }

  // Move the focused favourite one place (no wrapping), and keep it focused.
  function moveFav(delta) {
    var apps = radial.allCatApps
    var i = radial.appIndex, j = i + delta
    if (radial.catId !== "fav" || j < 0 || j >= apps.length) return
    var ids = apps.map(function(a) { return a.itemId })
    var moved = ids[i]
    ids[i] = ids[j]
    ids[j] = moved
    radial.menu.patchState({ favOrder: ids })
    radial.refreshGroups()
    radial.focusItemId(moved)
  }

  // ------------------------------------------------ open windows
  // Window class → address of its most recently used window, read when the
  // rings open. Apps are matched by StartupWMClass or desktop id.
  property var openWindows: ({})
  function scanWindows() {
    var out = ({}), rank = ({})
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      var ipc = t.lastIpcObject || {}
      var cls = String(ipc["class"] || (t.wayland ? t.wayland.appId : "") || "").toLowerCase()
      var addr = String(ipc.address || t.address || "")
      if (!cls || !addr) continue
      if (addr.indexOf("0x") !== 0) addr = "0x" + addr
      var r = ipc.focusHistoryID !== undefined ? Number(ipc.focusHistoryID) : 9999
      if (out[cls] === undefined || r < rank[cls]) { out[cls] = addr; rank[cls] = r }
    }
    radial.openWindows = out
  }
  function windowFor(row) {
    var c = row && row.wmClasses ? row.wmClasses : []
    for (var i = 0; i < c.length; i++) if (radial.openWindows[c[i]]) return radial.openWindows[c[i]]
    return ""
  }

  // Single-quote a string for bash.
  function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  // A terminal command opens in Omarchy's terminal. It closes when the
  // command ends, unless it failed: then it waits so the error can be read.
  function terminalAction(command) {
    // A subshell, so an `exit` in the command still reaches the check.
    var script = "(\n" + command + "\n)\ns=$?; if [ $s -ne 0 ]; then printf '\\n[exited with %s] Press Enter to close' $s; read -r _; fi"
    return "omarchy-launch-tui --app-id=org.omarchy.radial-command bash -lc " + radial.shellQuote(script)
  }

  // A user command as a Favourites button; it runs through the action path.
  function commandRow(c, groupId) {
    return {
      itemId: "cmd." + c.id,
      kind: "command",
      cmdId: c.id,
      command: String(c.command),
      terminal: !!c.terminal,
      search: String(c.command),
      action: c.terminal ? radial.terminalAction(c.command) : String(c.command),
      appId: "",
      appIcon: "",
      glyph: "\uf120",
      iconFont: "",
      label: String(c.label),
      detail: (c.terminal ? "In terminal · " : "") + String(c.command),
      groupId: groupId || "fav"
    }
  }

  // Each category gets its own gradient from the theme palette.
  function accentA(i) {
    var p = radial.menu ? radial.menu.accentPalette : []
    return p && p.length > 0 ? p[i % p.length] : (radial.menu ? radial.menu.ringStart : "white")
  }
  function accentB(i) {
    var p = radial.menu ? radial.menu.accentPalette : []
    return p && p.length > 0 ? p[(i + 1) % p.length] : (radial.menu ? radial.menu.ringEnd : "white")
  }

  readonly property var webDef: ({ id: "web", label: "Web Apps", icon: "󰌹" })
  readonly property var otherDef: ({ id: "other", label: "Other", icon: "󰇘" })

  // A built-in group by id, for apps moved into one.
  function builtinDef(id) {
    for (var i = 0; i < radial.categoryDefs.length; i++)
      if (radial.categoryDefs[i].id === id) return radial.categoryDefs[i]
    if (id === "web") return radial.webDef
    if (id === "other") return radial.otherDef
    return null
  }

  // A user group's button shows its initial.
  function initialOf(label) { return String(label || "?").trim().charAt(0).toUpperCase() || "?" }

  function openApps(id) {
    radial.scanWindows()
    radial.ringId = id || "apps"
    var built = radial.buildGroups()
    if (built.length === 0) return false
    radial.groups = built
    radial.catId = ""
    radial.catIndex = 0
    var last = radial.menu.recall("ring:" + radial.ringId)
    if (last)
      for (var g = 0; g < built.length; g++)
        if (built[g].id === last.cat) { radial.catIndex = g; break }
    radial.appIndex = 0
    radial.appPage = 0
    radial.query = ""
    radial.focusLevel = 1
    radial.appsOpen = true
    catAnim.restart()
    return true
  }

  function closeApps() {
    radial.carry = null
    radial.naming = null
    radial.actionTarget = null
    radial.undoInfo = null
    radial.appsOpen = false
    radial.catId = ""
    radial.query = ""
    radial.appPage = 0
    radial.catReveal = 0
    radial.appReveal = 0
  }

  // Step back one level: search → apps → categories → root.
  function back() {
    if (radial.naming) {
      radial.naming = null
    } else if (radial.actionTarget) {
      radial.closeActions()
    } else if (radial.carry) {
      radial.cancelCarry()
    } else if (radial.searching) {
      radial.setQuery("")
    } else if (radial.catId !== "") {
      radial.catId = ""
      radial.appPage = 0
      radial.appReveal = 0
      radial.focusLevel = 1
    } else {
      radial.closeApps()
    }
  }

  function openCategory(i) {
    if (i < 0 || i >= radial.groups.length) return
    radial.catIndex = i
    radial.catId = radial.groups[i].id
    radial.setApp(0)
    var last = radial.menu.recall("ring:" + radial.ringId)
    if (last && last.cat === radial.catId) {
      var apps = radial.groups[i].apps
      for (var a = 0; a < apps.length; a++)
        if (apps[a].itemId === last.item) { radial.setApp(a); break }
    }
    radial.focusLevel = 2
    appAnim.restart()
  }

  function setApp(i) {
    radial.appIndex = i
    radial.appPage = Math.floor(i / radial.pageSize)
  }

  function changePage(delta) {
    if (radial.catId === "" || radial.pageCount < 2) return
    radial.appPage = (radial.appPage + delta + radial.pageCount) % radial.pageCount
    radial.appIndex = radial.pageStart
    radial.focusLevel = 2
  }

  // i indexes the whole category. An app that's already open is switched
  // to, unless newCopy asks for another one.
  function launchApp(i, newCopy) {
    var apps = radial.allCatApps
    if (i < 0 || i >= apps.length) return
    var it = apps[i]
    radial.menu.remember("ring:" + radial.ringId, { cat: radial.catId, item: it.itemId })
    var win = it.kind === "app" && !newCopy ? radial.windowFor(it) : ""
    if (win) radial.menu.switchToWindow(it.appId, win)
    else if (it.kind === "app") radial.menu.launchApp(it.appId, it.label)
    else if (it.kind === "menu" || it.kind === "link") radial.menu.setActiveMenu(it.target, true, false)
    else radial.menu.applySelected(it.itemId, it.action)
  }

  // Pin or unpin the focused app, then rebuild the rings around it.
  function togglePinHot() {
    var it = radial.hotApp()
    if (!it) return
    var keep = it.itemId
    radial.menu.togglePin(it.appId)
    radial.groups = radial.buildGroups()
    var pos = -1
    for (var g = 0; g < radial.groups.length; g++)
      if (radial.groups[g].id === radial.catId) pos = g
    if (pos < 0) {
      // Unpinned the last favourite: the category is gone, step back out.
      radial.catId = ""
      radial.focusLevel = 1
      radial.catIndex = 0
      return
    }
    radial.catIndex = pos
    var apps = radial.groups[pos].apps
    var at = 0
    for (var a = 0; a < apps.length; a++) if (apps[a].itemId === keep) at = a
    radial.setApp(Math.min(at, apps.length - 1))
  }

  // The app under the cursor, for the uninstall shortcut.
  function hotApp() {
    if (!radial.appFocus) return null
    var it = radial.allCatApps[radial.appIndex]
    return it && it.kind === "app" ? it : null
  }

  // ------------------------------------------------ rearranging groups

  // Rebuild the rings. While an app is carried, Favourites and Recent
  // aren't places it can go, and a "New group" slot is added.
  function refreshGroups() {
    var built = radial.buildGroups()
    if (radial.carry) {
      built = built.filter(function(g) { return g.id !== "fav" && g.id !== "recent" })
      built.push({ id: "__new", label: "New group", icon: "\uf067", newSlot: true, apps: [] })
    }
    radial.groups = built
  }

  function groupPos(id) {
    for (var i = 0; i < radial.groups.length; i++) if (radial.groups[i].id === id) return i
    return -1
  }

  function focusItemId(itemId) {
    var apps = radial.allCatApps
    for (var a = 0; a < apps.length; a++) if (apps[a].itemId === itemId) { radial.setApp(a); return }
  }

  // Open a group with one app focused, e.g. where a moved app landed.
  function showApp(groupId, itemId) {
    var p = radial.groupPos(groupId)
    if (p < 0) { radial.catId = ""; radial.focusLevel = 1; return }
    radial.openCategory(p)
    radial.focusItemId(itemId)
  }

  function startCarry() {
    if (radial.ringId !== "apps") return
    var it = radial.hotApp()
    if (!it) return
    radial.carry = { row: it, fromCat: radial.catId }
    radial.query = ""
    radial.catId = ""
    radial.appReveal = 0
    radial.focusLevel = 1
    radial.refreshGroups()
    radial.catIndex = Math.max(0, radial.groupPos(it.groupId))
  }

  function cancelCarry() {
    var c = radial.carry
    radial.carry = null
    radial.refreshGroups()
    if (c) radial.showApp(c.fromCat, c.row.itemId)
  }

  // Drop the carried app on group i (or name a new group for it).
  function dropOn(i) {
    var g = radial.groups[i]
    if (!g || !radial.carry) return
    if (g.newSlot) { radial.naming = { mode: "new", groupId: "", text: "" }; return }
    var row = radial.carry.row
    radial.menu.assignApp(row.appId, g.id === row.autoCat ? "" : g.id)
    radial.carry = null
    radial.refreshGroups()
    radial.showApp(g.id, row.itemId)
  }

  function commitName() {
    var n = radial.naming
    var t = n ? n.text.trim() : ""
    if (!t) return
    if (n.mode === "cmdLine" || n.mode === "cmdName") { radial.commitCommand(n, t); return }
    radial.naming = null
    if (n.mode === "rename") {
      radial.menu.renameGroup(n.groupId, t)
      radial.refreshGroups()
      return
    }
    var id = radial.menu.createGroup(t)
    if (radial.carry) {
      var row = radial.carry.row
      radial.menu.assignApp(row.appId, id)
      radial.carry = null
      radial.refreshGroups()
      radial.showApp(id, row.itemId)
    } else {
      radial.refreshGroups()
      radial.catId = ""
      radial.appReveal = 0
      radial.focusLevel = 1
      radial.catIndex = Math.max(0, radial.groupPos(id))
    }
  }

  // Keep the state fields an edit is about to change, so Ctrl+Z can put them back.
  // usage, when given, is the launch history to restore as well.
  function offerUndo(label, names, focus, usage) {
    var fields = ({})
    for (var i = 0; i < names.length; i++) fields[names[i]] = radial.menu.menuState[names[i]]
    radial.undoInfo = { label: label, fields: fields, focus: focus, usage: usage || null }
    undoTimer.restart()
  }

  function undo() {
    var u = radial.undoInfo
    if (!u) return
    radial.undoInfo = null
    if (Object.keys(u.fields).length > 0) radial.menu.patchState(u.fields)
    if (u.usage) radial.menu.setUsage(u.usage)
    radial.refreshGroups()
    if (u.focus.itemId) radial.showApp(u.focus.groupId, u.focus.itemId)
    else {
      radial.catId = ""
      radial.appReveal = 0
      radial.focusLevel = 1
      radial.catIndex = Math.max(0, radial.groupPos(u.focus.groupId))
    }
  }

  Timer { id: undoTimer; interval: 10000; onTriggered: radial.undoInfo = null }

  function deleteGroup(id) {
    var p = radial.groupPos(id)
    radial.offerUndo("Deleted “" + (p >= 0 ? radial.groups[p].label : "") + "”", ["groups", "assign"], { groupId: id })
    radial.menu.deleteGroup(id)
    if (radial.catId === id) { radial.catId = ""; radial.appReveal = 0; radial.focusLevel = 1 }
    radial.refreshGroups()
    radial.catIndex = Math.min(radial.catIndex, radial.groups.length - 1)
  }

  // What the options ring offers for its target.
  readonly property var actions: {
    var t = radial.actionTarget
    if (!t) return []
    if (t.kind === "app") {
      var a = [
        { id: "pin", label: radial.menu.isPinned(t.row.appId) ? "Unpin" : "Pin to Favourites", icon: "\uf005" },
        { id: "move", label: "Move to…", icon: "\uf047" }
      ]
      if (t.row.groupId !== t.row.autoCat) a.push({ id: "reset", label: "Back to " + t.row.autoLabel, icon: "\uf0e2" })
      if (radial.catId === "recent") a.push({ id: "forget", label: "Forget", icon: "\uf1da" })
      a.push({ id: "uninstall", label: "Uninstall", icon: "\uf1f8" })
      return a
    }
    if (t.kind === "command") return [
      { id: "cmdEdit", label: "Edit command", icon: "\uf120" },
      { id: "cmdRename", label: "Rename", icon: "\uf040" },
      { id: "cmdTerm", label: t.row.terminal ? "Run without terminal" : "Run in terminal", icon: t.row.terminal ? "\uf28d" : "\uf489" },
      { id: "cmdRemove", label: "Remove", icon: "\uf1f8" }
    ]
    if (t.group.id === "recent") return [{ id: "recentClear", label: "Clear Recent", icon: "\uf1f8" }]
    var g = [{ id: "new", label: "New group", icon: "\uf067" }, { id: "cmdAdd", label: "Add command", icon: "\uf120" }]
    if (t.group.custom) g.unshift({ id: "rename", label: "Rename", icon: "\uf040" }, { id: "delete", label: "Delete group", icon: "\uf1f8" })
    return g
  }

  // Options for whatever has focus (Menu key / Shift+F10).
  function openActionsForFocus() {
    if (radial.ringId !== "apps") return
    if (radial.appFocus) {
      var it = radial.allCatApps[radial.appIndex]
      if (it && (it.kind === "app" || it.kind === "command")) radial.openActions({ kind: it.kind, row: it })
    } else {
      var g = radial.groups[radial.catIndex]
      if (g) radial.openActions({ kind: "group", group: g })
    }
  }

  function openActions(target) {
    radial.actionIndex = 0
    radial.actionTarget = target
  }

  function closeActions() { radial.actionTarget = null }

  function runAction(i) {
    var a = radial.actions[i]
    var t = radial.actionTarget
    if (!a) return
    radial.closeActions()
    if (a.id === "pin") radial.togglePinHot()
    else if (a.id === "move") radial.startCarry()
    else if (a.id === "uninstall") radial.menu.requestDeleteSelected()
    else if (a.id === "reset") {
      radial.menu.assignApp(t.row.appId, "")
      radial.refreshGroups()
      radial.showApp(t.row.autoCat, t.row.itemId)
    }
    else if (a.id === "rename") radial.naming = { mode: "rename", groupId: t.group.id, text: t.group.label }
    else if (a.id === "delete") radial.deleteGroup(t.group.id)
    else if (a.id === "new") radial.naming = { mode: "new", groupId: "", text: "" }
    else if (a.id === "cmdAdd") radial.naming = { mode: "cmdLine", cmdId: "", target: t.group.id, text: "" }
    else if (a.id === "cmdEdit") radial.naming = { mode: "cmdLine", cmdId: t.row.cmdId, text: t.row.command }
    else if (a.id === "cmdTerm") {
      radial.menu.updateCommand(t.row.cmdId, { terminal: !t.row.terminal })
      radial.refreshGroups()
      radial.showApp(t.row.groupId, t.row.itemId)
    }
    else if (a.id === "cmdRename") radial.naming = { mode: "cmdName", cmdId: t.row.cmdId, command: "", text: t.row.label }
    else if (a.id === "cmdRemove") {
      radial.offerUndo("Removed “" + t.row.label + "”", ["commands"], { groupId: t.row.groupId, itemId: t.row.itemId })
      radial.menu.removeCommand(t.row.cmdId)
      radial.afterRemoval()
    }
    else if (a.id === "forget") {
      radial.offerUndo("Forgot “" + t.row.label + "”", [], { groupId: "recent", itemId: t.row.itemId }, radial.menu.usage)
      radial.menu.forgetUsage(t.row.appId)
      radial.afterRemoval()
    }
    else if (a.id === "recentClear") {
      radial.offerUndo("Cleared Recent", [], { groupId: "recent" }, radial.menu.usage)
      radial.menu.setUsage({})
      radial.afterRemoval()
    }
  }

  // After something left the open group: stay on a neighbour, or step out
  // if the group is now gone.
  function afterRemoval() {
    var open = radial.catId
    radial.refreshGroups()
    if (open === "" ) { radial.catIndex = Math.min(radial.catIndex, radial.groups.length - 1); return }
    if (radial.groupPos(open) < 0) { radial.catId = ""; radial.appReveal = 0; radial.focusLevel = 1; radial.catIndex = 0 }
    else radial.setApp(Math.max(0, Math.min(radial.appIndex, radial.allCatApps.length - 1)))
  }

  // Where a command lives now.
  function commandGroup(cmdId) {
    var cs = radial.menu.menuState.commands || []
    for (var i = 0; i < cs.length; i++)
      if (cs[i].id === cmdId) return radial.groupPos(cs[i].group || "") >= 0 ? cs[i].group : "fav"
    return "fav"
  }

  // A name for a new command: its program's name, capitalised ("btop -t" → "Btop").
  function suggestName(command) {
    var w = String(command).trim().split(/\s+/)[0] || ""
    w = w.split("/").pop()
    return (w.charAt(0).toUpperCase() + w.slice(1)).slice(0, 24)
  }

  // Command typing and naming both end here.
  function commitCommand(n, t) {
    if (n.mode === "cmdLine" && n.cmdId) {
      radial.menu.updateCommand(n.cmdId, { command: t })
      radial.naming = null
      radial.refreshGroups()
      radial.showApp(radial.commandGroup(n.cmdId), "cmd." + n.cmdId)
    } else if (n.mode === "cmdLine") {
      // Then ask for its name.
      radial.naming = { mode: "cmdName", cmdId: "", command: t, target: n.target, text: radial.suggestName(t) }
    } else {
      radial.naming = null
      var id = n.cmdId
      if (id) radial.menu.updateCommand(id, { label: t })
      else id = radial.menu.addCommand(t, n.command, n.target === "recent" ? "fav" : n.target)
      radial.refreshGroups()
      radial.showApp(radial.commandGroup(id), "cmd." + id)
    }
  }

  function printable(event) {
    return event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
      && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)
  }

  // Keys while a group name is being typed: everything goes to the name.
  function nameKey(event) {
    var k = event.key
    var n = radial.naming
    if (k === Qt.Key_Escape) radial.naming = null
    else if (k === Qt.Key_Return || k === Qt.Key_Enter) radial.commitName()
    else if (k === Qt.Key_V && event.modifiers === Qt.ControlModifier) pasteProc.running = true
    else if (Util.editsFilter(event, n.text)) radial.setNamingText(Util.editedFilter(event, n.text))
    else if (radial.printable(event)) radial.setNamingText(n.text + event.text)
    return true
  }

  // Commands may be long; names stay short enough for a button.
  function namingLimit() { return radial.naming && radial.naming.mode === "cmdLine" ? 1000 : 24 }

  function setNamingText(text) {
    var n = radial.naming
    if (!n) return
    var next = ({})
    for (var k in n) next[k] = n[k]
    next.text = String(text).slice(0, radial.namingLimit())
    radial.naming = next
  }

  // Ctrl+V while typing a name or command: one line from the clipboard.
  Process {
    id: pasteProc
    command: ["wl-paste", "--no-newline", "--type", "text"]
    stdout: StdioCollector {
      onStreamFinished: {
        var line = String(this.text || "").split("\n")[0]
        if (radial.naming && line) radial.setNamingText(radial.naming.text + line)
      }
    }
  }

  function actionKey(event) {
    var k = event.key
    var n = radial.actions.length
    if (k === Qt.Key_Escape || k === Qt.Key_Backspace || k === Qt.Key_Menu) radial.closeActions()
    else if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_Tab) radial.actionIndex = (radial.actionIndex + 1) % n
    else if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_Backtab) radial.actionIndex = (radial.actionIndex - 1 + n) % n
    else if (k === Qt.Key_Return || k === Qt.Key_Enter) radial.runAction(radial.actionIndex)
    else if (k >= Qt.Key_1 && k <= Qt.Key_9 && k - Qt.Key_1 < n) radial.runAction(k - Qt.Key_1)
    return true
  }

  function carryKey(event) {
    var k = event.key
    var ctrl = event.modifiers & Qt.ControlModifier
    if (k === Qt.Key_Escape || k === Qt.Key_Backspace) radial.cancelCarry()
    else if (k === Qt.Key_Return || k === Qt.Key_Enter || (ctrl && k === Qt.Key_V)) radial.dropOn(radial.catIndex)
    else if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_Tab) radial.step(1)
    else if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_Backtab) radial.step(-1)
    else if (k === Qt.Key_Home || k === Qt.Key_End) radial.jump(k === Qt.Key_End)
    else if (k >= Qt.Key_1 && k <= Qt.Key_9) radial.dropOn(k - Qt.Key_1)
    else if (k === Qt.Key_0) radial.dropOn(9)
    return true
  }

  // Mouse on the rings while the options ring or a name is up: a click
  // elsewhere just closes the options; nothing else reacts.
  function pointerBlocked() {
    if (radial.naming) return true
    if (radial.actionTarget) { radial.closeActions(); return true }
    return false
  }

  // What else an app answers to: its generic name ("Web Browser"), keywords,
  // description and desktop id, so "browser" finds Chrome.
  function entrySearch(entry) {
    var kw = ""
    try { if (entry.keywords) kw = Array.prototype.join.call(entry.keywords, " ") } catch (e) { }
    return [entry.genericName, kw, entry.comment, entry.id].join(" ")
  }

  // Lower-cased words, with camelCase and . _ - / split apart.
  function wordsOf(text) {
    return " " + String(text || "").replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/[._:\/\\-]+/g, " ").toLowerCase().replace(/\s+/g, " ") + " "
  }

  // -1 when the item doesn't fit the search; higher is a better match.
  // The name always beats the extra text; every word typed must be found.
  function matchScore(it) {
    var q = radial.query.trim().toLowerCase()
    if (q === "") return 0
    var l = String(it.label || "").toLowerCase()
    if (l.indexOf(q) === 0) return 4
    if (l.indexOf(" " + q) >= 0) return 3
    if (l.indexOf(q) >= 0) return 2
    var hay = radial.wordsOf(it.label + " " + (it.search || it.appId || ""))
    var words = q.split(/\s+/)
    for (var i = 0; i < words.length; i++)
      if (hay.indexOf(" " + words[i]) < 0) return -1
    return 1
  }

  function groupMatches(g) {
    var n = 0
    for (var i = 0; i < g.apps.length; i++) if (radial.matchScore(g.apps[i]) >= 0) n++
    return n
  }

  readonly property int totalMatches: {
    if (!radial.searching) return 0
    var n = 0
    for (var i = 0; i < radial.groups.length; i++) n += radial.groupMatches(radial.groups[i])
    return n
  }

  // Typing filters the rings in place: non-matches dim, and focus jumps to
  // the best hit so Enter launches it.
  function setQuery(q) {
    radial.query = q
    if (!radial.searching) return
    var best = -1, bg = -1, bi = -1
    for (var g = 0; g < radial.groups.length; g++) {
      var apps = radial.groups[g].apps
      for (var i = 0; i < apps.length; i++) {
        var s = radial.matchScore(apps[i])
        if (s > best) { best = s; bg = g; bi = i }
      }
    }
    if (bg < 0) return
    if (radial.catId !== radial.groups[bg].id) radial.openCategory(bg)
    radial.focusLevel = 2
    radial.setApp(bi)
  }

  // Next index in the direction of delta whose item still matches the search.
  function stepIndex(cur, n, delta, ok) {
    for (var k = 0; k < n; k++) {
      cur = (cur + delta + n) % n
      if (ok(cur)) return cur
    }
    return cur
  }

  function step(delta) {
    if (radial.focusLevel === 2 && radial.catId !== "") {
      var apps = radial.allCatApps
      if (apps.length > 0)
        radial.setApp(radial.stepIndex(radial.appIndex, apps.length, delta, function(i) { return radial.matchScore(apps[i]) >= 0 }))
    } else if (radial.groups.length > 0) {
      radial.catIndex = radial.stepIndex(radial.catIndex, radial.groups.length, delta, function(i) { return !radial.searching || radial.groupMatches(radial.groups[i]) > 0 })
    }
  }

  function hintFor(i) { return i < 9 ? String(i + 1) : (i === 9 ? "0" : "") }

  function jump(toEnd) {
    var onApps = radial.focusLevel === 2 && radial.catId !== ""
    var n = onApps ? radial.allCatApps.length : radial.groups.length
    if (n === 0) return
    // Step once from just outside either end so the search filter applies.
    var cur = radial.stepIndex(toEnd ? 0 : n - 1, n, toEnd ? -1 : 1, onApps
      ? function(i) { return radial.matchScore(radial.allCatApps[i]) >= 0 }
      : function(i) { return !radial.searching || radial.groupMatches(radial.groups[i]) > 0 })
    if (onApps) radial.setApp(cur)
    else radial.catIndex = cur
  }

  // 1–9 and 0 pick the numbered button on whichever ring has focus.
  function hintPick(n) {
    if (radial.appFocus) {
      var gi = radial.pageStart + n
      if (n < radial.catApps.length) { radial.setApp(gi); radial.launchApp(gi) }
    } else if (n < radial.groups.length) {
      radial.openCategory(n)
    }
  }

  // Keys for the outer rings. Returns true when the key was consumed.
  function handleKey(event) {
    if (!radial.appsOpen) return false
    if (radial.naming) return radial.nameKey(event)
    if (radial.actionTarget) return radial.actionKey(event)
    if (radial.carry) return radial.carryKey(event)
    var k = event.key
    var ctrl = event.modifiers & Qt.ControlModifier
    if (k === Qt.Key_Menu || (k === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) { radial.openActionsForFocus(); return true }
    if (ctrl && k === Qt.Key_Z) { radial.undo(); return true }
    if (ctrl && k === Qt.Key_X) { radial.startCarry(); return true }
    if (ctrl && k === Qt.Key_N && radial.ringId === "apps") { radial.naming = { mode: "new", groupId: "", text: "" }; return true }
    if (!radial.appFocus) {
      var fg = radial.groups[radial.catIndex]
      if (k === Qt.Key_F2 && fg && fg.custom) { radial.naming = { mode: "rename", groupId: fg.id, text: fg.label }; return true }
      // Delete on a user group removes it (Ctrl+Z brings it back); on any
      // other group it does nothing — it must never reach an app hidden
      // behind the rings.
      if (k === Qt.Key_Delete) {
        if (fg && fg.custom) radial.deleteGroup(fg.id)
        return true
      }
    }
    if (k === Qt.Key_Escape) { radial.back(); return true }
    if (k === Qt.Key_Backspace && !radial.query) { radial.back(); return true }
    if (ctrl && radial.appFocus && radial.catId === "fav" && !radial.searching) {
      if (k === Qt.Key_Right || k === Qt.Key_Down) { radial.moveFav(1); return true }
      if (k === Qt.Key_Left || k === Qt.Key_Up) { radial.moveFav(-1); return true }
    }
    if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_Tab) { radial.step(1); return true }
    if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_Backtab) { radial.step(-1); return true }
    if (k === Qt.Key_Home || k === Qt.Key_End) { radial.jump(k === Qt.Key_End); return true }
    if (k === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) { radial.togglePinHot(); return true }
    if (k === Qt.Key_PageDown) { radial.changePage(1); return true }
    if (k === Qt.Key_PageUp) { radial.changePage(-1); return true }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (radial.focusLevel === 2 && radial.catId !== "") radial.launchApp(radial.appIndex, !!(event.modifiers & Qt.ShiftModifier))
      else radial.openCategory(radial.catIndex)
      return true
    }
    var plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
    if (!radial.query && plain && k >= Qt.Key_1 && k <= Qt.Key_9) { radial.hintPick(k - Qt.Key_1); return true }
    if (!radial.query && plain && k === Qt.Key_0) { radial.hintPick(9); return true }
    if (Util.editsFilter(event, radial.query)) { radial.setQuery(Util.editedFilter(event, radial.query)); return true }
    if (radial.printable(event)) {
      radial.setQuery(radial.query + event.text)
      return true
    }
    return false
  }

  // 0 → 1 on open and on every submenu change: the ring blooms outward.
  property real reveal: 1
  NumberAnimation on reveal {
    id: revealAnim
    from: 0
    to: 1
    duration: 220
    easing.type: Easing.OutCubic
    running: false
  }

  // Opening fires several triggers, some of them late (guard checks and
  // providers rebuild the rows after the menu is already showing), so the
  // open bloom plays once per open. Only a real submenu change blooms again.
  property bool bloomedThisOpen: false

  function bloom(force) {
    if (!radial.visible || !radial.menu || !radial.menu.opened) return
    if (!force && radial.bloomedThisOpen) return
    radial.bloomedThisOpen = true
    revealAnim.restart()
  }

  onVisibleChanged: radial.bloom(false)
  Connections {
    target: radial.menu
    function onActiveMenuChanged() { radial.closeApps(); radial.bloom(true) }
    function onOpenedChanged() {
      if (!radial.menu.opened) { radial.bloomedThisOpen = false; radial.helpOpen = false; radial.closeApps() }
      else radial.bloom(false)
    }
  }

  // ------------------------------------------------------------ components

  // A circle filled with the theme's two-tone gradient, run diagonally.
  component GradientDisc: Rectangle {
    property color startColor: radial.menu ? radial.menu.ringStart : "white"
    property color endColor: radial.menu ? radial.menu.ringEnd : "white"
    radius: width / 2
    rotation: 45
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: startColor }
      GradientStop { position: 1; color: endColor }
    }
  }

  // A font glyph painted with the same gradient, via an alpha mask.
  component GradientGlyph: Item {
    id: glyphRoot
    property string glyph: ""
    property string family: ""
    property real pixelSize: Style.font.display
    property color startColor: radial.menu ? radial.menu.ringStart : "white"
    property color endColor: radial.menu ? radial.menu.ringEnd : "white"

    Text {
      id: glyphText
      anchors.fill: parent
      textFormat: Text.PlainText
      text: glyphRoot.glyph
      font.family: glyphRoot.family
      font.pixelSize: glyphRoot.pixelSize
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      color: "white"
      visible: false
      layer.enabled: true
    }

    GradientDisc {
      id: glyphFill
      startColor: glyphRoot.startColor
      endColor: glyphRoot.endColor
      anchors.centerIn: parent
      width: Math.max(parent.width, parent.height) * 1.42
      height: width
      radius: 0
      visible: false
      layer.enabled: true
    }

    ShaderEffectSource {
      id: fillSource
      anchors.fill: parent
      sourceItem: glyphFill
      sourceRect: Qt.rect((glyphFill.width - glyphRoot.width) / 2, (glyphFill.height - glyphRoot.height) / 2, glyphRoot.width, glyphRoot.height)
      visible: false
    }

    MultiEffect {
      anchors.fill: parent
      source: fillSource
      maskEnabled: true
      maskSource: glyphText
      // Cut at half coverage with a full-width soft edge, which keeps the
      // glyph's own antialiasing instead of filling its whole box.
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }
  }

  // A round button for the outer rings: either a font glyph or an app icon.
  component RingButton: Item {
    id: btn
    property bool hot: false
    property string glyph: ""
    property string family: ""
    property string iconSource: ""
    property string label: ""
    property bool showLabel: true
    property bool dim: false
    property string hint: ""
    property bool pinned: false
    property bool running: false
    property bool hasMenu: false
    property bool noLabel: false
    property color accentStart: radial.menu ? radial.menu.ringStart : "white"
    property color accentEnd: radial.menu ? radial.menu.ringEnd : "white"
    signal entered()
    signal clicked()
    signal rightClicked()

    width: radial.buttonSize
    height: radial.buttonSize
    z: btn.hot ? 2 : 1
    scale: btn.hot ? 1.1 : 1.0
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    GradientDisc {
      anchors.fill: parent
      startColor: btn.accentStart
      endColor: btn.accentEnd
      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: btn.accentStart
        shadowBlur: 1.0
        shadowOpacity: btn.hot ? 1.0 : 0.4
        shadowScale: btn.hot ? 1.12 : 1.0
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
        autoPaddingEnabled: true
      }
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: Math.max(2, Style.space(2))
      radius: width / 2
      color: radial.menu
        ? Qt.tint(radial.menu.background, Util.alpha(btn.accentStart, btn.hot ? 0.22 : 0.06))
        : "black"
      Behavior on color { ColorAnimation { duration: 140 } }
    }

    GradientGlyph {
      anchors.centerIn: parent
      width: parent.width * 0.6
      height: parent.height * 0.6
      visible: btn.iconSource.length === 0
      startColor: btn.accentStart
      endColor: btn.accentEnd
      glyph: btn.glyph
      family: btn.family.length > 0 ? btn.family : (radial.menu ? radial.menu.fontFamily : "")
      pixelSize: radial.buttonSize * 0.4
    }

    Image {
      anchors.centerIn: parent
      visible: btn.iconSource.length > 0
      width: radial.buttonSize * 0.5
      height: width
      fillMode: Image.PreserveAspectFit
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      source: btn.iconSource
      asynchronous: true
    }

    // Number badge: press 1–9 to pick this button.
    Rectangle {
      visible: btn.hint.length > 0 && !radial.searching
      anchors.horizontalCenter: parent.horizontalCenter
      y: -height * 0.7
      width: Style.space(20)
      height: width
      radius: width / 2
      color: radial.menu ? radial.menu.background : "black"
      border.width: 1
      border.color: btn.accentStart
      Text {
        anchors.centerIn: parent
        text: btn.hint
        color: radial.menu ? radial.menu.foreground : "white"
        font.family: radial.menu ? radial.menu.fontFamily : ""
        font.pixelSize: Style.font.bodySmall
      }
    }

    Text {
      visible: btn.pinned
      x: parent.width - width * 0.8
      y: -height * 0.2
      text: "\uf005"
      color: btn.accentStart
      font.family: radial.menu ? radial.menu.fontFamily : ""
      font.pixelSize: Style.font.bodySmall
    }

    // A dot under an app that already has a window open.
    Rectangle {
      visible: btn.running
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - height * 0.3
      width: Style.space(7)
      height: width
      radius: width / 2
      color: btn.accentStart
      border.width: 1
      border.color: radial.menu ? radial.menu.background : "black"
    }

    // The focused label may run past its neighbours: a backing keeps it legible.
    Rectangle {
      visible: btn.hot && btnLabel.visible
      anchors.centerIn: btnLabel
      width: btnLabel.contentWidth + Style.space(12)
      height: btnLabel.contentHeight + Style.space(4)
      radius: height / 2
      color: radial.menu ? radial.menu.background : "black"
      opacity: 0.85
      scale: btnLabel.scale
    }

    Text {
      id: btnLabel
      anchors.top: parent.bottom
      anchors.topMargin: Style.space(6)
      anchors.horizontalCenter: parent.horizontalCenter
      visible: !btn.noLabel && (btn.showLabel || btn.hot)
      // The focused label shows in full; the rest stay inside their slot.
      width: btn.hot ? Math.max(radial.buttonSize * 1.9, implicitWidth) : radial.buttonSize * 1.9
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: btn.label
      color: radial.menu ? (btn.hot ? radial.menu.selectedText : radial.menu.foreground) : "white"
      font.family: radial.menu ? radial.menu.fontFamily : ""
      font.pixelSize: Style.font.subtitle
      font.weight: btn.hot ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
      scale: 1 / btn.scale
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      // Only a moving pointer takes focus: a ring that opens or filters
      // under a resting pointer must not steal it from the keyboard.
      acceptedButtons: btn.hasMenu ? (Qt.LeftButton | Qt.RightButton) : Qt.LeftButton
      onPositionChanged: btn.entered()
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) btn.rightClicked()
        else btn.clicked()
      }
    }
  }

  // ---------------------------------------------------------------- scene

  Item {
    id: scene
    width: radial.discRadius * 2
    height: width
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -Style.space(10)
    scale: radial.fit * (0.94 + 0.06 * radial.reveal)
    opacity: radial.reveal

    // Soft accent bloom behind the disc.
    Rectangle {
      anchors.centerIn: parent
      width: radial.hubRadius * 5
      height: width
      radius: width / 2
      color: radial.menu ? radial.menu.glow : "transparent"
      opacity: 0.16
      layer.enabled: true
      layer.effect: MultiEffect {
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        autoPaddingEnabled: true
      }
    }

    // Outer glass disc.
    Rectangle {
      id: disc
      anchors.fill: parent
      radius: width / 2
      color: radial.menu ? Util.alpha(radial.menu.background, 0.62) : "transparent"
      border.width: 1
      border.color: radial.menu ? Util.alpha(radial.menu.foreground, 0.16) : "transparent"

      // Clicks on the disc stay in the menu; clicks in its square corners
      // (outside the circle) dismiss it like the rest of the scrim.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          var dx = mouse.x - width / 2
          var dy = mouse.y - height / 2
          if (Math.sqrt(dx * dx + dy * dy) > width / 2) {
            if (mouse.button === Qt.LeftButton) radial.menu.cancel()
          } else if (mouse.button === Qt.RightButton) {
            // Right-click steps back one ring, like Esc.
            if (radial.appsOpen) radial.back()
            else if (radial.atRoot) radial.menu.cancel()
            else radial.menu.goBack()
          }
        }
      }

      // Scroll over a crowded category to turn its pages.
      WheelHandler {
        property double last: 0
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
          var now = Date.now()
          if (now - last < 180 || event.angleDelta.y === 0) return
          last = now
          radial.changePage(event.angleDelta.y < 0 ? 1 : -1)
        }
      }
    }

    // Track the buttons ride on.
    Rectangle {
      anchors.centerIn: parent
      visible: !radial.appsOpen
      width: radial.ringRadius * 2
      height: width
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: radial.menu ? Util.alpha(radial.menu.foreground, 0.10) : "transparent"
    }

    Rectangle {
      anchors.centerIn: parent
      visible: radial.appsOpen
      width: radial.catRadius * 2
      height: width
      radius: width / 2
      color: "transparent"
      // While an app is being moved the track lights up: the groups are targets.
      border.width: radial.carry ? 2 : 1
      border.color: radial.menu ? (radial.carry ? radial.menu.ringStart : Util.alpha(radial.menu.foreground, 0.10)) : "transparent"
      opacity: radial.catReveal * (radial.carry ? carryPulse.value : 1)

      QtObject { id: carryPulse; property real value: 1 }
      SequentialAnimation {
        running: radial.carry !== null
        loops: Animation.Infinite
        onStopped: carryPulse.value = 1
        NumberAnimation { target: carryPulse; property: "value"; from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { target: carryPulse; property: "value"; from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
      }
    }

    Rectangle {
      anchors.centerIn: parent
      visible: radial.catId !== ""
      width: radial.appRadius * 2
      height: width
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: radial.menu ? Util.alpha(radial.menu.foreground, 0.10) : "transparent"
      opacity: radial.appReveal
    }

    // ------------------------------------------------------------- hub
    Item {
      id: hub
      anchors.centerIn: parent
      width: radial.hubRadius * 2
      height: width

      readonly property bool hovered: hubMouse.containsMouse

      GradientDisc {
        anchors.fill: parent
        opacity: hub.hovered ? 0.95 : 0.7
        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: radial.menu ? radial.menu.glow : "black"
          shadowBlur: 1.0
          shadowOpacity: hub.hovered ? 0.9 : 0.55
          shadowHorizontalOffset: 0
          shadowVerticalOffset: 0
          autoPaddingEnabled: true
        }
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: Math.max(2, Style.space(2))
        radius: width / 2
        color: radial.menu ? Qt.tint(radial.menu.background, Util.alpha(radial.menu.foreground, hub.hovered ? 0.08 : 0.04)) : "black"
      }

      Column {
        anchors.centerIn: parent
        spacing: Style.space(2)
        // Above the hub's click area so the page dots get their clicks.
        z: 1

        // The app being moved rides in the hub, as does the focused app.
        Image {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: radial.carry !== null || radial.hubImage !== ""
          width: radial.hubRadius * 0.8
          height: width
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          source: radial.carry && radial.menu && radial.menu.appLibrary ? radial.menu.appLibrary.iconSource(radial.carry.row.appIcon) : radial.hubImage
        }

        GradientGlyph {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: radial.carry === null && radial.hubImage === ""
          width: radial.hubRadius * 1.1
          height: radial.hubRoot ? radial.hubRadius * 1.1 : radial.hubRadius * 0.8
          // The Omarchy logo on the root ring; the focused button's or the
          // submenu's own icon inside it.
          glyph: radial.hubRoot ? "" : (radial.hubGlyph || (radial.hubEntry && radial.hubEntry.icon) || "")
          family: radial.hubRoot || !(radial.hubGlyph || (radial.hubEntry && radial.hubEntry.icon)) ? "omarchy"
            : ((radial.hubGlyph && radial.hubFocus.iconFont) || (radial.menu ? radial.menu.fontFamily : ""))
          pixelSize: radial.hubRoot ? Style.font.displayLarge * 1.9 : Style.font.displayLarge * 1.3
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: !radial.hubRoot
          width: radial.hubRadius * 1.6
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: radial.carry ? (hub.hovered ? "Cancel" : "Moving…")
            : radial.focusItem ? radial.focusItem.label : (radial.hubEntry ? (radial.hubEntry.title || radial.hubEntry.label || "") : "")
          color: radial.menu ? radial.menu.foreground : "white"
          font.family: radial.menu ? radial.menu.fontFamily : ""
          font.pixelSize: Style.font.subtitle
          font.weight: Font.Medium
          elide: Text.ElideRight
        }

        // One dot per page; click one to jump there.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: radial.catId !== "" && radial.pageCount > 1
          spacing: Style.space(6)
          topPadding: Style.space(4)
          Repeater {
            model: radial.pageCount
            delegate: Rectangle {
              required property int index
              width: Style.space(7)
              height: width
              radius: width / 2
              color: radial.menu ? radial.menu.foreground : "white"
              opacity: index === radial.appPage ? 0.9 : 0.3
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                cursorShape: Qt.PointingHandCursor
                onClicked: radial.changePage(index - radial.appPage)
              }
            }
          }
        }
      }

      // Hub click: back out of a submenu, or close from the root ring.
      MouseArea {
        id: hubMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (radial.modal || radial.carry) radial.back()
          else if (radial.appsOpen) radial.closeApps()
          else if (radial.atRoot) radial.menu.cancel()
          else radial.menu.goBack()
        }
      }
    }

    // --------------------------------------------------------- buttons
    Repeater {
      model: radial.model

      delegate: Item {
        id: slot
        required property int index
        required property string itemId
        required property string kind
        required property string icon
        required property string iconFont
        required property string appIcon
        required property string label
        required property string detail

        readonly property bool hot: radial.menu && radial.menu.cursorActive && slot.index === radial.menu.selectedIndex
        readonly property bool isApp: slot.kind === "app"
        // Start at twelve o'clock and go clockwise.
        readonly property real angle: -Math.PI / 2 + 2 * Math.PI * slot.index / Math.max(1, radial.count)
        readonly property real distance: radial.ringRadius * (0.72 + 0.28 * radial.reveal)

        width: radial.buttonSize
        height: radial.buttonSize
        x: scene.width / 2 + Math.cos(slot.angle) * slot.distance - width / 2
        y: scene.height / 2 + Math.sin(slot.angle) * slot.distance - height / 2
        z: slot.hot ? 2 : 1
        // The main items step aside while Apps' own rings are showing.
        visible: !radial.appsOpen

        scale: slot.hot ? 1.1 : 1.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        // Gradient ring with a theme-colored glow that brightens on focus.
        GradientDisc {
          anchors.fill: parent
          layer.enabled: true
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: radial.menu ? radial.menu.glow : "black"
            shadowBlur: 1.0
            shadowOpacity: slot.hot ? 1.0 : 0.4
            shadowScale: slot.hot ? 1.12 : 1.0
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            autoPaddingEnabled: true
          }
        }

        Rectangle {
          anchors.fill: parent
          anchors.margins: Math.max(2, Style.space(2))
          radius: width / 2
          color: radial.menu
            ? Qt.tint(radial.menu.background, Util.alpha(radial.menu.ringStart, slot.hot ? 0.22 : 0.06))
            : "black"
          Behavior on color { ColorAnimation { duration: 140 } }
        }

        GradientGlyph {
          anchors.centerIn: parent
          width: parent.width * 0.6
          height: parent.height * 0.6
          visible: !slot.isApp
          glyph: slot.icon || "•"
          family: slot.iconFont.length > 0 ? slot.iconFont : (radial.menu ? radial.menu.fontFamily : "")
          pixelSize: radial.buttonSize * 0.4
        }

        Image {
          anchors.centerIn: parent
          visible: slot.isApp
          width: radial.buttonSize * 0.5
          height: width
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          source: slot.isApp && radial.menu && radial.menu.appLibrary ? radial.menu.appLibrary.iconSource(slot.appIcon) : ""
          asynchronous: true
        }

        Text {
          anchors.top: parent.bottom
          anchors.topMargin: Style.space(6)
          anchors.horizontalCenter: parent.horizontalCenter
          width: radial.buttonSize * 1.9
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: slot.label
          color: radial.menu ? (slot.hot ? radial.menu.selectedText : radial.menu.foreground) : "white"
          font.family: radial.menu ? radial.menu.fontFamily : ""
          font.pixelSize: Style.font.subtitle
          font.weight: slot.hot ? Font.DemiBold : Font.Normal
          elide: Text.ElideRight
          // Counter the button's focus zoom so labels stay crisp and level.
          scale: 1 / slot.scale
        }

        MouseArea {
          id: slotMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: radial.menu.selectFromPointer(slot.index, slot, { x: slotMouse.mouseX, y: slotMouse.mouseY })
          onPositionChanged: function(mouse) { radial.menu.selectFromPointer(slot.index, slot, mouse) }
          onClicked: {
            radial.menu.cursorActive = true
            radial.menu.selectedIndex = slot.index
            radial.menu.activateIndex(slot.index, true)
          }
        }
      }
    }

    // ------------------------------------------------- category ring
    Repeater {
      model: radial.appsOpen ? radial.groups : []

      delegate: RingButton {
        id: cat
        required property int index
        required property var modelData
        readonly property real angle: -Math.PI / 2 + 2 * Math.PI * cat.index / Math.max(1, radial.groups.length)
        readonly property real distance: radial.catRadius * (0.72 + 0.28 * radial.catReveal)
        x: scene.width / 2 + Math.cos(cat.angle) * cat.distance - width / 2
        y: scene.height / 2 + Math.sin(cat.angle) * cat.distance - height / 2
        readonly property int matches: radial.searching ? radial.groupMatches(cat.modelData) : cat.modelData.apps.length
        opacity: radial.catReveal * (radial.searching && cat.matches === 0 ? 0.25 : 1)
          * (radial.appFocus && cat.modelData.id !== radial.catId ? 0.45 : 1)
          * (radial.actionTarget ? 0.3 : 1)
        Behavior on opacity { NumberAnimation { duration: 140 } }
        accentStart: radial.accentA(cat.index)
        accentEnd: radial.accentB(cat.index)
        hint: radial.actionTarget ? "" : radial.hintFor(cat.index)
        hot: radial.focusLevel === 1 ? cat.index === radial.catIndex : cat.modelData.id === radial.catId
        glyph: cat.modelData.icon
        family: cat.modelData.iconFont || ""
        // Counts crowd a full ring; the focused one and searches keep theirs.
        label: cat.modelData.newSlot
          ? (radial.naming ? "“" + radial.naming.text + "▌”" : cat.modelData.label)
          : cat.modelData.label + (cat.hot || radial.searching || !radial.crowded ? " · " + cat.matches : "")
        hasMenu: radial.ringId === "apps" && !cat.modelData.newSlot
        onEntered: { if (radial.modal) return; radial.focusLevel = 1; radial.catIndex = cat.index }
        onClicked: {
          if (radial.pointerBlocked()) return
          if (radial.carry) radial.dropOn(cat.index)
          else radial.openCategory(cat.index)
        }
        onRightClicked: {
          if (radial.pointerBlocked() || radial.carry || radial.ringId !== "apps") return
          radial.focusLevel = 1
          radial.catIndex = cat.index
          radial.openActions({ kind: "group", group: cat.modelData })
        }
      }
    }

    // ------------------------------------------------------- app ring
    Repeater {
      model: radial.appsOpen && radial.catId !== "" ? radial.catApps : []

      delegate: RingButton {
        id: app
        required property int index
        required property var modelData
        readonly property real angle: -Math.PI / 2 + 2 * Math.PI * app.index / Math.max(1, radial.catApps.length)
        readonly property real distance: radial.appRadius * (0.72 + 0.28 * radial.appReveal)
        x: scene.width / 2 + Math.cos(app.angle) * app.distance - width / 2
        y: scene.height / 2 + Math.sin(app.angle) * app.distance - height / 2
        opacity: radial.appReveal * (radial.searching && radial.matchScore(app.modelData) < 0 ? 0.25 : 1)
          * (radial.actionTarget ? 0.3 : 1)
        accentStart: radial.accentA(radial.catPos)
        accentEnd: radial.accentB(radial.catPos)
        hint: radial.actionTarget ? "" : radial.hintFor(app.index)
        hot: radial.focusLevel === 2 && radial.pageStart + app.index === radial.appIndex
        iconSource: app.modelData.kind === "app" && radial.menu && radial.menu.appLibrary ? radial.menu.appLibrary.iconSource(app.modelData.appIcon) : ""
        glyph: app.modelData.glyph
        family: app.modelData.iconFont
        label: app.modelData.label
        // A crowded ring can't fit every name; the focused one always shows.
        showLabel: radial.appLabels
        pinned: app.modelData.kind === "app" && radial.menu.isPinned(app.modelData.appId)
        running: app.modelData.kind === "app" && radial.windowFor(app.modelData) !== ""
        hasMenu: app.modelData.kind === "app" || app.modelData.kind === "command"
        onRightClicked: {
          if (radial.pointerBlocked()) return
          radial.focusLevel = 2
          radial.setApp(radial.pageStart + app.index)
          if (app.modelData.kind === "command") radial.openActions({ kind: "command", row: app.modelData })
          else if (radial.ringId === "apps") radial.openActions({ kind: "app", row: app.modelData })
          else radial.togglePinHot()
        }
        onEntered: { if (radial.modal) return; radial.focusLevel = 2; radial.appIndex = radial.pageStart + app.index }
        onClicked: { if (!radial.pointerBlocked()) radial.launchApp(radial.pageStart + app.index) }
      }
    }

    // ---------------------------------------------------- options ring
    // A small ring just around the hub; the hub names the focused option.
    Repeater {
      model: radial.actionTarget ? radial.actions : []

      delegate: RingButton {
        id: act
        required property int index
        required property var modelData
        readonly property real angle: -Math.PI / 2 + 2 * Math.PI * act.index / Math.max(1, radial.actions.length)
        readonly property real distance: radial.hubRadius + radial.buttonSize * 0.4 + Style.space(14)
        x: scene.width / 2 + Math.cos(act.angle) * act.distance - width / 2
        y: scene.height / 2 + Math.sin(act.angle) * act.distance - height / 2
        z: 3
        scale: act.hot ? 0.9 : 0.8
        accentStart: act.modelData.id === "uninstall" || act.modelData.id === "delete" || act.modelData.id === "cmdRemove" || act.modelData.id === "recentClear" ? "#e06c75" : (radial.menu ? radial.menu.ringStart : "white")
        accentEnd: act.modelData.id === "uninstall" || act.modelData.id === "delete" || act.modelData.id === "cmdRemove" || act.modelData.id === "recentClear" ? "#be5046" : (radial.menu ? radial.menu.ringEnd : "white")
        hint: radial.hintFor(act.index)
        hot: act.index === radial.actionIndex
        glyph: act.modelData.icon
        label: act.modelData.label
        noLabel: true
        onEntered: radial.actionIndex = act.index
        onClicked: radial.runAction(act.index)
      }
    }
  }

  // Above the disc while an app is being moved: what to do next.
  Rectangle {
    visible: radial.carry !== null
    anchors.bottom: scene.top
    anchors.bottomMargin: Style.space(10) - (1 - scene.scale) * scene.height / 2
    anchors.horizontalCenter: parent.horizontalCenter
    width: carryBanner.implicitWidth + Style.space(36)
    height: carryBanner.implicitHeight + Style.space(16)
    radius: height / 2
    color: radial.menu ? Qt.tint(radial.menu.background, Util.alpha(radial.menu.ringStart, 0.18)) : "black"
    border.width: 1
    border.color: radial.menu ? radial.menu.ringStart : "white"

    Text {
      id: carryBanner
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: radial.carry ? "Moving " + radial.carry.row.label + "  —  click a group to put it there" : ""
      color: radial.menu ? radial.menu.foreground : "white"
      font.family: radial.menu ? radial.menu.fontFamily : ""
      font.pixelSize: Style.font.subtitle
      font.weight: Font.DemiBold
    }
  }

  // Under the disc: the search being typed, what the focused item is, and
  // a quiet reminder of the keys.
  Column {
    anchors.top: scene.bottom
    anchors.topMargin: Style.space(14) - (1 - scene.scale) * scene.height / 2
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(4)
    opacity: radial.reveal

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: radial.appsOpen && radial.searching
      textFormat: Text.PlainText
      text: "“" + radial.query + "”  ·  " + (radial.totalMatches === 0 ? "no matches" : radial.totalMatches + (radial.totalMatches === 1 ? " match" : " matches"))
      color: radial.menu ? radial.menu.foreground : "white"
      font.family: radial.menu ? radial.menu.fontFamily : ""
      font.pixelSize: Style.font.subtitle
      font.weight: Font.DemiBold
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: radial.appsOpen && text.length > 0
      width: Math.min(implicitWidth, radial.width * 0.7)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: radial.statusText
      color: radial.menu ? radial.menu.foreground : "white"
      opacity: 0.8
      // Click the "… click to undo" line to undo.
      MouseArea {
        anchors.fill: parent
        enabled: radial.undoInfo !== null && !radial.naming && !radial.actionTarget && !radial.carry
        cursorShape: Qt.PointingHandCursor
        onClicked: radial.undo()
      }
      font.family: radial.menu ? radial.menu.fontFamily : ""
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: radial.naming ? (radial.naming.mode === "cmdLine" ? "Type or Ctrl+V a shell command  ·  Enter " + (radial.naming.cmdId ? "save" : "next") + "  ·  Esc cancel"
          : "Type a name  ·  Enter save  ·  Esc cancel")
        : radial.actionTarget ? "← → choose  ·  1–9 pick  ·  Enter do it  ·  Esc close"
        : radial.carry ? "← → choose a group  ·  1–9 drop there  ·  Enter / Ctrl+V drop  ·  Esc cancel"
        : radial.appsOpen
        ? "Type to search  ·  1–9 pick  ·  ← → move" + (radial.pageCount > 1 && radial.catId !== "" ? "  ·  PgUp/PgDn pages" : "") + "  ·  Enter open  ·  Esc back  ·  ? help"
        : (radial.atRoot ? "Type to search  ·  ← → to move  ·  Esc to close  ·  ? help" : "Type to search  ·  ← → to move  ·  Backspace to go back  ·  ? help")
      color: radial.menu ? radial.menu.foreground : "white"
      opacity: 0.45
      font.family: radial.menu ? radial.menu.fontFamily : ""
      font.pixelSize: Style.font.bodySmall
    }
  }
  // ------------------------------------------------------------ help
  // The cheat-sheet sits over the disc; any key or click puts it away.
  Item {
    anchors.fill: parent
    visible: radial.helpOpen
    z: 10

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: radial.helpOpen = false
    }

    Rectangle {
      id: helpCard
      anchors.centerIn: parent
      anchors.verticalCenterOffset: scene.anchors.verticalCenterOffset
      width: helpBody.implicitWidth + Style.space(56)
      height: helpBody.implicitHeight + Style.space(48)
      radius: Style.space(28)
      color: radial.menu ? Util.alpha(radial.menu.background, 0.95) : "black"
      border.width: 1
      border.color: radial.menu ? Util.alpha(radial.menu.ringStart, 0.5) : "white"
      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: radial.menu ? radial.menu.glow : "black"
        shadowBlur: 1.0
        shadowOpacity: 0.5
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
        autoPaddingEnabled: true
      }

      Column {
        id: helpBody
        anchors.centerIn: parent
        spacing: Style.space(18)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "Keys"
          color: radial.menu ? radial.menu.foreground : "white"
          font.family: radial.menu ? radial.menu.fontFamily : ""
          font.pixelSize: Style.font.heading
          font.weight: Font.DemiBold
        }

        Row {
          spacing: Style.space(44)

          Repeater {
            model: radial.helpSections

            delegate: Column {
              id: section
              required property var modelData
              required property int index
              spacing: Style.space(10)

              Text {
                textFormat: Text.PlainText
                text: section.modelData.title
                color: radial.accentA(section.index)
                font.family: radial.menu ? radial.menu.fontFamily : ""
                font.pixelSize: Style.font.subtitle
                font.weight: Font.DemiBold
              }

              Grid {
                columns: 2
                columnSpacing: Style.space(18)
                rowSpacing: Style.space(7)

                Repeater {
                  model: section.modelData.rows.length * 2

                  delegate: Text {
                    required property int index
                    readonly property bool isKey: index % 2 === 0
                    textFormat: Text.PlainText
                    text: section.modelData.rows[Math.floor(index / 2)][isKey ? 0 : 1]
                    color: radial.menu ? (isKey ? radial.menu.selectedText : radial.menu.foreground) : "white"
                    opacity: isKey ? 1 : 0.85
                    font.family: radial.menu ? radial.menu.fontFamily : ""
                    font.pixelSize: Style.font.subtitle
                    font.weight: isKey ? Font.DemiBold : Font.Normal
                  }
                }
              }
            }
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "Any key or click to close"
          color: radial.menu ? radial.menu.foreground : "white"
          opacity: 0.45
          font.family: radial.menu ? radial.menu.fontFamily : ""
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
