import ../types/session
import ./wm_v1

proc encodeTabGroup*(g: ProjectionTabGroup): seq[byte] =
  result.addU64(g.output)
  result.addU64(g.group)
  for value in [g.x, g.y, g.width, g.height]:
    result.addU32(cast[uint32](value))
  result.addU32(g.selectedIndex)
  result.addU32(g.selectedGeneration)
  result.addU32(uint32(g.members.len))
  result.addU32(uint32(g.focused))

proc encodeTabMember*(g: ProjectionTabGroup, member: ProjectionTabMember): seq[byte] =
  result.addU64(g.output)
  result.addU64(g.group)
  result.addU32(member.surfaceIndex)
  result.addU32(member.surfaceGeneration)
