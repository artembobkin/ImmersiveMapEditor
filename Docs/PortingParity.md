# Porting parity

What was compared, on what data, what matched, and every difference with its reason (Docs/PortingGoal.md, "Parity").

## Topology

### The oracle on the JTS XML suites

GEOS 3.13.0 (the `GEOSwift/geos` 9.0.0 package) run on the JTS 1.20.0 XML suites by `JTSXMLGEOSTests`, to check the runner before it checks the port. Every file parses. The tests GEOS does not pass are listed one by one, with GEOS's result, in `Tests/TopologyTests/JTSXML/GEOSBaseline.swift`, and the test fails if that set changes.

| Suite | Tests | GEOS passes | Fails | Errors |
|---|---:|---:|---:|---:|
| general | 2,477 | 2,411 | 65 | 1 |
| validate | 5,326 | 5,325 | 1 | 0 |
| robust | 2,091 | 2,089 | 2 | 0 |
| misc | 504 | 498 | 5 | 1 |

Where GEOS differs from what JTS's tests expect, by kind:

- Overlays with an empty input (`TestOverlayEmpty`, `TestNGOverlayEmpty`, `TestNGOverlayA` 18, `TestUnaryUnion` 14 to 17): GEOS gives another type of empty result (`GEOMETRYCOLLECTION EMPTY` for `POLYGON EMPTY`), and keeps an empty polygon as a member of a union (`MULTIPOLYGON (((10 10, ...)), EMPTY)`).
- `minClearance` of a geometry with no clearance: GEOS gives infinity, JTS `Double.MAX_VALUE`.
- `getInteriorPoint` of a collection holding an empty polygon (`TestInteriorPoint` 22, 23): GEOS gives `POINT EMPTY`, JTS the interior point of the line.
- `getCentroid` of an almost degenerate triangle (`TestCentroid` 37): GEOS `POINT (56.52883333333333 25.210333333333335)`, JTS `POINT (56.52883333335 25.21033333335)`.
- A WKT with text after the geometry (`TestCentroid` 10): GEOS refuses it, JTS reads it.
- `densify` of a polygon (`TestDensify` 13, 14), mitred buffers (`TestBufferMitredJoin` 1, 2, 4), overlays at a fixed precision (`TestOverlayAAPrec` 5, 14, `TestOverlayLLPrec` 1), JTS's old overlay results against OverlayNG (`misc/TestOverlay`, `geos-bug838-union`, `TestOverlay-pg-list` 4), and two relates (`TestRelatePL` 2.7, `TestRobustRelateFloat` 1.1).

### Phase 2: the core against GEOS

Every comparison is exact: numbers bit for bit, geometries in GEOS's normal form (`GEOSNormalize` of both) bit for bit, predicates equal. No tolerance is used anywhere in this phase. The random inputs are seeded (`Tests/TopologyTests/Parity/RandomGeometries.swift`): star-shaped polygons with holes, lines, points and their collections, near the origin, at a city's metres, in degrees and far away (1e7), with collinear and repeated vertices, slivers, holes touching the shell, integer grids, and empty geometries.

| Function | Random | Equal | Recorded real calls | Equal |
|---|---:|---:|---:|---:|
| `Orientation.index` (DD, `GEOSOrientationIndex`), near-collinear triples | 200,000 | 200,000 | | |
| `Orientation.isCCW` (`GEOSCoordSeq_isCCW`) | 20,000 | 20,000 | | |
| `RobustLineIntersector` (`GEOSSegmentIntersection`): crossing, touching, collinear, almost parallel | 200,000 | 200,000 | | |
| area | 20,000 | 20,000 | 106,978 | 106,978 |
| length | 20,000 | 20,000 | 48,044 | 48,044 |
| bounds | 18,000 | 18,000 | 15,570 | 15,570 |
| envelope | 20,000 | 20,000 | | |
| centroid | 20,000 | 20,000 | 265 | 265 |
| interior point (`representativePoint`) | 20,000 | 20,000 | 4,367 | 4,367 |
| convex hull | 20,000 | 20,000 | 248 | 248 |
| boundary (not of a collection, which both refuse) | 18,595 | 18,595 | 15 | 15 |
| minimum rotated rectangle (`MinimumAreaRectangle`) | 20,000 | 20,000 | 2,013 | 2,013 |
| normalize, compared raw (not renormalized) | 20,000 | 20,000 | | |
| point location (`PointLocator`) as `GEOSIntersects` of a point | 23,416 | 23,416 | | |
| point location as `GEOSContains` of a point | 23,416 | 23,416 | | |
| WKT at rounding precision 3 (`Geometry.description`), text | 20,017 | 20,017 | | |
| WKB reading | | | 757,210 geometries | 757,210 |
| WKT reading (every input of the JTS XML suites) | 7,359 | 7,359 | | |

