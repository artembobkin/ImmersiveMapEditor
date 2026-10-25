# Porting osm2streets: progress

Phases 9 to 11 of `Docs/PortingGoal.md`, on the branch `port/streets`. This file is updated at every step.

## State

- Phase 9 (foundations): done. `Earcut`, `GeoAlgorithms`, `StreetGeom`, `OSMReader`, `CountryBoundaries` with the driving side, each with its tests.
- Phase 10 (Streets): done. Muv's lane reading is ported as `MuvLanes` (MPL-2.0, decided 2026-10-25), and osm2lanes reads every lane through it. With no help from the Rust, the four outputs are byte-identical to the Rust on all 29 XML cases of osm2streets, on the Moscow region and on the five tiles (the parity table below), and `toGeoJSON` equals the committed `geometry.json` of all 29 cases.
- Phase 11 (`Seed` onto `Streets`): done, the road documents seeded identically (below).

## MuvLanes

`Sources/MuvLanes/`, the parts of muv-osm (rev `2404d40`) that `lanes()` reaches, every file under the MPL-2.0 with its notice:

- `Tags/`: `Tag` (the tag tree) and `DoubleTag`, `Parse` (the derived `FromOsmStr`: whole-string, ASCII-case-insensitive names, and serde's variant names).
- `Support/`: `RustStr` (Rust's `split`, `trim`, integer and `f32` parsing), `HashOrder` (see below).
- `Modes/`: `TMode` with its hierarchy and the reading of modes from subtags, `TModes`, `AccessLevel`, `Lifecycle`.
- `Units/`: `Number` (an `f32` with its significant figures, written as `Display` writes it), `Quantity`, the units the lanes use.
- `Conditional/`: `Conditional`, `Restriction`, `Condition`, `Compare`, `Operator`, `DateTimeRange`, and `OpeningHoursSyntax`, the recogniser of opening-hours-syntax 1.1.3's grammar and builder errors, which decides whether a condition is a date range.
- `Lanes/`: `Lanes`, `Lane`, travel lanes and `Turn`, the direction parsers (`AllParser`, `IndividualParser`), parking, railways, waterways, aeroways, `lanes()`.
- `Highway/`: `highway_lanes`, `BaseLanes`, side lanes, one-way, `parse_direction`, the classes and their access, the driving side, and the legal speeds (`SpeedDefault` over `SpeedDefaultTable.swift`, generated from `speed_default.rs`: 554 functions, 12 classes, decoded once).
- `Serde/MuvJSON`: what `serde_json::to_value` makes of a `Lane`, the `muv` property of the lane polygons.

Decisions:

- **The order of tag maps.** A `Tag`'s subtags are a Rust `HashMap` with rustc-hash's `FxBuildHasher`, and Muv iterates them where two keys mean the same thing (`Bus` and `bus`, `tricycle` and `auto_rickshaw`, a `bus:lanes` and an `hgv:lanes` of other lane counts: the first read splits the lanes and the other is ignored, two lifecycle prefixes). `HashOrder` reproduces it: rustc-hash 2.1's `FxHasher` over a `str` and hashbrown's bucket layout (8-byte control groups on aarch64, triangular probing, growth), iterated in bucket order. rustc-hash, hashbrown and opening-hours-syntax are MIT or Apache-2.0: their translations sit inside two MPL files, their MIT notices in the folder's `LICENSE` (no new target: `Package.swift` was not to change).
- **Release arithmetic.** The Rust oracle is a release build, where `u8` overflows wrap: the port wraps there too (`&+`, `&*`).
- **Conditions are not evaluated.** osm2lanes evaluates them only for a `date_time`, which the pipeline's configuration (and the Swift `MapConfig`) never has. `DateTimeRange` keeps the text and only checks that the opening-hours crate would parse it.
- **Equality.** `LaneSpec` now holds the Muv `Lane` itself, compared with Muv's `PartialEq` (`Number` by value and figures, `Quantity` through conversion), as the Rust compares lanes in `CollapseDegenerateIntersections`.
- **The seam stays** (`LaneSpecSource`, default `MuvLaneSpecs`): the transformation tests run on made-up lanes. `RecordedLaneSpecs` and the harvest of lanes from the Rust are gone.
- Muv's own bugs are kept: `SlightLeft`'s OSM name is `sharp_left`, the legacy parking condition reads its modes from the parking tags, `maxdraught` of a whole direction goes into `maxheight`, `carriageway_width` reads the root key `carriageway`, RGB colours are written without padding.

## Parity numbers

`swift test -c release -Xswiftc -enable-testing`, the Rust being `osm2streets-cli` of the pipeline (rev fc119c4, arm64), the pipeline's configuration (inferred sidewalks and kerbs). The port reads every lane itself. "Identical" means byte-identical GeoJSON text. 2026-10-25:

| Case | Roads | Intersections | Tag sets | plain | lanes | lane_markings | intersection_markings |
|---|---|---|---|---|---|---|---|
| osm2streets's 29 XML cases (all but the PBF `frederiksted`) | 4 to 515 | 4 to 409 | 2 to 180 | 29 identical | 29 identical | 29 identical | 29 identical |
| Moscow 2x2 region, with its clip | 4874 | 4642 | 943 | identical (9516 features) | identical (7557) | identical (58360) | identical (229) |
| Moscow tile 15/19808/10242, unclipped | 1563 | 1577 | 437 | identical (3140) | identical (2543) | identical (21213) | identical (65) |
| Moscow tile 15/19809/10242 | 1389 | 1377 | 284 | identical (2766) | identical (2479) | one of the Rust's 5 results in 16 runs (18026) | identical (59) |
| Moscow tile 15/19808/10243 | 2091 | 1846 | 383 | identical (3937) | identical (2699) | one of the Rust's 2 results in 16 runs (29442) | identical (59) |
| Moscow tile 15/19809/10243 | 1614 | 1529 | 370 | identical (3143) | identical (2746) | identical (22910) | identical (131) |
| Moscow tile 15/19810/10243 | 1394 | 1349 | 248 | identical (2743) | identical (2568) | identical (18110) | identical (71) |

The committed `geometry.json` of the 29 cases, made as osm2streets's tests make it (`MapConfig::default()`, invariants checked): 29 of 29 identical (8 to 1025 features).

MuvLanes against the Rust on synthetic ways (`Tests/StreetsTests/MuvLanes/`): one way per tag set across a box, in ten countries (RU, DE, GB, US, FR, NL, IE, AU, AT, BE), the four outputs compared:

- 280 tag sets written by hand (every class, lane counts and placements, per-lane keys, access with case and alias clashes, every kind of speed and condition, opening hours accepted and refused, sidewalks, cycleways, bus lanes and bays, shoulders, both parking schemes, widths and units, surfaces and colours, overtaking, railways, odd values): 10 of 10 boxes identical, 1537 to 1539 lanes each.
- 400 tag sets drawn at random per box (a highway class and 2 to 9 of 120 lane keys, SplitMix64 from the box's name): 10 of 10 identical, 1941 to 2189 lanes each. One random way in FR makes the Rust itself panic (geom's `dist_along` of a negative distance, `polyline.rs:392`): `highway=busway width:lanes=3|3|3 shoulder=right est_width=5 lanes:backward=2 parking:right:capacity=4 motorcar:lanes=yes|no|yes turn=left turn:lanes:backward=left|through`. It is found alone and left out, as there is no output to compare. The port stops on it with the same error (`dist_along -4m is negative`, checked once by hand).
- Muv's own unit tests of the parts it rests on, translated (`MuvUnitTests`, 10 tests): the subtag order (`iter_tags`), numbers, quantities, parentheses, conditionals, separated values, the hierarchy, opening hours.

The Rust is not deterministic where two crossings (or traffic signals) on one road both fall within 30% of the same end: streets_reader iterates them in `HashMap` order, random per process, and the last one sets the stop line. The parity test runs the Rust 16 times when the first run differs, and passes only when the port's four files equal one run's four files, byte for byte. Measured before: `roosevelt_cycletrack` 2 results in 12 runs, 15/19809/10242 5 in 16, 15/19808/10243 2 in 16.

## Phase 11

`Seed` (`Sources/TileKit/Pipeline/Seed.swift`) no longer runs the Rust binary: it calls `Streets` in process (`StreetNetwork.fromOSM` with inferred sidewalks and kerbs, the transformations for clipped areas) on the same merged OSM XML and the same clip, read back from `clip.geojson` as the Rust read it, and writes the four GeoJSON outputs into `streets/` as before. `TileKit` depends on `Streets` (the one `Package.swift` change). `WorkspacePaths.osm2streets` is gone. `tools/osm2streets_cli` stays in the workspace as the oracle of the parity tests only. Whether to delete it is the user's decision.

Seeding parity, `tilepipeline seed 15 19808 10242 19809 10243` into temporary roots (`data/` holding links to the four tile folders of the workspace, `roads/` empty), before (this branch at `a38bf4d`, the Rust binary) and after:

- the road document `roads/15_19808_10242_19809_10243.json`: identical but the `"seeded"` date line (42 areas, markings line 698, zebra 186, letter 111, zigzag 32, 29 shelters);
- `streets/plain.geojson`, `lanes.geojson`, `lane_markings.geojson`, `intersection_markings.geojson`: byte-identical;
- `osm.json` and `clip.geojson`: the same content in another key order, `context.json` the same size: these differ the same way between two runs of the old binary (`JSONSerialization` writes Swift dictionaries in their per-process order).

Time of the whole seed, release builds: before 14.36 and 14.50 s, after 15.80 and 15.88 s (1.10 times, the goal 1.5).

## Speed

Release builds, this machine (Apple silicon), see "Phase 11" for the seeding as a whole.

| Run | Rust | Port, release |
|---|---|---|
| Moscow region, the four outputs | 0.8 s | 2.17 s |
| One tile, unclipped | | 0.71 to 1.11 s |

The seeding of the 2x2 block stays within the goal (1.10 times), so nothing was optimised. The speed table is one text decoded at first use, not dictionary literals: those cost the optimised build of `MuvLanes` 40 s (65 s against 25 s).

The whole `swift test`: 401 tests in 55 suites pass, in 557 s in debug and 86 s optimised (`-c release -Xswiftc -enable-testing`).

## The release test hang

An earlier `swift test -c release` sat at 0% CPU for 40 minutes. Found: the test process ran the editor's SwiftUI app, not the tests (its sample: `App.main` in `NSApplicationMain`, waiting for events). The executable's async `@main` emits its entry thunk under the same name as the test runner's (`async_Main`, with a shared specialised reabstraction thunk), and in an optimised build the linker keeps the executable's copy, so the runner's `main` started the app. Fixed by a synchronous entry (`Platform.runMain`, commit `b9f82e2`). Release tests also need `-Xswiftc -enable-testing` (the test targets use `@testable import`).

## Commits

- `5935bdb` Earcut. `3130717` CountryBoundaries. `7ddc315`, `cc93bb6` OSMReader. `7217ddf` GeoAlgorithms. `1aec73d` StreetGeom. `1cf1ea7` Streets with the parity tests. `b48762f` the remaining transformations.
- `b9f82e2` the synchronous entry point (the release test hang). `45ffd45` MuvLanes and osm2lanes reading through it. Then phase 11, `Seed` onto `Streets`.

## Left

- A way to check `ZipSidepaths` and `RemoveDisconnectedRoads` against the Rust (the binary does not run them).
- PBF input (osm2streets's `frederiksted`) is not ported: the pipeline writes XML.
