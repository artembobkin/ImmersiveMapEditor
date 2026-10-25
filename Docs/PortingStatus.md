IN PROGRESS

Phase: 12 (GEOS frozen into stored expectations, then removed). Phases 1 to 11 done.
Last green commit: cfd9d74 on main (phases 1 to 11 merged, 453 tests passing). Geometry runs on Topology: the five tiles' GLB geometry, stats and palettes byte-identical to the GEOS build, builds 1.06 to 1.29 times as long, seeding 1.17 times.
Branches: port/topology in .worktrees/topology, port/streets in .worktrees/streets, merged into main by the main session when green
Next step: merge phase 12, remove the GEOSwift/geos dependency from Package.swift (main session), run everything, write DONE
Decisions taken on the user's behalf:
- All port targets are declared once in Package.swift up front, so the parallel branches never edit it.
- The branches live in local git worktrees under .worktrees/ (ignored), never pushed.
- JTS 1.20.0 is cloned into .build/ports/jts (ignored).
- The port matches GEOS 3.13 as this package builds it, including clang's fused multiply-add, and follows GEOS where it differs from JTS (each place in PortingParity.md).
- The STR tree follows libc++'s std::sort and heap, translated to Swift: Apache-2.0 with LLVM exceptions, its full text in Sources/Topology/LICENSE-LLVM (fetched from llvm-project, llvmorg-19.1.7).
- Phase 3's signed zero at a node: GEOS's sources may be read (not copied) to find its noding order. If only -0.0 against 0.0 is left, it is accepted as equal and counted in PortingParity.md.
- Streets: osm2lanes reads every lane's tags through Muv's lanes(), not only the driving side. Muv's lane reading is ported as its own target, MuvLanes, under MPL-2.0 (a file-level licence, usable in an MIT package and an app). The user may reverse this: the alternative is a clean-room reader with no exact parity.
- MuvLanes holds translations of rustc-hash, hashbrown and opening-hours-syntax (MIT or Apache) inside its MPL files, their notices in its LICENSE, to reproduce Muv's hash order.
- The editor's entry is synchronous (dispatchMain in the AppKit bridge), because an async @main broke optimised test builds.
- The Rust osm2streets is nondeterministic (hash-map order of crossings at a shared road end). The tests enumerate every order the port can take there and require each Rust run to equal one of them (6 results on 15/19809/10242, the same 6 as 200 Rust runs).
- Speed: after two passes the geometry calls of a whole tile take 1.48 times GEOS's time (12.4 s against 8.4 s), the goal's bar being 1.5 times the whole tile build.
- makeValid (GEOS's linework method) has no JTS original: GEOS's comes from LGPL code. It is written anew from the algorithm, on the port's own operations, not translated from GEOS, and equals GEOS on 32,248 recorded and 12,000 random calls. To review by the user.
