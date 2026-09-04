## Passive records describing a Triad-to-Hagia configuration migration. The
## translation itself lives in `src/config/migration*.nim`; a report is evidence
## only and carries no authority to rewrite a profile.

type
  MigrationDisposition* {.pure.} = enum
    ## `excluded` means another authority owns the command or Hagia has queued
    ## it; `deferred` means Hagia has settled its design and is waiting on a
    ## named dependency. The distinction matters to a reader deciding whether
    ## a missing command is a decision or a schedule.
    retained
    transformed
    unsupported
    excluded
    deferred

  MigrationItemKind* {.pure.} = enum
    setting
    physicalBinding

  MigrationBindingKind* {.pure.} = enum
    none
    key
    pointer
    axis
    gesture
    switch

  MigrationItem* = object
    kind*: MigrationItemKind
    source*: string
    settingAuthority*: string
    authority*: string
    disposition*: MigrationDisposition
    result*: string
    bindingKind*: MigrationBindingKind
    context*: string
    trigger*: string
    command*: string

  MigrationReport* = object
    items*: seq[MigrationItem]
    outputProfile*: string

  CommandMigration* = object
    ## One classified Triad command: which authority claims it, whether it was
    ## retained, and what it became.
    authority*: string
    disposition*: MigrationDisposition
    result*: string
    outputCommand*: string
