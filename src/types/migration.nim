## Passive records describing a Triad-to-Hagia configuration migration. The
## translation itself lives in `src/config/migration*.nim`; a report is evidence
## only and carries no authority to rewrite a profile.

type
  MigrationDisposition* {.pure.} = enum
    retained
    transformed
    unsupported
    excluded

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
