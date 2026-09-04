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
  of "toggle-maximized", "maximize-window-to-edges":
    commandMigration(
      "policy", MigrationDisposition.transformed, "toggleMaximized policy action",
      "toggle-maximized",
    )
  of "maximize-column":
    commandMigration(
      "policy", MigrationDisposition.retained,
      "maximizeColumn policy action; a column decision, distinct from maximizing one window",
      command,
    )
  of "group-windows", "ungroup-window", "focus-next-in-group":
    commandMigration(
      "policy", MigrationDisposition.retained,
      "window group policy action; grouping decides what one key steps through, not where a layout puts a window",
      command,
    )
  of "toggle-gaps":
    commandMigration(
      "policy", MigrationDisposition.retained, "toggleGaps policy action", command
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
  of "center-tile":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "selectCenterTileLayout policy action", "layout-center-tile",
    )
  of "right-tile":
    commandMigration(
      "policy", MigrationDisposition.transformed, "selectRightTileLayout policy action",
      "layout-right-tile",
    )
  of "vertical-grid":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "selectVerticalGridLayout policy action", "layout-vertical-grid",
    )
  of "deck":
    commandMigration(
      "policy", MigrationDisposition.transformed, "selectDeckLayout policy action",
      "layout-deck",
    )
  of "move-window-up":
    commandMigration(
      "policy", MigrationDisposition.transformed, "moveWindowAbove policy action",
      "move-window-above",
    )
  of "move-window-down":
    commandMigration(
      "policy", MigrationDisposition.transformed, "moveWindowBelow policy action",
      "move-window-below",
    )
  of "move-window-left":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "moveWindowToColumnPrevious policy action; at the edge the window opens a column there",
      "move-window-column-prev",
    )
  of "move-window-right":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "moveWindowToColumnNext policy action; at the edge the window opens a column there",
      "move-window-column-next",
    )
  of "move-column-left":
    commandMigration(
      "policy", MigrationDisposition.transformed, "moveColumnPrevious policy action",
      "move-column-prev",
    )
  of "move-column-right":
    commandMigration(
      "policy", MigrationDisposition.transformed, "moveColumnNext policy action",
      "move-column-next",
    )
  of "move-column-to-first":
    commandMigration(
      "policy", MigrationDisposition.transformed, "moveColumnFirst policy action",
      "move-column-first",
    )
  of "move-column-to-last":
    commandMigration(
      "policy", MigrationDisposition.transformed, "moveColumnLast policy action",
      "move-column-last",
    )
  of "focus-column-first":
    commandMigration(
      "policy", MigrationDisposition.retained, "focusColumnFirst policy action", command
    )
  of "focus-column-last":
    commandMigration(
      "policy", MigrationDisposition.retained, "focusColumnLast policy action", command
    )
  of "zoom":
    commandMigration(
      "policy", MigrationDisposition.transformed,
      "promoteColumn policy action; Hagia's master is whichever column sits first",
      "promote-column",
    )
  of "move-to-tag-right":
    commandMigration(
      "policy", MigrationDisposition.transformed, "moveToViewNext policy action",
      "move-to-view-next",
    )
  of "move-to-tag-left":
    commandMigration(
      "policy", MigrationDisposition.transformed, "moveToViewPrevious policy action",
      "move-to-view-prev",
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
    for stepped in [
      ("adjust-gaps ", "gaps", "increase-gaps", "decrease-gaps"),
      (
        "adjust-master-count ", "master count", "increase-master-count",
        "decrease-master-count",
      ),
      (
        "adjust-master-ratio ", "master ratio", "increase-master-ratio",
        "decrease-master-ratio",
      ),
    ]:
      let argument = command.commandArgument(stepped[0])
      if argument.len == 0:
        continue
      # Hagia's actions carry no argument: the step size is a profile setting,
      # so a binding says which way to go and the profile says how far.
      return commandMigration(
        "policy",
        MigrationDisposition.transformed,
        "stepped " & stepped[1] & " policy action; Hagia reads the step from the profile",
        if argument.startsWith('-'):
          stepped[3]
        else:
          stepped[2],
      )
    if command.boundedWorkspaceCommand("swap-to-tag "):
      return commandMigration(
        "policy",
        MigrationDisposition.transformed,
        "swapWithView policy action",
        "swap-with-view " & command.commandArgument("swap-to-tag "),
      )
    let outputDirection = command.commandArgument("move-workspace-to-output ")
    if outputDirection.len > 0:
      if outputDirection notin ["left", "right", "up", "down"]:
        return commandMigration(
          "policy", MigrationDisposition.excluded,
          "move-workspace-to-output names a direction Hagia does not recognise",
        )
      # Hagia orders outputs rather than placing them on a compass, so the two
      # senses collapse onto the neighbour actions the output keys already use.
      return commandMigration(
        "policy",
        MigrationDisposition.transformed,
        "moveViewToOutput policy action; Hagia steps through output order rather than screen geometry",
        if outputDirection in ["left", "up"]:
          "move-view-to-output-prev"
        else:
          "move-view-to-output-next",
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
      "dwindle", "dwindle-split-down", "dwindle-split-left", "dwindle-split-right",
      "dwindle-split-up", "spiral", "tgmix",
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
