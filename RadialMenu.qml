import QtQuick
import QtQuick.Effects
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
  readonly property var activeEntry: radial.menu ? radial.menu.item(radial.menu.activeMenu) : null

  // Geometry. The ring grows with the number of items so labels never
  // collide, and the whole disc scales down if it would overflow the screen.
  readonly property real buttonSize: Style.space(60)
  readonly property real labelHeight: Style.font.subtitle + Style.space(10)
  readonly property real ringRadius: Math.max(Style.space(150), radial.count * (radial.buttonSize + Style.space(40)) / (2 * Math.PI))
  readonly property real discRadius: radial.animOuter + radial.buttonSize / 2 + radial.labelHeight + Style.space(20)
  readonly property real hubRadius: Style.space(64)
  readonly property real fit: Math.min(1, (radial.height - Style.space(80)) / (radial.discRadius * 2))

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

    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue

      var cats = []
      try { for (var c = 0; c < entry.categories.length; c++) cats.push(String(entry.categories[c])) } catch (e) { }

      var def = null
      for (var d = 0; d < defs.length && !def; d++)
        for (var k = 0; k < defs[d].keys.length; k++)
          if (cats.indexOf(defs[d].keys[k]) >= 0) { def = defs[d]; break }
      // Category-less launchers from Omarchy's web-app installer.
      if (!def && /webapp/.test(String(entry.execString || ""))) def = radial.webDef
      if (!def) def = { id: "other", label: "Other", icon: "󰇘" }

      if (!byId[def.id]) {
        byId[def.id] = { id: def.id, label: def.label, icon: def.icon, apps: [] }
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
        detail: String(radial.menu.appLibrary.entrySubtext(entry) || "")
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

    // Stable category order (the defs' order, "Other" last); apps alphabetical.
    var order = ["games", "dev", "graphics", "media", "internet", "web", "office", "system", "utility", "other"]
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
    var pins = radial.menu.menuState.pins.filter(function(id) { return byApp[id] }).map(function(id) { return byApp[id] })
    if (pins.length > 0) out.unshift({ id: "fav", label: "Favourites", icon: "\uf005", apps: pins })
    return out
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

  function openApps(id) {
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
    radial.appsOpen = false
    radial.catId = ""
    radial.query = ""
    radial.appPage = 0
    radial.catReveal = 0
    radial.appReveal = 0
  }

  // Step back one level: search → apps → categories → root.
  function back() {
    if (radial.searching) {
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

  // i indexes the whole category.
  function launchApp(i) {
    var apps = radial.allCatApps
    if (i < 0 || i >= apps.length) return
    var it = apps[i]
    radial.menu.remember("ring:" + radial.ringId, { cat: radial.catId, item: it.itemId })
    if (it.kind === "app") radial.menu.launchApp(it.appId, it.label)
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

  // -1 when the item doesn't fit the search; higher is a better match.
  function matchScore(it) {
    var q = radial.query.trim().toLowerCase()
    if (q === "") return 0
    var l = String(it.label || "").toLowerCase()
    if (l.indexOf(q) === 0) return 3
    if (l.indexOf(" " + q) >= 0) return 2
    if (l.indexOf(q) >= 0) return 1
    var id = String(it.appId || "").toLowerCase()
    return id !== "" && id.indexOf(q) >= 0 ? 1 : -1
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
    var k = event.key
    if (k === Qt.Key_Escape) { radial.back(); return true }
    if (k === Qt.Key_Backspace && !radial.query) { radial.back(); return true }
    if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_Tab) { radial.step(1); return true }
    if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_Backtab) { radial.step(-1); return true }
    if (k === Qt.Key_Home || k === Qt.Key_End) { radial.jump(k === Qt.Key_End); return true }
    if (k === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) { radial.togglePinHot(); return true }
    if (k === Qt.Key_PageDown) { radial.changePage(1); return true }
    if (k === Qt.Key_PageUp) { radial.changePage(-1); return true }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (radial.focusLevel === 2 && radial.catId !== "") radial.launchApp(radial.appIndex)
      else radial.openCategory(radial.catIndex)
      return true
    }
    var plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
    if (!radial.query && plain && k >= Qt.Key_1 && k <= Qt.Key_9) { radial.hintPick(k - Qt.Key_1); return true }
    if (!radial.query && plain && k === Qt.Key_0) { radial.hintPick(9); return true }
    if (Util.editsFilter(event, radial.query)) { radial.setQuery(Util.editedFilter(event, radial.query)); return true }
    if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
        && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
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
      if (!radial.menu.opened) { radial.bloomedThisOpen = false; radial.closeApps() }
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
    property bool pinnable: false
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
      visible: btn.showLabel || btn.hot
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
      acceptedButtons: btn.pinnable ? (Qt.LeftButton | Qt.RightButton) : Qt.LeftButton
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
      border.width: 1
      border.color: radial.menu ? Util.alpha(radial.menu.foreground, 0.10) : "transparent"
      opacity: radial.catReveal
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

        GradientGlyph {
          anchors.horizontalCenter: parent.horizontalCenter
          width: radial.hubRadius * 1.1
          height: radial.hubRoot ? radial.hubRadius * 1.1 : radial.hubRadius * 0.8
          // The Omarchy logo on the root ring; the submenu's own icon inside it.
          glyph: radial.hubRoot ? "" : ((radial.hubEntry && radial.hubEntry.icon) || "")
          family: radial.hubRoot || !(radial.hubEntry && radial.hubEntry.icon) ? "omarchy" : (radial.menu ? radial.menu.fontFamily : "")
          pixelSize: radial.hubRoot ? Style.font.displayLarge * 1.9 : Style.font.displayLarge * 1.3
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: !radial.hubRoot
          width: radial.hubRadius * 1.6
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: radial.focusItem ? radial.focusItem.label : (radial.hubEntry ? (radial.hubEntry.title || radial.hubEntry.label || "") : "")
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
          if (radial.appsOpen) radial.closeApps()
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
        Behavior on opacity { NumberAnimation { duration: 140 } }
        accentStart: radial.accentA(cat.index)
        accentEnd: radial.accentB(cat.index)
        hint: radial.hintFor(cat.index)
        hot: radial.focusLevel === 1 ? cat.index === radial.catIndex : cat.modelData.id === radial.catId
        glyph: cat.modelData.icon
        family: cat.modelData.iconFont || ""
        // Counts crowd a full ring; the focused one and searches keep theirs.
        label: cat.modelData.label + (cat.hot || radial.searching || !radial.crowded ? " · " + cat.matches : "")
        onEntered: { radial.focusLevel = 1; radial.catIndex = cat.index }
        onClicked: radial.openCategory(cat.index)
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
        accentStart: radial.accentA(radial.catPos)
        accentEnd: radial.accentB(radial.catPos)
        hint: radial.hintFor(app.index)
        hot: radial.focusLevel === 2 && radial.pageStart + app.index === radial.appIndex
        iconSource: app.modelData.kind === "app" && radial.menu && radial.menu.appLibrary ? radial.menu.appLibrary.iconSource(app.modelData.appIcon) : ""
        glyph: app.modelData.glyph
        family: app.modelData.iconFont
        label: app.modelData.label
        // A crowded ring can't fit every name; the focused one always shows.
        showLabel: radial.appLabels
        pinned: app.modelData.kind === "app" && radial.menu.isPinned(app.modelData.appId)
        pinnable: app.modelData.kind === "app"
        onRightClicked: { radial.focusLevel = 2; radial.setApp(radial.pageStart + app.index); radial.togglePinHot() }
        onEntered: { radial.focusLevel = 2; radial.appIndex = radial.pageStart + app.index }
        onClicked: radial.launchApp(radial.pageStart + app.index)
      }
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
      text: radial.focusItem ? String(radial.focusItem.detail || (radial.appFocus ? "" : radial.focusItem.apps.length + (radial.focusItem.apps.length === 1 ? " item" : " items"))) : ""
      color: radial.menu ? radial.menu.foreground : "white"
      opacity: 0.8
      font.family: radial.menu ? radial.menu.fontFamily : ""
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: radial.appsOpen
        ? "Type to search  ·  1–9 pick  ·  ← → move" + (radial.pageCount > 1 && radial.catId !== "" ? "  ·  PgUp/PgDn pages" : "") + "  ·  Enter open  ·  Esc back"
        : (radial.atRoot ? "Type to search  ·  ← → to move  ·  Esc to close" : "Type to search  ·  ← → to move  ·  Backspace to go back")
      color: radial.menu ? radial.menu.foreground : "white"
      opacity: 0.45
      font.family: radial.menu ? radial.menu.fontFamily : ""
      font.pixelSize: Style.font.bodySmall
    }
  }
}
