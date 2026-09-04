import std/strutils

import ../types/[migration, model]

## Triad command classification. Each retained command maps to one Hagia action
## or one recorded exclusion with a written reason; nothing is silently dropped.

proc commandMigration*(
    authority: string,
    disposition: MigrationDisposition,
    outcome: string,
    outputCommand = "",
): CommandMigration =
  CommandMigration(
    authority: authority,
    disposition: disposition,
    result: outcome,
    outputCommand: outputCommand,
  )

proc commandArgument*(command, prefix: string): string =
  if command.startsWith(prefix) and command.len > prefix.len:
    result = command[prefix.len .. ^1].strip()

proc boundedWorkspaceCommand*(command, prefix: string): bool =
  let argument = command.commandArgument(prefix)
  if argument.len == 0:
    return false
  try:
    result = parseInt(argument) in 1 .. 9
  except ValueError:
    result = false

proc classifyTriadCommand*(command: string): CommandMigration =
  ## The shortcut authority owns the physical match. This classification owns
  ## the distinct fact of which least-authority participant may execute the
  ## resulting semantic command.
  case command
  of "close-window":
    commandMigration(
      "session", MigrationDisposition.transformed, "opaque close-focused capability",
      "close-window",
    )
  of "exit-session":
    commandMigration(
      "session", MigrationDisposition.transformed, "opaque logout capability", "logout"
    )
  of "spawn-terminal":
    commandMigration(
      "session", MigrationDisposition.transformed, "opaque terminal capability",
      "spawn-terminal",
    )
  of "spawn kitty":
    commandMigration(
      "session", MigrationDisposition.transformed, "declared terminal capability",
      "spawn-terminal",
    )
  of "spawn helium":
    commandMigration(
      "session", MigrationDisposition.transformed, "declared browser capability",
      "spawn-browser",
    )
  of "lock-session", "toggle-keyboard-shortcuts-inhibit":
    commandMigration(
      "session", MigrationDisposition.excluded,
      "excluded from the WM freeze profile; requires a dedicated security transition capability",
    )
  of "triad-reload":
    commandMigration(
      "session", MigrationDisposition.excluded,
      "excluded from the WM freeze profile; watched reload requires a cross-authority recovery protocol",
    )
  of "select-window":
    commandMigration(
      "session", MigrationDisposition.transformed, "bounded generic window switcher",
      "window-switcher",
    )
  of "toggle-hotkey-overlay", "toggle-overview", "focus-shell-ui", "close-overview",
      "recent-window-next", "recent-window-prev", "recent-window-next --filter app-id",
      "recent-window-prev --filter app-id", "focus-window-or-workspace-down",
      "focus-window-or-workspace-up":
    commandMigration(
      "shell", MigrationDisposition.excluded,
      "excluded from the WM freeze profile; requires broader shell state or MRU semantics",
    )
  of "screenshot", "screenshot-screen", "screenshot-window",
      "screenshot --clipboard-only", "screenshot --show-pointer",
      "screenshot --no-clipboard --hide-pointer",
      "screenshot --clipboard-only --hide-pointer":
    commandMigration(
      "portal", MigrationDisposition.excluded,
      "excluded from the WM freeze profile; requires an explicit capture portal grant",
    )
  of "toggle-fullscreen", "fullscreen-window":
    commandMigration(
      "policy", MigrationDisposition.transformed, "toggleFullscreen policy action",
      "toggle-fullscreen",
    )
  of "toggle-maximized", "maximize-column", "maximize-window-to-edges":
    commandMigration(
      "policy", MigrationDisposition.transformed, "toggleMaximized policy action",
      "toggle-maximized",
    )
  of "minimize":
    commandMigration(
      "policy", MigrationDisposition.retained, "minimizeFocused policy action", command
    )
  of "restore-minimized":
    commandMigration(
      "policy", MigrationDisposition.retained, "restoreMinimized policy action", command
    )
  of "toggle-floating":
    commandMigration(
      "policy", MigrationDisposition.retained, "toggleFloating policy action", command
    )
  of "focus-next":
    commandMigration(
      "policy", MigrationDisposition.retained, "focusNext policy action", command
    )
  of "focus-prev":
    commandMigration(
      "policy", MigrationDisposition.retained, "focusPrevious policy action", command
    )
  of "focus-tag-right":
    commandMigration(
      "policy", MigrationDisposition.transformed, "viewNext policy action",
      "focus-view-next",
    )
  of "focus-occupied-tag-right":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "focusNextOccupiedWorkspace policy action", "focus-occupied-workspace-next",
    )
  of "move-to-scratchpad":
    commandMigration(
      "policy", MigrationDisposition.retained, "moveToScratchpad policy action", command
    )
  of "toggle-scratchpad":
    commandMigration(
      "policy", MigrationDisposition.retained, "toggleScratchpad policy action", command
    )
  of "restore-scratchpad":
    commandMigration(
      "policy", MigrationDisposition.retained, "restoreScratchpad policy action",
      command,
    )
  of "switch-layout":
    commandMigration(
      "policy", MigrationDisposition.retained, "switchLayout policy action", command
    )
  of "focus-last":
    commandMigration(
      "policy", MigrationDisposition.retained, "focusLast policy action", command
    )
  of "focus-left":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "focusColumnPrevious policy action; Hagia names the axis it moves along",
      "focus-column-prev",
    )
  of "focus-right":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "focusColumnNext policy action; Hagia names the axis it moves along",
      "focus-column-next",
    )
  of "focus-up":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "focusWindowAbove policy action; movement stays inside the focused column",
      "focus-window-above",
    )
  of "focus-down":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "focusWindowBelow policy action; movement stays inside the focused column",
      "focus-window-below",
    )
  of "scroller":
    commandMigration(
      "policy", MigrationDisposition.transformed, "selectScrollerLayout policy action",
      "layout-scroller",
    )
  of "tile":
    commandMigration(
      "policy", MigrationDisposition.transformed, "selectTileLayout policy action",
      "layout-tile",
    )
  of "grid":
    commandMigration(
      "policy", MigrationDisposition.transformed, "selectGridLayout policy action",
      "layout-grid",
    )
  of "monocle":
    commandMigration(
      "policy", MigrationDisposition.transformed, "selectMonocleLayout policy action",
      "layout-monocle",
    )
  of "new-workspace":
    commandMigration(
      "policy", MigrationDisposition.retained, "newWorkspace policy action", command
    )
  of "consume-window":
    commandMigration(
      "policy", MigrationDisposition.transformed, "consumeNextColumn policy action",
      command,
    )
  of "expel-window":
    commandMigration(
      "policy", MigrationDisposition.transformed, "expelFocusedWindow policy action",
      command,
    )
  of "resize-width -0.1":
    commandMigration(
      "policy", MigrationDisposition.transformed, "shrinkColumn policy action", command
    )
  of "resize-width 0.1":
    commandMigration(
      "policy", MigrationDisposition.transformed, "growColumn policy action", command
    )
  of "resize-height -0.1":
    commandMigration(
      "policy", MigrationDisposition.transformed, "shrinkWindow policy action", command
    )
  of "resize-height 0.1":
    commandMigration(
      "policy", MigrationDisposition.transformed, "growWindow policy action", command
    )
  of "move", "resize":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "Engine-owned completed pointer interaction", command,
    )
  else:
    if command.boundedWorkspaceCommand("focus-workspace "):
      return commandMigration(
        "policy", MigrationDisposition.transformed, "activateView policy action",
        command,
      )
    if command.boundedWorkspaceCommand("move-to-workspace "):
      return commandMigration(
        "policy", MigrationDisposition.transformed, "moveToView policy action", command
      )
    if command.startsWith("spawn "):
      return commandMigration(
        "session", MigrationDisposition.excluded,
        "excluded from the WM freeze profile; arbitrary launch requires a declared application capability",
      )
    if command.startsWith("switch-shell ") or command == "cycle-shell":
      return commandMigration(
        "shell", MigrationDisposition.excluded,
        "excluded from the WM freeze profile; requires a bounded shell selection capability",
      )
    let parts = command.splitWhitespace()
    if parts.len == 0:
      return commandMigration(
        "unowned", MigrationDisposition.unsupported, "command must not be empty"
      )
    let name = parts[0]
    if name.startsWith("split-tree-") or name.startsWith("frame-") or
        name in ["frame-tree", "bsp-tree", "i3", "notion"]:
      return commandMigration(
        "policy", MigrationDisposition.deferred,
        "tabbed substrate deferred until a shell surface can draw the tab bar; see docs/action-vocabulary.md",
      )
    if name in [
      "adjust-gaps", "adjust-master-count", "adjust-master-ratio", "center-tile",
      "deck", "dwindle", "dwindle-split-down", "dwindle-split-left",
      "dwindle-split-right", "dwindle-split-up", "focus-column-first",
      "focus-column-last", "focus-next-in-group", "group-windows", "move-column-left",
      "move-column-right", "move-column-to-first", "move-column-to-last",
      "move-to-tag-left", "move-to-tag-right", "move-window-down", "move-window-left",
      "move-window-right", "move-window-up", "move-workspace-to-output", "right-tile",
      "spiral", "swap-to-tag", "tgmix", "toggle-gaps", "ungroup-window",
      "vertical-grid", "zoom",
    ]:
      return commandMigration(
        "policy", MigrationDisposition.excluded,
        "spatial command is queued behind a later Hagia policy tranche; see docs/roadmap.md",
      )
    commandMigration(
      "unowned", MigrationDisposition.unsupported,
      "command has no classified retained authority",
    )

