# Porting osm2streets: progress

Phases 9 and 10 of `Docs/PortingGoal.md`, on the branch `port/streets`. This file is updated at every step.

## State

- Phase 9 (foundations): done. `Earcut`, `GeoAlgorithms`, `StreetGeom`, `OSMReader`, `CountryBoundaries` with the driving side, each with its tests.
- Phase 10 (Streets): done except the reading of lanes from tags, **blocked by Muv** (below). With the lanes the Rust gives, the four outputs are byte-identical to the Rust on all 29 XML cases of osm2streets and on the Moscow data.
- Phase 11 (swap `Seed` onto `Streets`) cannot start until the Muv question is decided.

## The blocker: osm2lanes reads every lane through Muv

The task assumed streets_reader only calls `muv_osm::lanes::highway::driving_side`. In fact osm2lanes's `get_lane_specs_ltr` (`osm2lanes/src/algorithm.rs`), the one function that turns a way's tags into its lanes, is built on Muv:

- `muv_osm::lanes::lanes(&tags, &[country])` interprets every lane tag (`lanes`, `*:lanes`, `oneway`, `sidewalk`, `cycleway`, `parking`, `access`, `turn`, `width`, conditional restrictions, units). It is about 6 to 8 thousand lines of Muv (`muv-osm/src/lanes/`, `tmode.rs`, `conditional.rs`, `units/`), MPL-2.0.
- osm2lanes's own code around it (the access ranking of modes, `TMode::iter_hierarchy`, kerbs from Muv's kerb positions, the lifecycle) works on Muv's types.
- The lane polygons GeoJSON writes every Muv `Lane` as it is (`serde_json::to_value(muv)`, the `muv` property), and `CollapseDegenerateIntersections` compares the Muv lanes of two roads.

So the lanes, and through their widths every road, intersection and marking, depend on Muv. The task forbids porting or copying Muv. The smallest input that shows it: any way, for example `highway=residential` alone, whose lanes (a sidewalk, two driving lanes, a sidewalk, with kerbs) come out of `muv_osm::lanes::lanes`.

Three ways out, for the user to decide:

1. Port Muv's lane interpretation as a separate target under its own licence, MPL-2.0 (file-level copyleft: those files stay MPL and public, the rest of the package stays MIT). It needs a new target in `Package.swift`: `.target(name: "MuvLanes", path: "Sources/MuvLanes", exclude: ["LICENSE"])` and `"MuvLanes"` added to the dependencies of `Streets` and `StreetsTests`.
2. A clean-room lane interpreter from the OSM wiki, matched to Muv by black-box tests against the Rust binary. Exact parity is unlikely: the `muv` property of the lane polygons is Muv's own data model, serialised by serde.
3. Keep the Rust binary for seeding (phase 11 not done).

