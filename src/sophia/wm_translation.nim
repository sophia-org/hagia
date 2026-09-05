import ../types/session
import ./wm_v1

proc encodeTranslationGroup*(group: ProjectionTranslationGroup): seq[byte] =
  result.addU64(group.output)
  result.addU64(group.group)
  result.addU32(cast[uint32](group.x))
  result.addU32(cast[uint32](group.y))
  result.addU32(uint32(group.members.len))
  result.addU32(0)

proc encodeTranslationMember*(
    group: ProjectionTranslationGroup, member: ProjectionTabMember
): seq[byte] =
  result.addU64(group.output)
  result.addU64(group.group)
  result.addU32(member.surfaceIndex)
  result.addU32(member.surfaceGeneration)
