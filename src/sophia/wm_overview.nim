import ../types/[session, wm_v1]
import ./[policy_transport, wm_v1]

proc encodeOverview*(
    workspaces: openArray[ProjectionOverviewWorkspace]
): (seq[byte], seq[byte]) =
  if workspaces.len > maxOverviewWorkspaces:
    fail("workspace preview count exceeds the bound")
  var count = 0
  for workspace in workspaces:
    count += workspace.placements.len
    if count > maxOverviewPlacements:
      fail("workspace preview placements exceed the bound")
    result[0].addU64(workspace.output)
    result[0].addU64(workspace.workspace)
    for value in [
      workspace.bounds.x, workspace.bounds.y, workspace.bounds.width,
      workspace.bounds.height,
    ]:
      result[0].addU32(cast[uint32](value))
    result[0].addU32(workspace.focusIndex)
    result[0].addU32(workspace.focusGeneration)
    result[0].addU32(uint32(workspace.placements.len))
    result[0].addU32(uint32(workspace.active))
    for placement in workspace.placements:
      result[1].addU64(workspace.output)
      result[1].addU64(workspace.workspace)
      result[1].addU32(placement.surfaceIndex)
      result[1].addU32(placement.surfaceGeneration)
      for value in [
        placement.geometry.x, placement.geometry.y, placement.geometry.width,
        placement.geometry.height,
      ]:
        result[1].addU32(cast[uint32](value))