`GEOSMinimumRotatedRectangle` in GEOS 3.13 is JTS's `MinimumAreaRectangle`: it matches 20,000 of 20,000, `MinimumDiameter.getMinimumRectangle` (the rectangle of least width) 7,342.

Point location is compared on valid geometries that are not collections. On the others (parts of a multipolygon overlapping, a collection of a polygon and a line over it) GEOS's `contains` follows the relate rules, which are not a point locator's: 15 of 28,736 points differed there. They are compared again with the predicates themselves in phase 4.

The JTS XML suites, for the operations the port has: it passes exactly the tests GEOS passes, and its results are GEOS's bit for bit on all 110 of them.

| Operation | Tests | Passed (as GEOS) |
|---|---:|---:|
| `getCentroid` | 38 | 37 |
| `getInteriorPoint` | 24 | 22 |
| `convexhull` | 14 | 14 |
| `getboundary` | 12 | 12 |
| `equalsExact` | 18 | 18 |
| `equalsNorm` | 5 | 5 |

One more passes than GEOS: `TestCentroid` 10, whose WKT has a `)` too many, which JTS's reader (and the port's) ignores and GEOS's refuses.

#### Where GEOS 3.13 differs from JTS 1.20, and the port follows GEOS

Each was found by a parity test and confirmed on GEOS's output. The port keeps JTS's code and changes only what GEOS does otherwise.

