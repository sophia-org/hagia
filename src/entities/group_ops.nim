import std/[sequtils, tables]

import ../types/[core, model]
import ../policy/entity_store
import ../state/[id_gen, values]

## Group membership. A group is a set of windows one key steps through; it
## decides nothing about geometry. Membership lives in two places that must
## agree — the group's own list and the per-window index — so every change to
## either happens here.

proc forgetGroupMembership*(model: var PolicyModel, windowId: WindowId) =
  ## Remove a window from whatever group holds it. A group of one is not a
  ## group, so the last pairing dissolves rather than lingering.
  if windowId notin model.groupOfWindow:
    return
  let groupId = model.groupOfWindow[windowId]
  model.groupOfWindow.del(windowId)
  if groupId notin model.groups:
    return
  model.groups[groupId].windows.keepItIf(it != windowId)
  if model.groups[groupId].windows.len < 2:
    for member in model.groups[groupId].windows:
      model.groupOfWindow.del(member)
    model.groups.del(groupId)
    return
  if model.groups[groupId].activeWindow == windowId:
    model.groups[groupId].activeWindow = model.groups[groupId].windows[0]

proc addGroup*(model: var PolicyModel, windows: openArray[WindowId]): GroupId =
  ## Gather windows into one group, taking each out of any group it already
  ## belonged to. Fewer than two windows is not a group and allocates nothing.
  var members: seq[WindowId]
  for windowId in windows:
    if windowId != nullWindowId and windowId in model.windows and windowId notin members:
      members.add(windowId)
  if members.len < 2:
    return nullGroupId
  if members.len > maxGroupMembers:
    fail("group membership exceeds its bound")
  for windowId in members:
    model.forgetGroupMembership(windowId)
  result = model.allocateGroupId()
  model.groups[result] =
    GroupData(id: result, windows: members, activeWindow: members[0])
  for windowId in members:
    model.groupOfWindow[windowId] = result

proc setGroupActiveWindow*(model: var PolicyModel, windowId: WindowId) =
  if windowId notin model.groupOfWindow:
    return
  let groupId = model.groupOfWindow[windowId]
  if groupId in model.groups:
    model.groups[groupId].activeWindow = windowId
