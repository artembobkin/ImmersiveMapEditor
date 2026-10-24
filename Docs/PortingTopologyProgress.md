# The Topology port: progress

The port of JTS 1.20.0 to Swift (`Sources/Topology`), phases 1 to 3 of `Docs/PortingGoal.md`, on the branch `port/topology`. The parity numbers are in `Docs/PortingParity.md`, section Topology.

## Done

### Phase 1: oracle and recording

- **The GEOS oracle** (`Tests/TopologyTests/Oracle/`): `GEOSOracle` (a GEOS context per test, WKT, hexadecimal and binary WKB read and written, `normalized`, `transformed`, a geometry to and from `Shape`), `GEOSOperations` (the C API's shapes, so a test names the GEOS function it compares with), `Shape` (a geometry as plain values, compared bit for bit), `TestPaths` (where the JTS sources and the recordings are).
- **The JTS XML runner** (`Tests/TopologyTests/JTSXML/`): `JTSTestFile` (the XML read as JTS's `TestReader` reads it: precision model, tolerance, result matcher, geometry operation, cases and tests), `JTSTestRunner` (an engine runs each test, the result compared as JTS compares it: normalized `equalsExact` within the tolerance, the buffer matcher, booleans and numbers), `GEOSEngine` (every JTS operation of the suites on GEOS). `JTSXMLGEOSTests` runs the four suites on GEOS and checks the outcome against `GEOSBaseline` (written by the test with `WRITE_GEOS_BASELINE=1`).
- **The recording mode** (`Sources/Geometry/Recorder.swift`, hooks in `Geometry.swift`): `GEOMETRY_RECORD=<folder>` writes every operation's inputs (WKB, exact) and parameters to `geometry-<pid>.rec`, and the count of every call to `geometry-<pid>.counts` at exit. Without the variable each operation reads one static that is nil. The public API of `Geometry` is unchanged.
- **The recordings** (`.build/recording/` of this worktree, outside git, read by `RecordingTests` and the replays):
  - `tiles/<x>_<y>/`: `tilepipeline --root ~/Desktop/TilePipeline lab data/15_<x>_<y> /private/tmp/claude-501/topology-record/tiles/<x>_<y> --whole --export --samples 16`, release build, for the five tiles.
  - `seed/`: `tilepipeline --root <tmp> seed 15 19808 10242 19809 10243` in `/private/tmp/claude-501/topology-record/seed-root`, whose `data/` holds links to the four tiles' folders (so `data/regions/` is written in the temporary root), `tools/osm2streets_cli/target/release/osm2streets-cli` a link to the real binary, `roads/` empty.

#### The recording's summary

| Recording | Calls | Geometries |
|---|---:|---:|
| tiles/19808_10242 | 565,850 | 172,909 |
| tiles/19808_10243 | 545,246 | 267,697 |
| tiles/19809_10242 | 37,605 | 31,510 |
| tiles/19809_10243 | 815,313 | 144,527 |
| tiles/19810_10243 | 25,991 | 15,506 |
| seed (2x2 block) | 226,531 | 125,061 |
| **all** | **2,216,536** | **757,210** |

Calls of each function, over all six recordings: `intersects` 1,428,861, `Prepared.contains` 175,334, `buffer` 112,586, `area` 106,978, `distance` 100,452, `length` 48,044, `isValid` 47,724, `unaryUnion` 41,654, `makeValid` 32,248, `contains` 16,649, `setPrecision` 16,124, `bounds` 15,570, `intersection` 14,804, `lineMerge` 14,668, `polygonize` 14,663, `constrainedDelaunay` 9,495, `simplify` 6,276, `representativePoint` 4,367, `interpolate` 3,062, `difference` 2,462, `minimumRotatedRectangle` 2,013, `STRtree.query` 1,051, `project` 311, `STRtree.nearest` 279, `offsetCurve` 273, `centroid` 265, `convexHull` 248, `nearestPoints` 34, `boundary` 15, `Prepared.init` 14, `STRtree.init` 6, `union` 6. Never called: `within`, `envelope`, `description`, `Prepared.intersects`. The seeding alone makes the `offsetCurve`, `project`, `nearestPoints`, `STRtree.nearest` calls and most `makeValid` and `setPrecision` ones. Constructors are counted, not written (`.counts`): for 19808/10243, `polygon` 143,698, `lineString` 36,627, `point` 28,622, `collection` 23,309.

### Phase 2: the topology core

`Sources/Topology/`, by JTS's packages: `Geom` (`Coordinate`, `Envelope`, `PrecisionModel`, `Location`, `Dimension`, the geometry classes, `GeometryFactory`, `CoordinateSequences`, `CoordinateArrays`, `LineSegment`), `Math` (`DD`, `Fused`, `MathUtil`, `JavaMath`), `Algorithm` (`CGAlgorithmsDD`, `Orientation`, `RobustLineIntersector`, `Intersection`, `Distance`, `RayCrossingCounter`, `PointLocation`, `PointLocator`, `BoundaryNodeRule`, `Area`, `Length`, `Centroid`, the interior points, `ConvexHull`, `BoundaryOp`, `MinimumAreaRectangle`, `MinimumDiameter`, `Rectangle`), `IO` (`WKTReader`, `WKTWriter`, `WKBReader`). Checked against GEOS on random and recorded inputs, all equal bit for bit (`Docs/PortingParity.md`). Tests: `Tests/TopologyTests/Parity/`, `JTSXML/TopologyEngine.swift` with `JTSXMLTopologyTests`, `Recording/ReplayTests.swift`.

## Left

- Phase 3: indexes and noding.

## Decisions

- **The port follows GEOS where GEOS 3.13 differs from JTS 1.20**, since parity with GEOS is the bar: each difference is found by a parity test, confirmed on GEOS's output, and listed in `Docs/PortingParity.md` ("Where GEOS 3.13 differs from JTS 1.20"). The JTS XML suites then pass on the port exactly where they pass on GEOS. GEOS's sources are not read: the differences are inferred from its results.
- **Two dimensions.** `Coordinate` is x and y: the package's geometry is planar and GEOS is called with XY. The readers drop Z and M.
- **Geometries are classes**, as JTS's (`normalize` changes one in place), their coordinates contiguous arrays of a value type. Envelopes, segments, DD, intersectors and locators are values.
- **Names are JTS's** (`getEnvelopeInternal`, `getNumPoints`), so the port reads side by side with JTS.
- **Programming errors trap** (`precondition`), as JTS's `IllegalArgumentException` and assertions do: a ring that is not closed, the boundary of a collection. The readers check their input and throw instead.
- **GEOS here is built with fused multiply-add.** The `GEOSwift/geos` package compiles GEOS with SwiftPM's default flags, and Apple clang's default `-ffp-contract=on` fuses `a * b + c` inside one expression into one `fmadd` on arm64, in debug and release alike (checked on a two-line function: `fmadd` at `-O0` and `-O2`). JTS on the JVM never fuses. So the GEOS this package runs today does not compute JTS's arithmetic exactly wherever an expression multiplies and adds. The port follows JTS's operations and adds the fusion clang makes (`Fused.swift`, `addingProduct`): the rule is clang's, the left product of a sum or difference first. Every such place is checked against GEOS, and the tests fail without it.
- The oracle and the runner read the JTS sources from `.build/ports/jts` of the package or of a folder above it (a worktree), or `JTS_ROOT`. The XML suites are not copied into the package: 16 MB, and a test target cannot hold non-Swift files without declaring them in `Package.swift`.
- The recordings are outside git. The tests that read them run only when they are there (`.enabled(if: Recording.available)`), the JTS XML tests always.
- `GEOSEngine` maps JTS's old overlay names (`intersection`, `union`) to GEOS's overlay (OverlayNG), the `SR` overlays to the `Prec` functions with grid `1 / scale`, and a fixed precision model to coordinates rounded on reading (as JTS's `WKTReader`) and the `Prec` overlays. GEOS has no oriented Hausdorff distance, so the buffer matcher uses the symmetric one, the stricter check.
