IN PROGRESS

Phase: 4 to 5 (Topology: overlay, predicates, distance, buffer) and 9 to 10 (Streets), running in parallel
Last green commit: 1942934 on main (phases 1 to 3 merged, 57 tests passing)
Branches: port/topology in .worktrees/topology, port/streets in .worktrees/streets, merged into main by the main session when green
Next step: merge each branch when its phases pass, then phases 6 to 8 (Topology), 11 (Seed onto Streets), 12 (remove GEOS)
Decisions taken on the user's behalf:
- All port targets are declared once in Package.swift up front, so the parallel branches never edit it.
- The branches live in local git worktrees under .worktrees/ (ignored), never pushed.
- JTS 1.20.0 is cloned into .build/ports/jts (ignored).
- The port matches GEOS 3.13 as this package builds it, including clang's fused multiply-add, and follows GEOS where it differs from JTS (each place in PortingParity.md).
- The STR tree follows libc++'s std::sort and heap, translated to Swift: Apache-2.0 with LLVM exceptions, its full text in Sources/Topology/LICENSE-LLVM (fetched from llvm-project, llvmorg-19.1.7).
- Phase 3's signed zero at a node: GEOS's sources may be read (not copied) to find its noding order. If only -0.0 against 0.0 is left, it is accepted as equal and counted in PortingParity.md.
- Streets: osm2lanes reads lanes through Muv (MPL-2.0, not ported). To be resolved before phase 11: Seed cannot depend on the Rust oracle.
