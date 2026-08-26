pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// All Tableau state lives here.
//
// A bar widget is instantiated once per monitor, so a Process or a Timer
// declared in Panel.qml would exist twice on a two-screen desk and poll
// twice. This file is the model; Panel.qml is the view.
//
// Loading a setup is slow by nature -- it opens real windows and waits for
// each one to map -- so it is never run as a child of the shell. The CLI is
// launched detached and reports progress through its own state file, which
// this store polls. A shell restart mid-load therefore loses nothing.
Singleton {
  id: root

  readonly property string cli:
    Qt.resolvedUrl("bin/omarchy-tableau").toString().replace(/^file:\/\//, "")

  readonly property string iconSetups: "\uf009"  // four-pane grid

  property string fontFamily: ""

  property var setups: []
  property string current: "Empty"
  property string phase: "idle"
  property string step: ""
  property string error: ""
  property var blocked: []
  property string configError: ""
  property bool configExists: true
  property string screens: ""
  property bool known: false
  property int done: 0
  property int total: 0
  property bool loaded: false
  property bool actionBusy: false

  function cursorIndexForCurrent() {
    if (root.current === "Empty") return 0
    for (var i = 0; i < root.setups.length; i++) {
      if (root.setups[i].name === root.current) return i + 1
    }
    return 0
  }

  readonly property bool busy: phase === "loading" || phase === "unloading"
  readonly property bool isBlocked: phase === "blocked"
  readonly property bool hasProblem: isBlocked || error !== "" || configError !== ""

  // Fast while something is happening, lazy otherwise. Nothing here costs
  // more than reading two small files, but there is no reason to do it every
  // second when the desk is sitting still.
  readonly property int pollInterval: busy ? 700 : 5000

  function refresh() { statusProc.running = true }

  Process {
    id: statusProc
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.applyStatus(text)
    }
  }

  function applyStatus(text) {
    var payload
    try {
      payload = JSON.parse(text)
    } catch (e) {
      // A CLI that fails must not blank the menu: keep what is on screen and
      // let the next poll try again.
      root.loaded = true
      return
    }
    root.setups = payload.setups || []
    // A status poll can have started just before a save and finish after it.
    // Do not let that stale snapshot briefly move the selection back to Empty.
    var reportedCurrent = payload.current || "Empty"
    if (!(root.actionBusy && reportedCurrent === "Empty" && root.current !== "Empty"))
      root.current = reportedCurrent
    root.phase = payload.phase || "idle"
    root.step = payload.step || ""
    root.error = payload.error || ""
    root.blocked = payload.blocked || []
    root.configError = payload.configError || ""
    root.configExists = payload.configExists !== false
    root.screens = payload.screens || ""
    root.known = payload.known === true
    root.done = payload.progress ? (payload.progress.done || 0) : 0
    root.total = payload.progress ? (payload.progress.total || 0) : 0
    root.loaded = true
  }

  Timer {
    interval: root.pollInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // --- actions --------------------------------------------------------

  function load(name, force) {
    if (root.busy) return
    // Optimistic phase so the panel reacts on the click rather than on the
    // next poll; the CLI overwrites this within a few hundred milliseconds.
    root.phase = "unloading"
    root.step = "closing windows"
    root.error = ""
    root.blocked = []
    var args = [root.cli, "load", name]
    if (force) args.push("--force")
    Quickshell.execDetached(args)
    Qt.callLater(root.refresh)
  }

  function saveCurrent(name) {
    if (!name || name.trim() === "") return
    var savedName = name.trim()
    // Keep the card selected immediately. The CLI also persists this value;
    // this optimistic value prevents an older status poll from selecting
    // Empty while the save process is still finishing.
    root.current = savedName
    root.error = ""
    saveProc.command = [root.cli, "save", savedName]
    root.actionBusy = true
    saveProc.running = true
  }

  Process {
    id: saveProc
    stderr: StdioCollector { onStreamFinished: if (text !== "") root.error = String(text).trim() }
    stdout: StdioCollector { onStreamFinished: root.refresh() }
    onExited: function(code) {
      root.actionBusy = false
      if (code !== 0 && root.error === "") root.error = "Could not save the current desktop"
      root.refresh()
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector { onStreamFinished: if (text !== "") root.error = String(text).trim() }
    onExited: function(code) {
      root.actionBusy = false
      if (code !== 0 && root.error === "") root.error = "Tableau action failed"
      root.refresh()
    }
  }

  function deleteSetup(name) { actionProc.command = [root.cli, "delete", name]; root.actionBusy = true; actionProc.running = true }
  function renameSetup(oldName, newName) { actionProc.command = [root.cli, "rename", oldName, newName]; root.actionBusy = true; actionProc.running = true }
  function duplicateSetup(source, newName) { actionProc.command = [root.cli, "duplicate", source, newName]; root.actionBusy = true; actionProc.running = true }

  function edit() { Quickshell.execDetached([root.cli, "edit"]) }
  function createConfig() { Quickshell.execDetached([root.cli, "init"]) ; Qt.callLater(root.refresh) }
  function clearProblem() { clearProc.running = true }
  function retry(force) {
    if (root.actionBusy || root.busy) return
    actionProc.command = [root.cli, "retry"]
    if (force) actionProc.command.push("--force")
    root.actionBusy = true
    actionProc.running = true
  }

  Process {
    id: clearProc
    command: [root.cli, "clear"]
    onExited: root.refresh()
  }

  // --- derived text ---------------------------------------------------

  function plain(s) {
    return String(s === undefined || s === null ? "" : s).replace(/[<>&]/g, " ")
  }

  readonly property string headline: {
    if (configError !== "") return "There is a problem with tableau.toml"
    if (isBlocked) return "Some windows would not close"
    if (phase === "unloading") return "Closing everything…"
    if (phase === "loading") return total > 0 ? "Loading " + current + " — " + done + "/" + total
                                              : "Loading " + current + "…"
    if (phase === "error" && error !== "") return "Last load reported a problem"
    if (current === "Empty") return "Empty desktop"
    return current
  }

  readonly property string subline: {
    if (configError !== "") return configError
    if (isBlocked) return blocked.length + " window(s) are still asking about unsaved work"
    if (busy && step !== "") return step
    if (error !== "") return error
    return screens
  }

  // The one line under a setup's name in the menu: what it starts, in the
  // order it starts it. Labels beat counts here -- "codex · btop · shell"
  // says what a setup *is* in a way "5 windows" never does.
  function metaFor(setup) {
    if (!setup) return ""
    var parts = []
    if (setup.workspaces > 0) parts.push(setup.workspaces + (setup.workspaces === 1 ? " workspace" : " workspaces"))
    if (setup.windows > 0) parts.push(setup.windows + (setup.windows === 1 ? " window" : " windows"))
    var services = setup.services || 0
    if (services > 0) parts.push(services + (services === 1 ? " service" : " services"))
    var layout = setup.layout || []
    for (var w = 0; w < layout.length; w++) {
      var cols = layout[w].columns || []
      for (var c = 0; c < cols.length; c++) {
        var labels = cols[c].labels || []
        for (var i = 0; i < labels.length; i++) parts.push(labels[i])
      }
    }
    return parts.join(" · ")
  }

  readonly property string tooltip: {
    var s = current === "Empty" ? "Empty desktop" : current
    if (busy) s = headline
    return "Tableau — " + s
  }
}
