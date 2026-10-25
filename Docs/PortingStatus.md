IN PROGRESS

Phase: 4 to 5 (Topology: overlay, predicates, distance, buffer). Streets: phase 11 merged (Seed on Streets), one parity test flaky against the Rust's nondeterminism, being made deterministic
Last green commit: 41f5556 on main. dfd2889 (phase 11 merged) builds, 400 of 401 tests pass, the one failure is the flaky Rust comparison above. Seeding the 2x2 block checked by the main session: road document identical but the date, streets GeoJSON byte-identical, other JSON equal in content, 16.6 s against 15.0 s
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
- MuvLanes holds translations of rustc-hash, hashbrown and opening-hours-syntax (MIT or Apache) inside its MPL files, their notices in its LICENSE, to reproduce Muv's hash order.
- The editor's entry is synchronous (dispatchMain in the AppKit bridge), because an async @main broke optimised test builds.
- The Rust osm2streets is nondeterministic (hash-map order of crossings and signals). The port uses node-id order, and parity means equal to one of the Rust's runs.
