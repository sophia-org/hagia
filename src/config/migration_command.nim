import std/strutils

import ../types/migration

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
    if name.startsWith("split-tree-") or name.startsWith("frame-"):
      return commandMigration(
        "policy", MigrationDisposition.excluded,
        "excluded from the WM freeze profile; structural layout command belongs to a later policy and shell tranche",
      )
    if name in [
      "adjust-gaps", "adjust-master-count", "adjust-master-ratio", "center-tile",
      "deck", "dwindle", "dwindle-split-down", "dwindle-split-left",
      "dwindle-split-right", "dwindle-split-up", "focus-column-first",
      "focus-column-last", "focus-down", "focus-last", "focus-left",
      "focus-next-in-group", "focus-right", "focus-up", "frame-split-horizontal",
      "frame-split-vertical", "frame-tab-next", "frame-tab-prev", "frame-unsplit",
      "grid", "group-windows", "i3", "monocle", "move-column-left", "move-column-right",
      "move-column-to-first", "move-column-to-last", "move-to-named-scratchpad",
      "move-to-tag-left", "move-to-tag-right", "move-window-down", "move-window-left",
      "move-window-right", "move-window-up", "move-workspace-to-output", "notion",
      "right-tile", "scroller", "spiral", "split-tree-layout-stacking",
      "split-tree-layout-tabbed", "split-tree-layout-toggle-split",
      "split-tree-split-horizontal", "split-tree-split-vertical", "swap-to-tag",
      "tgmix", "tile", "toggle-gaps", "toggle-named-scratchpad", "ungroup-window",
      "vertical-grid", "zoom",
    ]:
      return commandMigration(
        "policy", MigrationDisposition.excluded,
        "historical spatial command is not selected by the checked-in freeze profile",
      )
    commandMigration(
      "unowned", MigrationDisposition.unsupported,
      "command has no classified retained authority",
    )
