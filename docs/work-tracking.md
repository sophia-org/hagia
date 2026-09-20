# Work tracking

Hagia uses the same queue and notebook as `sophia-stack`, so one workflow
covers both repositories and a finding in either is recorded the same way.
The two notebooks stay separate: Hagia's tasks and notes live here, and
nothing in this repository depends on the other at build or run time.

## The queue

`todo.md` is a todo.txt file. Reach it through the CLI rather than editing it
by hand:

```sh
zk tasks ls                 # the queue, in reviewed order
zk queue                    # only the critical lane
zk tasks add "(A) ... +critical @development id:hNNN order:000.NNNN"
zk tasks do N               # complete the line the listing numbers N
```

Every line carries a stable `id:` and an `order:` key. IDs are `h` and a
number, unique for the life of the repository and never reused; Sophia's are
`t` and a number, so a relayed task is unambiguous about which queue it
belongs to. **Identities are never recycled.** A new task takes the next number above
every `id:` that has ever been used, in `todo.md` and in the `done-*.md`
files together -- not the lowest number that happens to be free. A completed
task keeps its identity for ever, and the evidence that closed it is reached
by that identity: notes, commit messages and gate reports all cite it. Giving
a new task an old number silently re-points every one of those citations at
work it never described. Two live rows sharing a number is the visible
failure; the quiet one is worse. The `order:` key sets the reviewed position, which the CLI
preserves rather than sorting by description. Completion moves the line to
`done-YYYY-MM.md` with its ID and links intact; see `done.md`.

The display number a listing shows is not an identifier. Find a task by ID,
read its current number, then act on that number, because another agent may
have moved the queue in between.

## The notebook

Notes live under `docs/notes/`, one directory per kind, each with a template:

```sh
zk investigate --title "..."    # docs/notes/investigations
zk concept --title "..."        # docs/notes/concepts
zk adr --title "..."            # docs/notes/decisions
zk plan --title "..."           # docs/notes/plans
```

An investigation records the question, the evidence with its exact candidate
and configuration, the finding and the boundary responsible, and what remains.
Distinguish an observation from a hypothesis, and say when a reading is from
source rather than from a reproduction. A task that has a note links to it;
the note links back by naming the task ID.

`zk index` after editing a note directly, since the CLI only reindexes after
its own commands. `docs/roadmap.md` stays the narrative record of what landed
and is not a queue.
