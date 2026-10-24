IN PROGRESS

Phase: 4 to 5 (Topology: overlay, predicates, distance, buffer) and Streets: MuvLanes, release speed, then 11 (Seed onto Streets), running in parallel
Last green commit: a38bf4d on main (phases 1 to 3 and 9 to 10 merged, 388 tests passing)
Branches: port/topology in .worktrees/topology, port/streets in .worktrees/streets, merged into main by the main session when green
Next step: merge each branch when its phases pass, then phases 6 to 8 (Topology), 11 (Seed onto Streets), 12 (remove GEOS)
Decisions taken on the user's behalf:
- All port targets are declared once in Package.swift up front, so the parallel branches never edit it.
- The branches live in local git worktrees under .worktrees/ (ignored), never pushed.
- JTS 1.20.0 is cloned into .build/ports/jts (ignored).
- The port matches GEOS 3.13 as this package builds it, including clang's fused multiply-add, and follows GEOS where it differs from JTS (each place in PortingParity.md).
- The STR tree follows libc++'s std::sort and heap, translated to Swift: Apache-2.0 with LLVM exceptions, its full text in Sources/Topology/LICENSE-LLVM (fetched from llvm-project, llvmorg-19.1.7).
- Phase 3's signed zero at a node: GEOS's sources may be read (not copied) to find its noding order. If only -0.0 against 0.0 is left, it is accepted as equal and counted in PortingParity.md.
- Streets: osm2lanes reads every lane's tags through Muv's lanes(), not only the driving side. Muv's lane reading is ported as its own target, MuvLanes, under MPL-2.0 (a file-level licence, usable in an MIT package and an app). The user may reverse this: the alternative is a clean-room reader with no exact parity.
- The Rust osm2streets is nondeterministic (hash-map order of crossings and signals). The port uses node-id order, and parity means equal to one of the Rust's runs.
