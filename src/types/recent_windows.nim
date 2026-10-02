import ./core

## Recent-windows switcher geometry. The sizes follow niri's defaults, as
## Triad's port does; Sophia receives only generic instance and region records.
const
  ## How long the opening chord must be held before the switcher is drawn. A
  ## quicker tap switches to the previous window without drawing anything.
  recentWindowsOpenDelayMs* = 150'u32
  recentWindowsMaxHeight* = 480'i32
  ## A preview is at most half its window's size (niri `max-scale 0.5`).
  recentWindowsMaxScaleDivisor* = 2'i64
  recentWindowsPadding* = 30'i32
  ## The strip scrolls once it would come closer than this to an output edge.
  recentWindowsStrut* = 192'i32
  ## Windows with no usable size are drawn as if they had this one.
  recentWindowsFallbackWidth* = 800'i32
  recentWindowsFallbackHeight* = 600'i32
  recentWindowsTinySize* = 32'i32

type
  RecentWindowPreview* = object
    window*: WindowId
    geometry*: Rect

  RecentWindowStrip* = object
    output*: OutputId
    bounds*: Rect
    previews*: seq[RecentWindowPreview]
    highlight*: Rect
