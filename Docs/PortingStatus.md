IN PROGRESS

Phase: 1 to 3 (Topology) and 9 to 10 (Streets), running in parallel
Last green commit: 4ca5bed on main (port targets declared, licences in place)
Branches: port/topology in .worktrees/topology, port/streets in .worktrees/streets, merged into main by the main session when green
Next step: merge each branch when its phases pass, then phases 4 to 8 (Topology), 11 (Seed onto Streets), 12 (remove GEOS)
Decisions taken on the user's behalf:
- All port targets are declared once in Package.swift up front, so the parallel branches never edit it.
- The branches live in local git worktrees under .worktrees/ (ignored), never pushed.
- JTS 1.20.0 is cloned into .build/ports/jts (ignored).