What the port does meanwhile: the reading of lanes is a seam, `LaneSpecSource` (osm2lanes's `get_lane_specs_ltr(tags, config)`), passed to `StreetNetwork.fromOSM`. `RecordedLaneSpecs` serves lanes recorded per tag set. The parity tests record the Rust's lanes for every tag set of a case from the Rust binary itself (`Tests/StreetsTests/Parity/LaneHarvest.swift`): a synthetic OSM file holds one way per tag set, each crossing the whole box of the case so that clipping makes both its ends map edges and nothing collapses, inside the same box, so the country (and Muv's legal defaults) are the same. The port then runs with those lanes. That proves everything except Muv's `lanes()` against the Rust. osm2lanes's own pieces that need no Muv type (`infer_sidewalk_tags`, `traffic_direction`, the typical widths, placement, turns) are ported.

## Targets

| Target | Ports | State |
|---|---|---|
| `Earcut` | earcutr 0.4.3 | done. 31 tests, the crate's 35 fixtures give the same triangles index for index |
| `GeoAlgorithms` | geo 0.27 subset (geo-types, sweep and BooleanOps, area, contains, intersects, coordinate position, line intersection, RDP and VW simplification, winding, closest point, distance, convex hull, centroid), polylabel 3.2 (with geo 0.28), robust 1.2, float_next_after | done. 207 tests pass, 7 skip (they read geo-test-fixtures, not in the cargo registry) |
| `StreetGeom` | geom 9bb49fc, the parts osm2streets uses, and serde_json's number reading and pretty printing | done, unit tests and every number of a Rust output round-tripped |
| `OSMReader` | osm-reader 7892405, XML only | done, tests |
| `CountryBoundaries` | country-boundaries 1.2.0, data 60x30 as generated base64 source (ODbL), and the driving side | done. 59 tests, the driving side equal to Muv's for its 251 codes and every id of the data |
| `Streets` | osm2streets, streets_reader, osm2lanes without Muv | done with recorded lanes, parity below |

## Decisions

- `CountryBoundaries` names its driving side `CountryDrivingSide`, so it does not clash with osm2lanes's `DrivingSide` in `Streets`.
- Rust `HashMap` iteration that reaches the output (streets_reader's traffic signals and crossings, `split_ways.rs`) is random in the Rust. The port iterates them in insertion order (node id order). See the parity notes.
- PBF input is not ported (the pipeline writes XML). osm2streets's test `frederiksted` is PBF and is not run.
- The clip GeoJSON is read with serde_json's float algorithm (no `float_roundtrip`), not `Double(String)`: serde_json is off by one unit in the last place on some coordinates, and the port must be off the same way.
- `checkInvariants` is ported but the parity tests do not call it: the Rust CLI does not, and with the pipeline's configuration the invariants do not always hold in the Rust either (an intersection left without roads after a road is skipped).
- Transformations: the three of `standard_for_clipped_areas` are ported and checked. `RemoveDisconnectedRoads` and `ZipSidepaths` (with petgraph's A* on a `DiGraphMap`, its open set in Rust's `BinaryHeap` order) are ported and unit-tested on made-up networks, not checked against the Rust: the binary never runs them. `MergeDualCarriageways` only adds debugging output in the Rust, so it is a no-op here.
- Not ported because nothing the pipeline calls reaches them: osm2lanes's lane editing (`edit/`), osm2streets's `block.rs`, `render/output.rs`, `paint.rs`, `marking.rs`, debug steps, pathfinding beyond `find_nearby_roads`, the geom pieces only those use (`FindClosest`, `QuadTree`, times and durations).
- Muv's `Lane` is carried as its serde JSON (`LaneSpec.muv`). Rust compares `LaneSpec`s with Muv's derived `PartialEq`, the port compares the JSON. They agree on every case run.

## Parity numbers

`swift test --filter StreetsTests` (debug build, 332 tests, about 210 s), the Rust being `osm2streets-cli` of the pipeline (rev fc119c4, arm64), with the pipeline's configuration (inferred sidewalks and kerbs) and the lanes recorded from the Rust as described above. "Identical" means byte-identical GeoJSON text. 2026-10-25:

| Case | Roads | Intersections | Tag sets | plain | lanes | lane_markings | intersection_markings |
|---|---|---|---|---|---|---|---|
| osm2streets's 29 XML cases (all but the PBF `frederiksted`) | 4 to 515 | 4 to 409 | 2 to 180 | 29 identical | 29 identical | 28 identical, `roosevelt_cycletrack` one of the Rust's results | 29 identical |
| Moscow 2x2 region, with its clip | 4874 | 4642 | 943 | identical (9516 features) | identical (7557) | identical (58360) | identical (229) |
| Moscow tile 15/19808/10242, unclipped | 1563 | 1577 | 437 | identical (3140) | identical (2543) | identical (21213) | identical (65) |
| Moscow tile 15/19809/10242 | 1389 | 1377 | 284 | identical (2766) | identical (2479) | one of the Rust's results (18026) | identical (59) |
| Moscow tile 15/19808/10243 | 2091 | 1846 | 383 | identical (3937) | identical (2699) | identical or one of the Rust's results (29442) | identical (59) |
| Moscow tile 15/19809/10243 | 1614 | 1529 | 370 | identical (3143) | identical (2746) | identical (22910) | identical (131) |
| Moscow tile 15/19810/10243 | 1394 | 1349 | 248 | identical (2743) | identical (2568) | identical or one of the Rust's results (18110) | identical (71) |

The Rust is not deterministic where two crossings (or traffic signals) on one road both fall within 30% of the same end: streets_reader iterates them in `HashMap` order, random per process, and the last one sets the stop line. Measured: `roosevelt_cycletrack` gave 2 different `lane_markings.geojson` in 12 runs of the Rust (on road 106, way 621283289, crossings at 72.5 m and 87.5 m of 90.8 m: with 87.5 m the stop line falls past the lane's end and is not drawn), the tile 15/19809/10242 5 in 16 runs, 15/19808/10243 2 in 16. The port iterates them in node id order and its result has each time been one of the Rust's. The parity test runs the Rust 16 times when the first run differs, and passes only when the port's four files equal one run's four files, byte for byte.

Not compared: the committed `geometry.json` of osm2streets's tests. They are made with `MapConfig::default()` (no inferred sidewalks), and the harvest can only record lanes as the pipeline's binary reads them (inferred sidewalks). Blocked with Muv.

Found on the way: serde_json reads some coordinates of the clip 1 or 2 units in the last place off. Before the port read numbers the same way, 7 cases differed by that much in every coordinate.

## Commits

- `5935bdb` Earcut. `3130717` CountryBoundaries. `7ddc315`, `cc93bb6` OSMReader. `7217ddf` GeoAlgorithms. `1aec73d` StreetGeom. `1cf1ea7` Streets with the parity tests. Then the remaining transformations.

## Left

- The Muv decision, then the lane reading (and the `geometry.json` checks, which need it).
- A way to check `ZipSidepaths` and `RemoveDisconnectedRoads` against the Rust (the binary does not run them).
- Speed: the port takes 19.7 s for the Moscow region in a debug build, 6.8 to 10.9 s per tile (the Rust: 0.8 s for the region). A release run of the tests hung in swift-testing and was stopped, so release is not measured.
- Phase 11 and on.