- **Fused multiply-add.** GEOS is compiled here with Apple clang's default `-ffp-contract=on`, which fuses `a * b + c` inside one expression (checked: `fmadd` at `-O0` and `-O2`). The port fuses the same expressions (`Fused.swift`). Without it, area matches GEOS on 1,461 of 3,000 random polygons and segment intersection on 199,383 of 200,000; with it, on all.
- **Length and point distance**: `sqrt(dx * dx + dy * dy)` (fused), not JTS's `Math.hypot`. With `hypot`, length matches on 2,859 of 3,000 random lines, line centroids and interior points differ in the last bit.
- **Interior point**: by the geometry's dimension, not by the dimension of its non-empty parts (`TestInteriorPoint` 22, 23: a collection of an empty polygon and a line gives `POINT EMPTY`).
- **Envelope**: a rectangle counter-clockwise from the lower left corner, flat when the envelope is (JTS: clockwise, and a line for a flat envelope).
- **Boundary of a polygon**: line strings, not the rings.
- **Normal form**: members of collections and holes sorted in descending order, lines compared by their number of points first, a closed line normalized as a clockwise ring, and a polygon's ring re-closed only when it does not already end at its first point, so a repeated closing point goes.
- **Convex hull of two points**: in the order they first occur (JTS: Java's hash order).
- **WKT with a rounding precision**: GEOS's trimmed numbers (scientific below 1e-4 and from 1e17, fewer decimals below 1, the shortest digits rounded half to even).

### Phase 3: indexes and noding against GEOS

| What | Compared | Equal |
|---|---:|---:|
| STR tree query (`GEOSSTRtree_query`, capacity 10), random item sets of 0 to 1,500 geometries: random, on a grid, with duplicates | 6,000 | 6,000 |
| STR tree nearest (`GEOSSTRtree_nearest`, distance by `GEOSDistance` on both sides), ties included | 5,495 | 5,495 |
| replay: the recorded trees, their queries | 1,051 | 1,051 |
| replay: the recorded trees, their nearest searches | 279 | 279 |
| MC index noder in an iterated noder, duplicates dropped (`GEOSNode`) | 4,861 | 4,860, and 1 differing only in the sign of a zero |

The tree breaks ties as GEOS does only with libc++'s algorithms: JTS's stable sort and Java's `PriorityQueue` give the same nearest item on 4,609 of 5,495 searches (all the others are ties: equal envelope centres, equal distances), libc++'s `std::sort` and heap (`CxxAlgorithms`) on all 5,495. Queries are the same either way.

`GEOSNode` is not compared on a collection holding an empty geometry: GEOS 3.13 crashes on it (a segmentation fault, `GEOMETRYCOLLECTION (LINESTRING (0 0, 1 1), LINESTRING EMPTY)`). 139 of the 5,000 random inputs.

The open difference (Docs/PortingTopologyProgress.md, "Blocked"): a zero-length segment between `0.0` and `-0.0`. Smallest input: `LINESTRING (1 0, 0 0, -0 0, -1 -1)`, noded: the port gives `(1 0, 0 0), (0 0, -0 0), (0 0, -1 -1)`, GEOS `(1 0, 0 0), (-0 0, -0 0), (-0 0, -1 -1)`. The values are equal, only the sign of the zero differs.

Snap rounding is not exposed alone by GEOS's C API (its overlays at a precision and `GEOSGeom_setPrecision` of polygons use it): it is compared with GEOS through those in phases 4 and 6. Here it passes JTS's own cases (`SnapRoundingNoderTest`, 18 of 18, each result checked fully noded), and the KD-tree JTS's `KdTreeTest`.

## Streets

The Swift osm2streets (`Streets` on `StreetGeom`, `GeoAlgorithms`, `Earcut`, `OSMReader`, `CountryBoundaries`, `MuvLanes`) against the Rust binary of the pipeline (`osm2streets-cli`, rev `fc119c4`), the port reading every lane itself. The bar: byte-identical GeoJSON text. Details and the tag-set tests of `MuvLanes` in `Docs/PortingStreetsProgress.md`. Measured 2026-10-25, `swift test -c release -Xswiftc -enable-testing`.

| Compared | Data | Result |
|---|---|---|
| The four outputs (plain, lanes, lane markings, intersection markings), pipeline configuration | osm2streets's 29 XML test cases | 29 of 29 identical in all four |
| The same | Moscow 2x2 region with its clip (4874 roads, 943 tag sets) | identical in all four (9516, 7557, 58360, 229 features) |
| The same | the five Moscow tiles, unclipped | identical, two tiles' lane markings equal to one of the Rust's own results (see below) |
| `to_geojson`, `MapConfig::default()`, invariants checked | the committed `geometry.json` of the 29 cases | 29 of 29 identical |
| The four outputs | synthetic ways: 280 hand-written and 400 random tag sets in each of 10 countries | 20 of 20 identical (one random way left out in FR: the Rust panics on it) |
| Seeding, `tilepipeline seed 15 19808 10242 19809 10243`, before (Rust binary) and after (in process) | the four Moscow tiles, temporary roots | the road document identical but its `"seeded"` date, the four `streets/` outputs byte-identical |

Accepted difference, none in the port: the Rust is not deterministic where two crossings or traffic signals set the same road end (streets_reader iterates a `HashMap`, random per process). The test does not sample this: the port computes its outputs for every order of each contested road end (`HashMapOrder`), and every Rust run must equal one of them (16 runs where the order changes the result). Measured over 200 Rust runs: 15/19809/10242 gives exactly the port's 6 results (three contested road ends, 2 by 2 by 3 crossings), 15/19808/10243 exactly its 2. Details in `Docs/PortingStreetsProgress.md`.
