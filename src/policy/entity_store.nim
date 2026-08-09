import std/[options, tables]

## Adapted from Triad's dense EntityManager at baseline
## fb8fb27ec294e0fe2361375de0b2fa8c08be0ca9. See THIRD_PARTY_NOTICES.md and
## docs/provenance.md. Hagia stores IDs beside payloads so T need not embed id.

type EntityStore*[Id, T] = object
  ## Dense entity storage. Logical identity and semantic order live outside the
  ## dense slot so swap-and-pop removal cannot change policy behavior.
  entities*: seq[T]
  ids*: seq[Id]
  index*: Table[Id, int]

proc len*[Id, T](store: EntityStore[Id, T]): int =
  store.entities.len

proc contains*[Id, T](store: EntityStore[Id, T], id: Id): bool =
  id in store.index

proc `[]`*[Id, T](store: EntityStore[Id, T], id: Id): T =
  store.entities[store.index[id]]

proc `[]`*[Id, T](store: var EntityStore[Id, T], id: Id): var T =
  store.entities[store.index[id]]

proc `[]=`*[Id, T](store: var EntityStore[Id, T], id: Id, value: T) =
  if id in store.index:
    store.entities[store.index[id]] = value
  else:
    store.index[id] = store.entities.len
    store.ids.add(id)
    store.entities.add(value)

proc get*[Id, T](store: EntityStore[Id, T], id: Id): Option[T] =
  if id in store.index:
    some(store[id])
  else:
    none(T)

proc del*[Id, T](store: var EntityStore[Id, T], id: Id) =
  if id notin store.index:
    return
  let removed = store.index[id]
  let last = store.entities.high
  if removed != last:
    store.entities[removed] = store.entities[last]
    store.ids[removed] = store.ids[last]
    store.index[store.ids[removed]] = removed
  store.entities.setLen(last)
  store.ids.setLen(last)
  store.index.del(id)

iterator pairs*[Id, T](store: EntityStore[Id, T]): (Id, T) =
  for index, id in store.ids:
    yield (id, store.entities[index])

iterator keys*[Id, T](store: EntityStore[Id, T]): Id =
  for id in store.ids:
    yield id

proc validateDense*[Id, T](store: EntityStore[Id, T]): bool =
  if store.entities.len != store.ids.len or store.ids.len != store.index.len:
    return false
  for slot, id in store.ids:
    if id notin store.index or store.index[id] != slot:
      return false
  true
