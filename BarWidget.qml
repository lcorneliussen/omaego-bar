import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The ego of the current workspace, and a panel to act on all of them.
//
// There is deliberately no "active ego": an ego is an identity that has windows
// on a workspace, not a mode the system is in. The label therefore reports the
// workspace, and turns urgent when a workspace holds more than one ego.
//
// Short text entry goes through walker (`omaego new`, `omaego rule new`): the
// picker already exists and is themed. Adding an app is the exception and lives
// in the panel, because it needs a list AND a text field at once - walker's
// dmenu filters its rows by what is typed and returns nothing for a miss.
// NOTE: this file must be called BarWidget.qml. A third-party bar widget loaded
// under any other name fails with Qt's "File name case mismatch", which points
// nowhere near the real cause. First-party widgets (dropbox, clock) use other
// names because they live inside the shell's own qs module tree.
Panel {
  id: root
  moduleName: "io.github.lcorneliussen.omaego"
  ipcTarget: "io.github.lcorneliussen.omaego"

  readonly property string omaego: setting("command", "omaego")
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", false) === true
  // Updates are event-driven; this is only a backstop for anything that changes
  // without an event (an ego directory added by hand, say).
  readonly property int pollSeconds: Math.max(1, setting("pollSeconds", 20))

  property var model: ({ egos: [], rules: [] })
  readonly property var egos: model.egos || []
  readonly property var rules: model.rules || []
  readonly property var hereEgos: egos.filter(function (e) { return e.here })
  readonly property bool mixed: hereEgos.length > 1
  readonly property string label: hereEgos.map(function (e) { return e.name }).join(" · ")
  readonly property real iconPx: Math.max(10, Math.round(barSize * 0.78))
  readonly property real ringPx: Math.max(1, Math.round(iconPx * 0.1))
  // nf-md-account (U+F0004), outside the BMP so it needs a surrogate pair
  readonly property string faceGlyph: "\udb80\udc04"
  readonly property string iconFont: setting("iconFont", "JetBrainsMono Nerd Font")

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Always visible by default: the widget is the only way into the panel, and
  // an empty workspace is exactly when you want it (to start an ego here).
  // Hiding it then made the widget look broken.
  visible: hereEgos.length > 0 || !hideWhenEmpty
  implicitWidth: vertical ? barSize : content.implicitWidth + Style.space(14)
  implicitHeight: vertical ? content.implicitHeight + Style.space(14) : barSize
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  function refresh() { if (!probe.running) probe.running = true }

  // Outline every ego's windows in its own colour for as long as the panel is
  // open. Doing it on hover meant chasing a small target while looking away at
  // the windows; this way the whole mapping is visible at once.
  onOpenedChanged: {
    root.run([root.omaego, "highlight", opened ? "all" : "off"])
    if (opened) refresh()     // an app added a moment ago must be on its card
    else addEgo = null
  }

  // A shell restart or a crash while the panel was open would otherwise leave
  // every window wearing an ego colour, with no panel left to close. Done after
  // the first probe returns rather than on Component.onCompleted: settings are
  // injected by the bar after construction, so the configured command path is
  // not known yet at that point.
  property bool clearedStaleHighlights: false

  // Focus comes from the Wayland toplevel, which updates the instant it changes.
  // The CLI's own `focused` still counts, because it resolves a window to its
  // ego by data dir and so catches web-app windows, whose appId is the app's
  // rather than the ego's.
  readonly property string focusedClass:
    ToplevelManager.activeToplevel ? (ToplevelManager.activeToplevel.appId || "") : ""
  // Fire-and-forget calls go out detached. One shared Process would drop a call
  // made while it is still busy - closing the panel during an `app add` used to
  // lose the `highlight off` and leave every window outlined.
  function run(args) { Quickshell.execDetached(args) }
  function later() { reloadTimer.restart() }

  Process {
    id: probe
    command: [root.omaego, "panel"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.model = JSON.parse(String(text || "{}")) } catch (e) {}
      }
    }
  }
  // What a click in the panel does. It refreshes when the command is done, not
  // on a timer: `app add` takes seconds, and the card must show the new app.
  Process {
    id: actor
    onExited: root.later()
  }
  Timer { id: reloadTimer; interval: 90; onTriggered: root.refresh() }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { root.refresh() }
    // Windows appearing, closing or moving change which egos are here. Coalesced
    // through reloadTimer so a burst of events costs one call, not twenty.
    function onRawEvent(event) {
      if (!event || !event.name) return
      switch (String(event.name)) {
      case "openwindow":
      case "closewindow":
      case "movewindow":
      case "movewindowv2":
      case "activewindow":
      case "activewindowv2":
      case "workspace":
        reloadTimer.restart()
      }
    }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { reloadTimer.restart() }
  }
  Timer {
    interval: root.pollSeconds * 1000
    running: true; repeat: true; triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.label === "" ? 0 : Style.space(5)

    // Two-faced mark: half light, half dark, drawn rather than taken from a
    // glyph because no Nerd Font carries one. The ring keeps the dark half
    // readable on a dark bar, where a literal black fill would disappear.
    // Jekyll and Hyde: one person, split straight down the middle. No circle.
    // The dark half is a dimmed foreground rather than literal black - black has
    // no edge against a dark bar and the half simply disappears.
    Item {
      id: mark
      width: root.iconPx
      height: root.iconPx
      anchors.verticalCenter: parent.verticalCenter
      opacity: root.hereEgos.length ? 1.0 : 0.55

      Item {
        width: parent.width / 2
        height: parent.height
        clip: true
        Text {
          width: mark.width
          height: mark.height
          text: root.faceGlyph
          color: root.fg
          font.family: root.iconFont
          font.pixelSize: root.iconPx
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
      Item {
        x: parent.width / 2
        width: parent.width / 2
        height: parent.height
        clip: true
        Text {
          x: -mark.width / 2
          width: mark.width
          height: mark.height
          text: root.faceGlyph
          color: Qt.darker(root.fg, 2.6)
          font.family: root.iconFont
          font.pixelSize: root.iconPx
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    // One item per ego so each name can be hovered on its own. Hovering
    // outlines that ego's windows - the quickest way to see which tiles on a
    // mixed workspace belong to whom.
    Row {
      id: labelRow
      visible: !root.vertical
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Repeater {
        model: root.hereEgos
        Row {
          spacing: 0
          Text {
            text: index === 0 ? "" : "·"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          // The ego owning the FOCUSED window gets a pill behind its name. It
          // sits inside the padding the name already has, so nothing moves as
          // focus changes between egos - the bar must not jitter.
          //
          // The hit area is the whole card: full bar height and padded either
          // side, since the glyph box alone is a few pixels tall.
          Item {
            width: egoLabel.implicitWidth
            height: root.barSize

            Rectangle {
              anchors.fill: parent
              anchors.topMargin: Style.space(3)
              anchors.bottomMargin: Style.space(3)
              radius: height / 2
              color: modelData.color || root.fg
              opacity: (modelData.focused
                        || modelData.class === root.focusedClass) ? 0.25 : 0
              Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            Text {
              id: egoLabel
              anchors.fill: parent
              text: modelData.name
              color: modelData.color || root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              leftPadding: Style.space(7)
              rightPadding: Style.space(7)
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.toggle()
            }
          }
        }
      }
    }
  }
  MouseArea {
    id: button
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.toggle()
  }

  // One column per ego, side by side: its browser, its web apps, the hosts
  // that always open in it. The last column makes a new ego. Rules that name
  // no ego (Zoom rewrites and the like) sit underneath, across the panel.
  //
  // Hover is one root property rather than per-row containsMouse, the same
  // contract the first-party panels keep: exactly one highlight on screen.
  property string hoverKey: ""
  readonly property real colWidth: Style.space(220)
  readonly property real colGap: Style.space(10)
  readonly property var looseRules: model.looseRules || []
  // Where ~/.config/omaego stands against its private repo; "norepo" hides it.
  readonly property var sync: model.sync || ({ state: "norepo" })
  readonly property var available: model.available || []
  readonly property string syncText: {
    var st = sync.state, n = sync.local || 0, b = sync.behind || 0, a = sync.ahead || 0
    return st === "clean" ? "In sync with your repo"
         : st === "local" ? (n ? n + (n === 1 ? " change" : " changes") + " here" : a + " not pushed")
         : st === "behind" ? b + (b === 1 ? " change" : " changes") + " to pull"
         : st === "diverged" ? "Changes here and " + b + " to pull"
         : st === "unpublished" ? "Not pushed yet"
         : "Keep your egos and rules in a private repo…"
  }

  function act(args) {
    if (actor.running) run(args)
    else { actor.command = args; actor.running = true }
    close(); later()
  }

  // --- drag to reorder -------------------------------------------------------
  // One drag at a time: an ego card along the row, or an app or remote row
  // within its card. dragTo is the slot it would land in (0..count), drawn as
  // a line; dropping writes the new order to egos.toml through the CLI, and
  // the panel stays open and re-reads it.
  property string dragKind: ""        // "ego" | "app" | "remote"
  property string dragEgo: ""
  property int dragFrom: -1
  property int dragTo: -1
  property var dragIds: []            // ids of the list being reordered, in order

  // Slot under `pos` along a Repeater's items, by their midpoints.
  function slotAt(rep, pos, horizontal) {
    for (let i = 0; i < rep.count; i++) {
      const it = rep.itemAt(i)
      if (!it) continue
      const mid = horizontal ? it.x + it.width / 2 : it.y + it.height / 2
      if (pos < mid) return i
    }
    return rep.count
  }
  function dragUpdate(kind, ego, from, to, ids) {
    dragKind = kind; dragEgo = ego; dragFrom = from; dragTo = to; dragIds = ids
  }
  function dragEnd(commit) {
    const kind = dragKind, ego = dragEgo, from = dragFrom, to = dragTo, ids = dragIds
    dragKind = ""; dragEgo = ""; dragFrom = -1; dragTo = -1; dragIds = []
    // Dropping onto its own slot, or the one right after it, changes nothing.
    if (!commit || from < 0 || to < 0 || to === from || to === from + 1) return
    const where = to >= ids.length ? ["--end"] : ["--before", ids[to]]
    const args = kind === "ego"
      ? [root.omaego, "move", "ego", ids[from], ...where]
      : [root.omaego, "move", kind, ego, ids[from], ...where]
    if (actor.running) run(args)
    else { actor.command = args; actor.running = true }   // refreshes on exit
  }
  function showsDrop(kind, ego, index) {
    return dragKind === kind && (kind === "ego" || dragEgo === ego) && dragTo === index
           && dragTo !== dragFrom && dragTo !== dragFrom + 1
  }

  // The line that marks where a dragged row or card would land.
  component DropLine: Rectangle {
    property bool vertical: false
    color: Color.accent
    radius: 1
    width: vertical ? 3 : (parent ? parent.width : 0)
    height: vertical ? (parent ? parent.height : 0) : 3
    z: 10
  }

  // --- adding an app ---------------------------------------------------------
  // The panel body swaps from the ego cards to a picker for one ego, and from
  // there to a create form. `addEgo` null means the cards are showing.
  property var addEgo: null
  property string addStage: "pick"          // "pick" | "create"
  // The create form doubles as the edit form for an installed app: then this
  // holds that app, the URL is fixed, and saving renames and re-icons it.
  property var editApp: null
  property bool confirmRemove: false
  property var catalog: []
  property bool catalogFetched: false
  property string query: ""
  property int sel: 0
  property var nameIdeas: []
  property string probedIcon: ""
  property bool wantAgent: false
  readonly property real addWidth: Style.space(440)
  readonly property real rowH: Style.space(32)
  readonly property bool probing: iconProc.running || iconProc.next !== null

  // Catalogue apps matching the query, then always one Custom row that takes
  // what was typed further - so a miss is never a dead end. A pasted URL
  // matches the catalogue app on that host. Apps this ego already has are
  // listed, dimmed, so a search for one does not end in a duplicate.
  readonly property var rows: {
    var q = query.trim().toLowerCase(), host = urlHost(q)
    var hits = [], rest = [], have = []
    for (var i = 0; i < catalog.length; i++) {
      var c = catalog[i], n = String(c.name).toLowerCase()
      var h = String(c.host || "").replace(/^www\./, "")
      var bucket = host !== "" ? (h === host ? hits : null)
                 : q === "" || n.indexOf(q) === 0 ? hits
                 : n.indexOf(q) > 0 || String(c.key).indexOf(q) >= 0
                   || h.indexOf(q) >= 0 ? rest : null
      if (!bucket) continue
      if (c.installed) { if (q !== "") have.push(c) } else bucket.push(c)
    }
    return hits.concat(rest, [{ create: true }], have)
  }
  onRowsChanged: sel = 0
  function urlHost(t) {
    if (!looksLikeUrl(t)) return ""
    var m = String(t).trim().toLowerCase().match(/^(?:[a-z][a-z0-9+.-]*:\/\/)?([^\/?#:]+)/)
    return m ? m[1].replace(/^www\./, "") : ""
  }
  readonly property string customLabel: {
    var q = query.trim()
    return q === "" ? "Custom app…"
         : looksLikeUrl(q) ? "Custom app from " + urlHost(q)
         : "Custom app “" + q + "”"
  }
  readonly property string customHint: {
    var q = query.trim()
    return q === "" ? "any site" : looksLikeUrl(q) ? "name it next" : "its URL next"
  }

  function looksLikeUrl(t) {
    t = String(t).trim()
    return t !== "" && !/\s/.test(t) && (t.indexOf("://") > 0 || /^[^.]+(\.[^.]+)+/.test(t))
  }
  function start(proc, args) {
    proc.next = args
    if (!proc.running) { proc.command = args; proc.next = null; proc.running = true }
  }
  function startAdd(ego) {
    editApp = null
    addEgo = ego; addStage = "pick"; query = ""; searchField.text = ""
    start(catalogProc, [omaego, "app", "catalog", ego.slug])
    Qt.callLater(function () { searchField.forceActiveFocus() })
  }
  function cancelAdd() {
    addEgo = null
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }
  function startEdit(ego, app) {
    addEgo = ego; editApp = app; confirmRemove = false
    nameIdeas = []; probedIcon = ""; wantAgent = false
    urlField.text = app.url
    nameField.text = app.short || app.name; nameField.touched = true
    iconField.text = ""
    addStage = "create"
    Qt.callLater(function () { nameField.forceActiveFocus() })
  }
  // Back from the form: to the search it came from, or to the cards for an edit.
  function formBack() { if (editApp) cancelAdd(); else backToPick() }
  function removeApp(ego, app) {
    act([omaego, "app", "remove", ego.slug, app.name])
  }
  function backToPick() {
    addStage = "pick"
    Qt.callLater(function () { searchField.forceActiveFocus() })
  }
  // Installed rows sit after Custom and cannot be chosen.
  function moveSel(d) {
    var last = rows.length - 1
    while (last > 0 && rows[last].installed) last--
    sel = Math.max(0, Math.min(last, sel + d))
  }
  function activateRow() {
    var r = rows[sel]
    if (!r || !addEgo || r.installed) return
    if (!r.create) { act([omaego, "app", "add", addEgo.slug, r.key]); return }
    var q = query.trim(), isUrl = looksLikeUrl(q)
    nameIdeas = []; probedIcon = ""; wantAgent = false; editApp = null
    nameField.touched = !isUrl && q !== ""
    nameField.text = isUrl ? "" : q
    iconField.text = ""
    urlField.text = isUrl ? q : ""
    addStage = "create"
    Qt.callLater(function () {
      (isUrl || q === "" ? nameField : urlField).forceActiveFocus()
    })
  }
  function runProbe() {
    var u = urlField.text.trim()
    if (!addEgo || !looksLikeUrl(u)) { nameIdeas = []; probedIcon = ""; return }
    // An installed app already has its icon: look only at one pasted for it.
    if (editApp && iconField.text.trim() === "") { probedIcon = ""; return }
    if (!editApp) start(namesProc, [omaego, "app", "probe", addEgo.slug, u, "--names"])
    var a = [omaego, "app", "probe", addEgo.slug, u]
    if (iconField.text.trim() !== "") a = a.concat(["--icon", iconField.text.trim()])
    start(iconProc, a)
  }
  function canCreate() {
    var n = nameField.text.trim()
    return addEgo !== null && n !== "" && n.indexOf("/") < 0 && looksLikeUrl(urlField.text)
  }
  function createApp() {
    if (nameField.text.trim() === "") { nameField.forceActiveFocus(); return }
    if (editApp) {
      var e = [omaego, "app", "edit", addEgo.slug, editApp.name,
               "--name", nameField.text.trim()]
      if (probedIcon !== "" && !probing) e = e.concat(["--icon", probedIcon])
      if (wantAgent) e.push("--agent-icon")
      act(e)
      return
    }
    if (!canCreate()) { urlField.forceActiveFocus(); return }
    var a = [omaego, "app", "add", addEgo.slug,
             "--url", urlField.text.trim(), "--name", nameField.text.trim()]
    // Pass the previewed file, so what was shown is what gets installed.
    if (probedIcon !== "" && !probing) a = a.concat(["--icon", probedIcon])
    if (wantAgent) a.push("--agent-icon")
    act(a)
  }

  Process {
    id: catalogProc
    property var next: null
    onExited: if (next) { command = next; next = null; running = true }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.catalog = JSON.parse(String(text || "[]")) } catch (e) { return }
        // Icons are cached by the CLI; fill the cache once, then list again.
        if (!root.catalogFetched && root.addEgo
            && root.catalog.some(function (c) { return !c.iconPath })) {
          root.catalogFetched = true
          fetchProc.running = true
        }
      }
    }
  }
  Process {
    id: fetchProc
    command: [root.omaego, "app", "catalog", "--fetch"]
    onExited: if (root.addEgo)
      root.start(catalogProc, [root.omaego, "app", "catalog", root.addEgo.slug])
  }
  Process {
    id: namesProc
    property var next: null
    onExited: if (next) { command = next; next = null; running = true }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.nameIdeas = JSON.parse(String(text || "{}")).names || [] } catch (e) { return }
        if (!nameField.touched && root.nameIdeas.length) nameField.text = root.nameIdeas[0]
      }
    }
  }
  Process {
    id: iconProc
    property var next: null
    onExited: if (next) { command = next; next = null; running = true }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.probedIcon = JSON.parse(String(text || "{}")).iconPath || "" } catch (e) {}
      }
    }
  }
  Timer { id: probeTimer; interval: 350; onTriggered: root.runProbe() }
  function bare(pattern) { return String(pattern).replace(/^https?:\/\//, "") }

  // A hoverable, clickable row. `key` must be unique across the panel.
  // With `draggable`, pressing and moving it emits dragMoved (in the Hit's
  // own coordinates) and, on release, dropped - and then no click.
  component Hit: CursorSurface {
    id: hit
    property string key: ""
    property bool draggable: false
    property bool dragging: false
    signal activated()
    signal entered()
    signal exited()
    signal dragMoved(real mx, real my)
    signal dropped()
    foreground: root.fg
    hasCursor: root.hoverKey === key
    opacity: dragging ? 0.35 : 1.0
    MouseArea {
      id: hitArea
      property point pressAt
      property bool moved: false
      anchors.fill: parent
      hoverEnabled: true
      preventStealing: hit.draggable
      cursorShape: hit.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      onEntered: { root.hoverKey = hit.key; hit.entered() }
      onExited: { if (root.hoverKey === hit.key) root.hoverKey = ""; hit.exited() }
      onPressed: (m) => { pressAt = Qt.point(m.x, m.y); moved = false }
      onPositionChanged: (m) => {
        if (!hit.draggable || !pressed) return
        if (!hit.dragging && Math.abs(m.x - pressAt.x) + Math.abs(m.y - pressAt.y) > 8) {
          hit.dragging = true; moved = true
        }
        if (hit.dragging) hit.dragMoved(m.x, m.y)
      }
      onReleased: { if (hit.dragging) { hit.dragging = false; hit.dropped() } }
      onCanceled: { if (hit.dragging) { hit.dragging = false; root.dragEnd(false) } }
      onClicked: { if (!moved) hit.activated() }
    }
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  // An app's icon, or its initial on a disc while there is none to show.
  component AppIcon: Item {
    id: ai
    property string src: ""
    property string letter: ""
    Rectangle {
      anchors.fill: parent
      visible: img.status !== Image.Ready
      radius: Style.cornerRadius
      color: "transparent"
      border.width: 1
      border.color: root.dim
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: ai.letter
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Math.round(ai.height * 0.5)
      }
    }
    Image {
      id: img
      anchors.fill: parent
      sourceSize.width: width * 2; sourceSize.height: height * 2
      source: ai.src ? "file://" + ai.src : ""
      fillMode: Image.PreserveAspectFit
      smooth: true
    }
  }

  component AddTitle: Item {
    property string text: ""
    signal back()
    width: parent ? parent.width : 0
    implicitHeight: backHit.implicitHeight
    Hit {
      id: backHit
      key: "addback"
      implicitWidth: backText.implicitWidth + Style.space(12)
      implicitHeight: backText.implicitHeight + Style.space(8)
      onActivated: parent.back()
      Caption {
        id: backText
        anchors.centerIn: parent
        text: "←  Esc"
        color: backHit.hasCursor ? root.fg : root.dim
      }
    }
    Text {
      anchors.left: backHit.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: parent.text
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      elide: Text.ElideRight
    }
  }

  // "+ Add app" and friends: quiet until hovered.
  component AddRow: Hit {
    id: add
    property string label: ""
    width: parent ? parent.width : 0
    implicitHeight: addText.implicitHeight + Style.space(8)
    Caption {
      id: addText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "+  " + add.label
      color: add.hasCursor ? root.fg : root.dim
    }
  }

  component RuleRow: Hit {
    id: rr
    property var rule
    width: parent ? parent.width : 0
    implicitHeight: Math.max(ruleText.implicitHeight, rmBtn.height) + Style.space(4)
    Caption {
      id: ruleText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.right: rmBtn.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      text: root.bare(rr.rule.pattern) + (rr.rule.app ? "  · app" : "")
      color: rr.hasCursor ? root.fg : root.dim
      elide: Text.ElideMiddle
    }
    // Shown on hover only, and only the button deletes: a stray click on the
    // row must not lose a rule.
    HoverHandler { id: ruleHover }
    PanelActionButton {
      id: rmBtn
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: ruleHover.hovered || rr.hasCursor
      iconText: "\udb80\udd59"                  // nf-md-close_circle
      tooltipText: "Remove rule"
      foreground: root.fg
      hoverColor: root.bar ? root.bar.urgent : root.fg
      fontFamily: root.fontFamily
      onClicked: root.act([root.omaego, "rule", "rm", rr.rule.pattern])
    }
  }

  KeyboardPanel {
    id: card
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: fittedContentWidth(body.implicitWidth + padding * 2)
    contentHeight: fittedContentHeight(body.implicitHeight)
    focusTarget: keyCatcher

    // Esc closes, like every other omarchy panel.
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
    }

    Column {
      id: body
      spacing: Style.space(10)

      // RowLayout so every column stretches to the tallest one.
      RowLayout {
        id: columns
        visible: root.addEgo === null
        spacing: root.colGap

        Repeater {
          id: egoRep
          model: root.egos

          BorderSurface {
            id: egoCard
            readonly property var ego: modelData
            readonly property int cardIndex: index
            Layout.preferredWidth: root.colWidth
            Layout.fillHeight: true
            implicitHeight: egoCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            // Presence is shown by fading the whole card, not by a fill behind
            // it: a background competes with the per-ego colours on the card.
            // A faded card comes forward on hover anywhere over it, so an ego
            // that is not on this desktop is still readable before you act on it.
            color: "transparent"
            opacity: ego.here || cardHover.hovered ? 1.0 : 0.45
            Behavior on opacity { NumberAnimation { duration: 110 } }

            HoverHandler { id: cardHover }
            borderSpec: Border.controlSpec("normal", root.fg, Color.accent)

            // Where a dragged card would land: before this one, or after the last.
            DropLine {
              vertical: true
              x: -root.colGap / 2 - 1
              visible: root.showsDrop("ego", "", egoCard.cardIndex)
            }
            DropLine {
              vertical: true
              x: parent.width + root.colGap / 2 - 1
              visible: egoCard.cardIndex === egoRep.count - 1
                       && root.showsDrop("ego", "", egoRep.count)
            }

            Column {
              id: egoCol
              x: Style.space(8); y: Style.space(8)
              width: parent.width - Style.space(16)
              spacing: Style.space(2)

              // The ego itself: click opens its browser on this desktop.
              // Drag the name sideways to move the card.
              Hit {
                key: "ego:" + egoCard.ego.slug
                width: parent.width
                implicitHeight: head.implicitHeight + Style.space(10)
                draggable: true
                onDragMoved: (mx, my) => {
                  const pt = mapToItem(columns, mx, my)
                  root.dragUpdate("ego", "", egoCard.cardIndex, root.slotAt(egoRep, pt.x, true),
                                  root.egos.map(e => e.slug))
                }
                onDropped: root.dragEnd(true)
                onActivated: root.act([root.omaego, "launch", egoCard.ego.slug])

                Column {
                  id: head
                  x: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(12)
                  spacing: Style.space(1)
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: egoCard.ego.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  // The accounts it signs in with, when it has any: optional,
                  // so an ego without them shows no empty line.
                  Caption {
                    visible: (egoCard.ego.accounts || []).length > 0
                    width: parent.width
                    text: (egoCard.ego.accounts || []).join(", ")
                    elide: Text.ElideRight
                  }
                  Row {
                    spacing: Style.space(5)
                    Rectangle {
                      width: Style.space(6); height: width; radius: width / 2
                      anchors.verticalCenter: parent.verticalCenter
                      color: egoCard.ego.here ? Color.accent : "transparent"
                      border.width: egoCard.ego.here ? 0 : 1
                      border.color: root.dim
                    }
                    Caption {
                      text: (egoCard.ego.here ? "on this desktop" : "open here")
                            + (egoCard.ego.default ? "  ·  fallback" : "")
                    }
                  }
                }
              }

              // The browser this ego runs in. Its own row rather than part of
              // the header: the header launches the ego, and choosing another
              // browser (and which profile it should hold) must not.
              Hit {
                id: engineRow
                key: "engine:" + egoCard.ego.slug
                visible: !!egoCard.ego.browser
                width: parent.width
                implicitHeight: engineText.implicitHeight + Style.space(8)
                onActivated: root.act([root.omaego, "engine", "pick", egoCard.ego.slug])
                Caption {
                  id: engineText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: (egoCard.ego.browser || "")
                        + (engineRow.hasCursor ? "  ·  change browser or profile" : "")
                  color: engineRow.hasCursor ? root.fg : root.dim
                }
              }

              Item { width: 1; height: Style.space(4) }
              PanelSectionHeader {
                x: Style.space(6)
                text: "APPS"; foreground: root.fg; fontFamily: root.fontFamily
              }

              Repeater {
                id: appRep
                model: egoCard.ego.apps
                Hit {
                  id: appRow
                  readonly property int rowIndex: index
                  draggable: true
                  onDragMoved: (mx, my) => {
                    const pt = mapToItem(egoCol, mx, my)
                    root.dragUpdate("app", egoCard.ego.slug, rowIndex, root.slotAt(appRep, pt.y, false),
                                    egoCard.ego.apps.map(a => a.url))
                  }
                  onDropped: root.dragEnd(true)
                  DropLine { y: -2; visible: root.showsDrop("app", egoCard.ego.slug, appRow.rowIndex) }
                  DropLine {
                    y: parent.height
                    visible: appRow.rowIndex === appRep.count - 1
                             && root.showsDrop("app", egoCard.ego.slug, appRep.count)
                  }
                  // Declared in your egos repo, not installed on this machine:
                  // shown blurred, and the first click installs it.
                  readonly property bool pending: modelData.pending === true
                  key: "app:" + egoCard.ego.slug + ":" + (modelData.desktop || modelData.url)
                  width: egoCol.width
                  implicitHeight: Math.max(appIcon.height, appName.implicitHeight) + Style.space(8)
                  // The stored Exec already names the ego, so launching it
                  // here cannot land the app in the wrong identity.
                  onActivated: pending
                    ? root.act([root.omaego, "app", "open", egoCard.ego.slug, modelData.name])
                    : root.act(["sh", "-c", modelData.exec])
                  Image {
                    id: appIcon
                    x: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.font.iconLarge; height: width
                    sourceSize.width: width * 2; sourceSize.height: height * 2
                    source: modelData.iconPath ? "file://" + modelData.iconPath : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    opacity: appRow.pending && !appRow.hasCursor ? 0.6 : 1.0
                    layer.enabled: appRow.pending
                    layer.effect: MultiEffect {
                      blurEnabled: true; blurMax: 12
                      blur: appRow.hasCursor ? 0.15 : 0.6
                      saturation: appRow.hasCursor ? 0 : -0.5
                    }
                  }
                  Text {
                    id: appName
                    anchors.left: appIcon.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: appTools.left
                    anchors.rightMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: modelData.short || modelData.name
                    color: appRow.pending && !appRow.hasCursor ? root.dim : root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  // On hover: edit (name, icon) and remove, as Omarchy's own
                  // panels show row actions. A click anywhere else on the row
                  // still launches the app. HoverHandler, not the row's own
                  // hover: that one ends as the pointer moves onto a button.
                  HoverHandler { id: appHover }
                  Row {
                    id: appTools
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)
                    visible: appHover.hovered || appRow.hasCursor
                    PanelActionButton {
                      visible: !appRow.pending
                      iconText: "\udb80\udfeb"          // nf-md-pencil
                      tooltipText: "Edit"
                      foreground: root.fg
                      hoverColor: root.fg
                      fontFamily: root.fontFamily
                      onClicked: root.startEdit(egoCard.ego, modelData)
                    }
                    PanelActionButton {
                      iconText: "\udb80\udd59"          // nf-md-close_circle
                      tooltipText: appRow.pending ? "Remove from your egos repo" : "Remove"
                      foreground: root.fg
                      hoverColor: root.bar ? root.bar.urgent : root.fg
                      fontFamily: root.fontFamily
                      onClicked: root.removeApp(egoCard.ego, modelData)
                    }
                  }
                }
              }
              AddRow {
                key: "addapp:" + egoCard.ego.slug
                label: "Add app"
                onActivated: root.startAdd(egoCard.ego)
              }

              // herdr sessions, TUIs and gateways on your machines, pinned to
              // this ego. Each opens where it runs directly, elsewhere over ssh
              // (or a serve URL / tunnel for a gateway), and reconnects.
              Item { width: 1; height: Style.space(4) }
              PanelSectionHeader {
                x: Style.space(6)
                text: "REMOTE"; foreground: root.fg; fontFamily: root.fontFamily
              }
              Repeater {
                id: remRep
                model: egoCard.ego.remotes || []
                Hit {
                  id: remRow
                  readonly property int rowIndex: index
                  draggable: true
                  onDragMoved: (mx, my) => {
                    const pt = mapToItem(egoCol, mx, my)
                    root.dragUpdate("remote", egoCard.ego.slug, rowIndex, root.slotAt(remRep, pt.y, false),
                                    (egoCard.ego.remotes || []).map(r => r.id))
                  }
                  onDropped: root.dragEnd(true)
                  DropLine { y: -2; visible: root.showsDrop("remote", egoCard.ego.slug, remRow.rowIndex) }
                  DropLine {
                    y: parent.height
                    visible: remRow.rowIndex === remRep.count - 1
                             && root.showsDrop("remote", egoCard.ego.slug, remRep.count)
                  }
                  key: "remote:" + egoCard.ego.slug + ":" + modelData.id
                  width: egoCol.width
                  implicitHeight: Math.max(remIcon.height, remName.implicitHeight) + Style.space(8)
                  onActivated: root.act([root.omaego, "remote", "open", egoCard.ego.slug, modelData.id])
                  // The same badged icon as its launcher entry; a glyph when
                  // there is none. Faded while its machine is offline.
                  Item {
                    id: remIcon
                    x: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.font.iconLarge; height: width
                    opacity: modelData.online || remRow.hasCursor ? 1.0 : 0.45
                    Image {
                      anchors.fill: parent
                      visible: !!modelData.iconPath
                      sourceSize.width: width * 2; sourceSize.height: height * 2
                      source: modelData.iconPath ? "file://" + modelData.iconPath : ""
                      fillMode: Image.PreserveAspectFit
                      smooth: true
                    }
                    Text {
                      anchors.centerIn: parent
                      visible: !modelData.iconPath
                      // nf-md-web / console; nf-md-lan_disconnect while offline
                      text: !modelData.online ? "\udb80\udf19"
                          : modelData.kind === "web" ? "\udb81\udd9f" : "\udb80\udd8d"
                      color: modelData.online ? root.fg : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.iconLarge * 0.8
                    }
                  }
                  Text {
                    id: remName
                    anchors.left: remIcon.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: remTag.left
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: modelData.online || remRow.hasCursor ? root.fg : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  // Where it runs: "here" or the machine. The name keeps the room.
                  Caption {
                    id: remTag
                    anchors.right: remTools.visible ? remTools.left : parent.right
                    anchors.rightMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, remRow.width * 0.38)
                    elide: Text.ElideMiddle
                    text: modelData.here ? "here" : modelData.machine
                  }
                  HoverHandler { id: remHover }
                  PanelActionButton {
                    id: remTools
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: remHover.hovered || remRow.hasCursor
                    iconText: "\udb80\udd59"          // nf-md-close_circle
                    tooltipText: "Unpin from " + egoCard.ego.name
                    foreground: root.fg
                    hoverColor: root.bar ? root.bar.urgent : root.fg
                    fontFamily: root.fontFamily
                    onClicked: root.act([root.omaego, "remote", "remove", egoCard.ego.slug, modelData.id])
                  }
                }
              }
              AddRow {
                key: "addremote:" + egoCard.ego.slug
                label: "Add session or gateway"
                onActivated: root.act([root.omaego, "remote", "pick", egoCard.ego.slug])
              }

              Item { width: 1; height: Style.space(4) }
              PanelSectionHeader {
                x: Style.space(6)
                text: "ALWAYS OPENS HERE"; foreground: root.fg; fontFamily: root.fontFamily
              }
              Repeater {
                model: egoCard.ego.rules
                RuleRow { key: "rule:" + modelData.pattern; rule: modelData }
              }
              AddRow {
                key: "addrule:" + egoCard.ego.slug
                label: "Add rule"
                onActivated: root.act([root.omaego, "rule", "new", egoCard.ego.slug])
              }
            }
          }
        }

        // Egos in your repo that this device has not set up: faded, listing
        // what comes with them, until "Set up here" creates one.
        Repeater {
          model: root.available
          Hit {
            id: availCard
            key: "avail:" + modelData.slug
            Layout.preferredWidth: root.colWidth
            Layout.fillHeight: true
            implicitHeight: availCol.implicitHeight + Style.space(16)
            bordered: true
            opacity: hasCursor ? 1.0 : 0.45
            onActivated: root.act([root.omaego, "add", modelData.slug, "--open"])
            Column {
              id: availCol
              x: Style.space(14); y: Style.space(14)
              width: parent.width - Style.space(28)
              spacing: Style.space(4)
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: modelData.name
                color: modelData.color
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }
              Caption { text: "in your repo, not on this device" }
              Caption {
                visible: (modelData.accounts || []).length > 0
                width: availCol.width
                text: "sign in as " + (modelData.accounts || []).join(", ")
                elide: Text.ElideRight
              }
              Item { width: 1; height: Style.space(6) }
              Repeater {
                model: modelData.apps
                Caption { text: modelData; width: availCol.width; elide: Text.ElideRight }
              }
              Repeater {
                model: modelData.rules
                Caption { text: root.bare(modelData.pattern); width: availCol.width; elide: Text.ElideMiddle }
              }
              Item { width: 1; height: Style.space(6) }
              Caption {
                text: "+  Set up here"
                color: availCard.hasCursor ? root.fg : root.dim
              }
            }
          }
        }

        // New ego: a hollow column, so it reads as a slot rather than an ego.
        Hit {
          id: newCard
          key: "newego"
          Layout.preferredWidth: root.colWidth * 0.6
          Layout.fillHeight: true
          implicitHeight: newCol.implicitHeight + Style.space(16)
          bordered: true
          onActivated: root.act([root.omaego, "new"])
          Column {
            id: newCol
            anchors.centerIn: parent
            spacing: Style.space(4)
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "+"
              color: newCard.hasCursor ? root.fg : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
            Caption {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "New ego"
              color: newCard.hasCursor ? root.fg : root.dim
            }
          }
        }
      }

      Column {
        visible: root.addEgo === null && root.looseRules.length > 0
        width: columns.width
        spacing: Style.space(2)
        PanelSeparator { width: parent.width }
        PanelSectionHeader {
          x: Style.space(6)
          text: "ANY EGO · REWRITES"; foreground: root.fg; fontFamily: root.fontFamily
        }
        Repeater {
          model: root.looseRules
          RuleRow { key: "rule:" + modelData.pattern; rule: modelData; width: Math.min(columns.width, Style.space(420)) }
        }
      }

      // The egos repo: what this machine has that the repo does not, and the
      // other way round. Sync pulls, and hands commits and merges to the agent.
      Column {
        visible: root.addEgo === null
        width: columns.width
        spacing: Style.space(2)
        PanelSeparator { width: parent.width }
        Hit {
          id: syncRow
          key: "sync"
          width: Math.min(columns.width, Style.space(420))
          implicitHeight: syncLabel.implicitHeight + Style.space(8)
          onActivated: root.act(root.sync.state === "norepo"
                                ? [root.omaego, "sync", "--setup"] : [root.omaego, "sync"])
          Row {
            x: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            Text {
              // nf-md-sync (U+F04E6), outside the BMP like the mark's glyph
              anchors.verticalCenter: parent.verticalCenter
              text: "\udb81\udce6"
              color: syncLabel.color
              font.family: root.iconFont
              font.pixelSize: Style.font.body
            }
            Text {
              id: syncLabel
              text: "Sync"
              color: (root.sync.state === "clean" || root.sync.state === "norepo")
                     && !syncRow.hasCursor ? root.dim : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Caption {
              anchors.verticalCenter: parent.verticalCenter
              text: root.syncText
              color: root.sync.state === "clean" || root.sync.state === "norepo"
                     ? root.dim : Color.accent
            }
          }
        }
      }

      // Add app, step one: the catalogue, filtered as you type.
      Column {
        id: pickView
        visible: root.addEgo !== null && root.addStage === "pick"
        width: root.addWidth
        spacing: Style.space(6)

        AddTitle {
          text: "Add app to " + (root.addEgo ? root.addEgo.name : "")
          onBack: root.cancelAdd()
        }
        TextField {
          id: searchField
          width: parent.width
          foreground: root.fg
          font.family: root.fontFamily
          placeholderText: "Search apps, or paste a URL / type a name for your own"
          onTextChanged: root.query = text
          onAccepted: root.activateRow()
          // Esc clears a search first, so a typo does not throw you out.
          Keys.onEscapePressed: text !== "" ? text = "" : root.cancelAdd()
          Keys.onDownPressed: root.moveSel(1)
          Keys.onUpPressed: root.moveSel(-1)
        }
        ListView {
          id: pickList
          width: parent.width
          height: Math.min(count, 9) * root.rowH
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.rows
          currentIndex: root.sel

          delegate: CursorSurface {
            id: pr
            required property var modelData
            required property int index
            readonly property bool create: modelData.create === true
            readonly property bool have: modelData.installed === true
            width: pickList.width
            height: root.rowH
            foreground: root.fg
            hasCursor: index === root.sel
            opacity: have ? 0.45 : 1.0

            AppIcon {
              id: prIcon
              x: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.font.iconLarge + Style.space(2); height: width
              src: pr.create ? "" : (pr.modelData.iconPath || "")
              letter: pr.create ? "+" : String(pr.modelData.name).charAt(0)
            }
            Text {
              id: prName
              anchors.left: prIcon.right
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width * 0.6)
              textFormat: Text.PlainText
              text: pr.create ? root.customLabel : pr.modelData.name
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            Caption {
              anchors.left: prName.right
              anchors.leftMargin: Style.space(8)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              text: pr.create ? root.customHint
                    : pr.have ? "already in " + (root.addEgo ? root.addEgo.name : "")
                    : (pr.modelData.host || "")
            }
            // Selection follows the pointer only when it actually moves, so a
            // resting pointer does not fight the arrow keys as the list scrolls.
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: pr.have ? Qt.ArrowCursor : Qt.PointingHandCursor
              onPositionChanged: if (!pr.have) root.sel = pr.index
              onClicked: if (!pr.have) { root.sel = pr.index; root.activateRow() }
            }
          }
        }
        Caption {
          x: Style.space(6)
          text: root.rows[root.sel] && root.rows[root.sel].create
                ? "↑ ↓ choose  ·  Enter continues  ·  Esc " + (root.query !== "" ? "clears" : "back")
                : "↑ ↓ choose  ·  Enter adds  ·  Esc " + (root.query !== "" ? "clears" : "back")
        }
      }

      // Add app, step two: everything about a custom app in one box.
      Column {
        id: createView
        visible: root.addEgo !== null && root.addStage === "create"
        width: root.addWidth
        spacing: Style.space(10)

        AddTitle {
          text: (root.editApp ? "Edit app in " : "Custom app in ")
                + (root.addEgo ? root.addEgo.name : "")
          onBack: root.formBack()
        }
        Row {
          width: parent.width
          spacing: Style.space(12)

          AppIcon {
            id: preview
            width: Style.space(64); height: width
            src: root.probedIcon !== "" ? root.probedIcon
                 : root.editApp ? (root.editApp.iconPath || "") : ""
            letter: nameField.text.trim().charAt(0).toUpperCase()
            opacity: root.probing ? 0.4 : 1.0
            Behavior on opacity { NumberAnimation { duration: 110 } }
          }
          Column {
            width: parent.width - preview.width - parent.spacing
            spacing: Style.space(4)

            Caption { text: "URL" }
            TextField {
              id: urlField
              width: parent.width
              foreground: root.fg
              font.family: root.fontFamily
              placeholderText: "https://…"
              // An app's URL is what it is; a different one is a new app.
              readOnly: root.editApp !== null
              opacity: readOnly ? 0.6 : 1.0
              onTextChanged: probeTimer.restart()
              onAccepted: root.createApp()
              Keys.onEscapePressed: root.formBack()
            }
            Item { width: 1; height: Style.space(2) }
            Caption { text: "NAME" }
            TextField {
              id: nameField
              // Typed by hand: suggestions stop replacing it.
              property bool touched: false
              width: parent.width
              foreground: root.fg
              font.family: root.fontFamily
              placeholderText: "Shown as “<name> " + (root.addEgo ? root.addEgo.name : "") + "”"
              onTextEdited: touched = text.trim() !== ""
              onAccepted: root.createApp()
              Keys.onEscapePressed: root.formBack()
            }
            Flow {
              width: parent.width
              spacing: Style.space(4)
              visible: root.nameIdeas.length > 1
              Repeater {
                model: root.nameIdeas
                Hit {
                  key: "idea:" + modelData
                  bordered: true
                  current: nameField.text === modelData
                  implicitWidth: ideaText.implicitWidth + Style.space(14)
                  implicitHeight: ideaText.implicitHeight + Style.space(6)
                  onActivated: { nameField.text = modelData; nameField.touched = true }
                  Caption {
                    id: ideaText
                    anchors.centerIn: parent
                    text: modelData
                    color: root.fg
                  }
                }
              }
            }
            Item { width: 1; height: Style.space(2) }
            Caption { text: "ICON" }
            TextField {
              id: iconField
              width: parent.width
              foreground: root.fg
              font.family: root.fontFamily
              placeholderText: root.editApp ? "Paste an image URL to replace it"
                               : "Taken from the site — or paste an image URL"
              onTextChanged: probeTimer.restart()
              onAccepted: root.createApp()
              Keys.onEscapePressed: root.formBack()
            }
            Caption {
              width: parent.width
              wrapMode: Text.WordWrap
              elide: Text.ElideNone
              text: root.wantAgent ? (root.editApp
                        ? "The agent will look for a better icon when you save."
                        : "The agent will look for a better icon after the app is added.")
                    : root.editApp ? (iconField.text.trim() === "" ? "The icon it has now."
                        : root.probing ? "Fetching that image…"
                        : root.probedIcon !== "" ? "This one replaces it."
                        : "Could not use that image.")
                    : !root.looksLikeUrl(urlField.text) ? "Enter a URL to look for its icon."
                    : root.probing ? "Looking for an icon…"
                    : root.probedIcon !== "" ? "Icon found."
                    : "No icon found — a generic one will be used."
            }
          }
        }
        Item {
          width: parent.width
          height: formButtons.height
          // Removing is one deliberate step away: the first click asks.
          Button {
            visible: root.editApp !== null
            anchors.left: parent.left
            text: root.confirmRemove ? "Really remove?" : "Remove"
            bordered: true
            foreground: root.bar ? root.bar.urgent : root.fg
            fontFamily: root.fontFamily
            onClicked: root.confirmRemove ? root.removeApp(root.addEgo, root.editApp)
                                          : root.confirmRemove = true
          }
          Row {
            id: formButtons
            anchors.right: parent.right
            spacing: Style.space(8)
            Button {
              text: "Let the agent find an icon"
              bordered: true
              selected: root.wantAgent
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.wantAgent = !root.wantAgent
            }
            Button {
              text: root.editApp ? "Save  ⏎" : "Create  ⏎"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              opacity: (urlField.text, nameField.text, root.canCreate()) ? 1.0 : 0.5
              onClicked: root.createApp()
            }
          }
        }
      }
    }
  }
}