proc namedScratchpadSlot(names: var seq[string], name: string): int =
  ## Triad addresses a scratchpad by name; Hagia addresses one of four slots.
  ## Slots are handed out in the order the migration first meets each name, so
  ## the same input profile always produces the same output profile.
  result = names.find(name) + 1
  if result == 0 and names.len < maxNamedScratchpadSlots:
    names.add(name)
    result = names.len

proc classifyTriadCommand*(
    command: string, scratchpadNames: var seq[string]
): CommandMigration =
  ## Classification for the commands that carry a name Hagia must number.
  ## Everything else is stateless and answers from the command alone.
  for prefix in ["toggle-named-scratchpad", "move-to-named-scratchpad"]:
    let argument = command.commandArgument(prefix & " ")
    if argument.len == 0:
      continue
    let slot = scratchpadNames.namedScratchpadSlot(argument)
    if slot == 0:
      return commandMigration(
        "policy",
        MigrationDisposition.excluded,
        "Hagia bounds named scratchpads to " & $maxNamedScratchpadSlots &
          " slots and this profile names more",
      )
    let action =
      if prefix == "toggle-named-scratchpad":
        "toggleNamedScratchpad"
      else:
        "moveToNamedScratchpad"
    return commandMigration(
      "policy",
      MigrationDisposition.transformed,
      action & $slot & " policy action; slot " & $slot & " carries Triad's \"" & argument &
        "\"",
      prefix & " " & $slot,
    )
  command.classifyTriadCommand()
