# The Topology port: progress

The port of JTS 1.20.0 to Swift (`Sources/Topology`), phases 1 to 7 of `Docs/PortingGoal.md`, on the branch `port/topology`. The parity numbers are in `Docs/PortingParity.md`, section Topology.

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

### Phase 3: indexes and noding

`Index`: `STRtree` (query, nearest neighbour, ties broken as GEOS), `JavaPriorityQueue`, `CxxAlgorithms` and `CxxPriorityQueue` (libc++'s `std::sort` and heap, see the licence), `Chain` (`MonotoneChain`, `MonotoneChainBuilder`), `KdTree`. `Noding`: segment strings (`SegmentString`, `NodableSegmentString`, `BasicSegmentString`, `NodedSegmentString`, `SegmentNode`, `SegmentNodeList`, `Octant`, `SegmentPointComparator`, `OrientedCoordinateArray`), `SegmentIntersector` and `Noder`, `IntersectionAdder`, `InteriorIntersectionFinderAdder`, `NodingIntersectionFinder`, `MCIndexNoder`, `IteratedNoder`, `ScaledNoder`, `FastNodingValidator`, `ValidatingNoder`, `SnapRound` (`HotPixel`, `HotPixelIndex`, `SnapRoundingIntersectionAdder`, `SnapRoundingNoder`). `Geom`: `Quadrant`, `TopologyException`. `Math`: `JavaRandom`. Checked against GEOS (`Docs/PortingParity.md`, phase 3), equal bit for bit.

### Resolved: the sign of a zero at a node

Phase 3 ended with one difference: at the zero-length segment of `LINESTRING (1 0, 0 0, -0 0, -1 -1)` through `GEOSNode`, the port's nodes took `0.0` and GEOS's `-0.0` (equal values). Four orders tried then (JTS's; the other chain first; the higher id first; a lazily sorted node list alone) each left one of two inputs differing. The main session then allowed GEOS's noding sources to be read to find its order (never copied). They show two things together, both now in the port: GEOS's STR tree reports the pairs of chains by its packed leaf order, each leaf against the leaves after it (`STRtree.queryPairs`, used by `MCIndexNoder`), and GEOS keeps a segment string's nodes in an array, sorted with `std::sort` when read and de-duplicated keeping the first of equal nodes (`SegmentNodeList`). With both, all 4,861 random inputs and both inputs of phase 3 are GEOS's bit for bit, the sign of every zero included.

### Phase 4, step 1: overlay and union

- **OverlayNG** (`Operation/OverlayNG/`): `OverlayNG` (floating precision, fixed precision with snap rounding, the strict mode), `OverlayNGRobust` (floating, then snapping with a growing tolerance, then snap rounding at a safe scale), `EdgeNodingBuilder` (clipping with `RingClipper` and `LineLimiter`, the `RobustClipEnvelopeComputer`), `Edge`, `EdgeKey`, `EdgeMerger`, `EdgeSourceInfo`, `OverlayLabel`, `OverlayEdge`, `OverlayGraph`, `OverlayLabeller`, `MaximalEdgeRing`, `OverlayEdgeRing`, `PolygonBuilder`, `LineBuilder`, `IntersectionPointBuilder`, `OverlayPoints`, `OverlayMixedPoints`, `IndexedPointOnLineLocator`, `InputGeometry`, `OverlayUtil`, `PrecisionUtil`. `EdgeGraph/HalfEdge`. `Noding/Snap/` (`SnappingNoder`, `SnappingPointIndex`, `SnappingIntersectionAdder`). `Algorithm/Locate/` (`PointOnGeometryLocator`, `IndexedPointInAreaLocator` over `Index/IntervalRTree/SortedPackedIntervalRTree`, `SimplePointInAreaLocator`). `Geom`: `Position`, `CoordinateList`, `Util/LinearComponentExtracter`, `Util/GeometryCombiner`. `Util/Exceptions` (the errors the robust overlay catches).
- **Union** (`Operation/Union/`): `UnaryUnionOp`, `CascadedPolygonUnion`, `PointGeometryUnion`, `UnionStrategy`, `GeometryOverlay` (the `Geometry` methods `intersection`, `union`, `difference`, `symDifference`, `union()` as GEOS 3.13 runs them), `MixedDimensionOverlay` (GEOS's overlay of collections of mixed dimensions, which JTS refuses).
- **Index**: `CxxUnorderedMap` (the iteration order of libc++'s `unordered_map`, see the licence), `STRtree.itemsInPackedOrder` and `queryPairs`.
- Checked against GEOS (`Docs/PortingParity.md`, phase 4): random and near-degenerate inputs, the JTS XML suites, and every recorded `intersection`, `difference`, `union` and `unaryUnion` call, all GEOS's bit for bit, results in GEOS's normal form and as they come. Tests: `Parity/OverlayParityTests`, `Recording/OverlayReplayTests` (long: `TOPOLOGY_LONG_REPLAY=1`), the overlays in `JTSXML/TopologyEngine`, `Parity/DebugCaseTests` (one case on both sides, from `DEBUG_OP`, `DEBUG_A`, `DEBUG_B`).
- How differences were found: the parity helpers write every difference in full to the file named by `PARITY_DUMP`; a case is run on both sides with `DebugCaseTests`; and GEOS's internal stages are observed with lldb on the test binary (breakpoints on GEOS's functions and on C++ throws, its edges printed at `OverlayGraph::addEdge`), which showed which stage of the robust overlay each side ended at.

### Phase 4, step 2: predicates, distance and nearest points

- **RelateNG** (`Operation/RelateNG/`): `RelateNG`, `RelateGeometry`, `RelatePointLocator`, `AdjacentEdgeLocator`, `LinearBoundary`, `TopologyComputer`, `NodeSection`, `NodeSections`, `PolygonNodeConverter`, `RelateNode`, `RelateEdge`, `RelateSegmentString`, `EdgeSegmentIntersector`, `EdgeSetIntersector`, `DimensionLocation`, the predicates (`TopologyPredicate`, `IMPredicate`, `RelatePredicate` with its named predicates, `IMPatternMatcher`, `RelateMatrixPredicate`) and `GeometryPredicates` (`Geometry`'s `intersects`, `contains`, `within` and the rest, as GEOS 3.13 dispatches them; they throw where JTS and GEOS fail). `Geom/IntersectionMatrix`, `Algorithm/PolygonNodeTopology`, `Operation/Predicate/` (`RectangleIntersects`, `RectangleContains`).
- **Prepared geometries** (`Geom/Prep/`): `PreparedGeometryFactory` with GEOS's choice of kind, `BasicPreparedGeometry` (a prepared RelateNG), `PreparedPoint`, `PreparedLineString`, `PreparedPolygon` (with GEOS's contains, covers, containsProperly and point locator). `Noding`: `MCIndexSegmentSetMutualIntersector`, `FastSegmentSetIntersectionFinder`, `SegmentIntersectionDetector`, `SegmentStringUtil`.
- **Distance** (`Operation/Distance/`): `DistanceOp` (distance, nearest points, within a distance, as GEOS runs it), `GeometryLocation`, `LineSegment.closestPoints`, `Geometry.distance`. `Envelope.distance` and `distanceSquared` as GEOS computes them.
- Checked against GEOS (`Docs/PortingParity.md`, phase 4): random pairs, the JTS XML suites and every recorded `intersects`, `contains`, `Prepared.contains`, `distance` and `nearestPoints` call, all equal. Tests: `Parity/PredicateParityTests`, `Parity/DistanceParityTests`, `Recording/PredicateReplayTests` and `DistanceReplayTests` (long), the predicates and distance in `JTSXML/TopologyEngine`.

### Phase 5: buffer and offset curve

- **The old planar graph** (`GeomGraph/`, namespace `GeomGraph`): `Label` and `TopologyLocation`, `Edge` and `EdgeList`, `EdgeEnd` and `DirectedEdge`, `DirectedEdgeStar`, `Node` and `PlanarGraph`, `EdgeRing`: the part of JTS's `geomgraph` the buffer uses. The old overlay's polygon builder (`Operation/Overlay/`, namespace `Overlay`): `PolygonBuilder`, `MaximalEdgeRing`, `MinimalEdgeRing`.
- **The buffer** (`Operation/Buffer/`): `BufferOp` (with GEOS's retries at reduced precision, 12 digits down to 6, snap rounding), `BufferParameters`, `BufferBuilder`, `BufferCurveSetBuilder`, `OffsetCurveBuilder`, `OffsetSegmentGenerator`, `OffsetSegmentString`, `BufferInputLineSimplifier`, `BufferSubgraph`, `RightmostEdgeFinder`, `SubgraphDepthLocater`; `Geometry.buffer` as `GEOSBufferWithStyle` takes it. `UnionStrategy.classic` now has its union by the buffer by zero of two areas whose overlay fails, reached only where GEOS reaches it (see `Docs/PortingParity.md`: robust OverlayNG's final failure is not a topology failure).
- **The offset curve** (`Operation/Buffer/OffsetCurve.swift`): `OffsetCurve`, `OffsetCurveSection`, `SegmentMCIndex` (GEOS 3.13's `GEOSOffsetCurve`); `Geometry.offsetCurve`.
- Helpers: `Algorithm/Angle`, `Geom/Triangle` (in-centre), `Geom/Util/GeometryMapper` (`flatMap`), `LineSegment.offset`.
- Not ported: single-sided buffers (GEOS builds them with the polygonizer and line merger, phases to come; the package never asks for one), the joined offset curve, the variable buffer. `MCIndexSnapRounder` (see Decisions).
- Checked against GEOS (`Docs/PortingParity.md`, phase 5): 8,000 random buffers and 4,000 random offset curves, the JTS XML buffer tests, and every recorded `buffer` (112,586) and `offsetCurve` (273) call, all equal bit for bit, normalized and as they come. No tolerance was needed: GEOS's arcs are computed with the same `sin` and `cos` of the system's libm. Tests: `Parity/BufferParityTests`, `Recording/BufferReplayTests` (long), `buffer` and `bufferMitredJoin` in `JTSXML/TopologyEngine`.

### Phase 6: validity, make valid, precision, simplify

- **Validity** (`Operation/Valid/`): `IsValidOp`, `TopologyValidationError` (GEOS's messages), `PolygonTopologyAnalyzer`, `PolygonIntersectionAnalyzer`, `PolygonRing` (with `PolygonRingTouch`, `PolygonRingSelfNode`; touches in the order of the ring indices, GEOS's ordered map), `IndexedNestedHoleTester`, `IndexedNestedPolygonTester`; `Geometry.isValid()`.
- **Make valid** (`Operation/Valid/MakeValid.swift`, `Operation/Polygonize/BuildArea.swift`): GEOS 3.13's default "linework" method. JTS has no such class (it has only the structural `GeometryFixer`): written for this port from the algorithm (rttopo's and PostGIS's `ST_MakeValid`, `ST_BuildArea`, as GEOS documents and runs it), on the port's JTS operations, in GEOS's order of operations (see Decisions). `Geometry.makeValid()`.
- **Precision** (`Precision/GeometryPrecisionReducer.swift`, `Geom/Util/GeometryTransformer.swift`): `GeometryPrecisionReducer`, `PrecisionReducerTransformer`, `PointwisePrecisionReducerTransformer`, `PrecisionReducer` (OverlayNG's), `GeometryTransformer` (GEOS's rules), the copy of `GeometryEditor` with its no-op operation; `Geometry.setPrecision(_:)` as `GEOSGeom_setPrecision` with flags 0 runs it.
- **Simplify** (`Simplify/TopologyPreservingSimplifier.swift`): `TopologyPreservingSimplifier`, `TaggedLinesSimplifier`, `TaggedLineStringSimplifier`, `TaggedLineString`, `TaggedLineSegment`, `LineSegmentIndex` (a uniform grid instead of the quadtree: the same candidates, and every use asks only whether one intersects badly), `ComponentJumpChecker`; `Geometry.topologyPreserveSimplify(_:)`.
- Shared: `Math/NonFinite.swift` (GEOS's exception on a non-finite point in its orientation test, see Decisions), `Index/CxxTree.swift` (libc++'s red-black tree, GEOS's `std::set` and `std::map`), `GeometryFactory.createLinearRingChecked`, GEOS's NaN semantics of `Envelope` (`isNull`, `intersects`).
- Tests: `Parity/ValidityParityTests`, `Parity/MakeValidParityTests`, `Parity/PrecisionParityTests`, `Parity/SimplifyParityTests`, `Parity/InvalidGeometries` (the often invalid inputs), `Recording/ValidityReplayTests`, `Recording/RepairReplayTests` (long), `Recording/ShapeReplayTests` (simplify), `isValid` and `simplifyTP` in `JTSXML/TopologyEngine`.

### Phase 7: triangulation, polygonize, line merge, linear referencing

- **Planar graph** (`Planargraph/PlanargraphComponents.swift`, namespace `Planargraph`): `GraphComponent`, `Node`, `Edge`, `DirectedEdge`, `DirectedEdgeStar`, `PlanarGraph`, in GEOS's orders.
- **Polygonize** (`Operation/Polygonize/`, namespace `Polygonize`): `Polygonizer`, `PolygonizeGraph`, `PolygonizeEdge`, `PolygonizeDirectedEdge`, `EdgeRing`, `HoleAssigner`; `Geometry.polygonize(_:)` as `GEOSPolygonize`.
- **Line merge** (`Operation/Linemerge/LineMerger.swift`): `LineMerger`, `LineMergeGraph`, `LineMergeEdge`, `LineMergeDirectedEdge`, `EdgeString`; `Geometry.lineMerge()` as `GEOSLineMerge`.
- **Constrained Delaunay** (`Triangulate/`): `ConstrainedDelaunayTriangulator`, `PolygonHoleJoiner` (with `PolygonNoder`'s node adder), `PolygonEarClipper`, `TriDelaunayImprover`, `TrianglePredicate` (GEOS's in-circle test, not JTS's), `Tri`, `TriEdge`, `TriangulationBuilder`; `Index/VertexSequencePackedRtree`; `Triangle.intersects`.
- **Linear referencing** (`Linearref/LengthIndexedLine.swift`): `LengthIndexedLine` (`extractPoint`, `project`), `LengthLocationMap`, `LengthIndexOfPoint`, `LinearLocation`, `LinearIterator`; `Geometry.interpolate(_:normalized:)`, `Geometry.project(_:)` as `GEOSInterpolate`, `GEOSInterpolateNormalized` and `GEOSProject`.
- Not ported, not reachable from `Geometry.swift`: the single-sided buffer (`Geometry.swift` never sets it), `LineSequencer`, `IsSimpleOp`, the structural `GeometryFixer`.
- Tests: `Parity/LinesParityTests` (polygonize, line merge), `Parity/TriangulationParityTests` (triangulation, linear referencing), `Recording/LinesReplayTests`, `Recording/ShapeReplayTests`, `polygonize` in `JTSXML/TopologyEngine`.

### Phase 8: `Geometry` on `Topology`

- **The swap** (`Sources/Geometry/`): `Geometry.swift` (the class, making and reading), `Operations.swift`, `Transforms.swift` (what was already Swift), `Prepared.swift`, `STRtree.swift`, `Inspection.swift` (internal: WKB in and out and the precision grids, for the replay), `Recorder.swift`. The `Geometry` target depends on `Topology` only; `geos` stays a dependency of `TopologyTests`, the oracle. The public API is the same, but for `Geometry.ptr` and `Geometry.init(owning:)`, the GEOS pointer, which nothing outside the target used (the tests' GEOS oracle has its own). Every operation is the port's function of the table below, inside `NonFinite.scope`, and fails as the C API failed (`Failure`: an empty collection, 0, false, -1, `(.zero, .zero)`, nil). The constructors keep the old wrapper's corners: a hole that is no ring (too few points, a NaN first point) makes the whole polygon an empty collection (the wrapper handed GEOS a null hole), the boundary of a geometry collection is empty, an STR tree given one geometry twice reports its last index.
- **The recording mode** works as before: `Topology`'s `WKBWriter` (new, JTS's, two dimensions, little-endian) writes the bytes GEOS's writer wrote. A recording made after the swap is byte for byte the one made with GEOS (three tiles, see `Docs/PortingParity.md`).
- **Non-finite coordinates**: every operation of `Geometry` runs in `NonFinite.scope`, the C API's catch, so the predicates, the buffer, the distance, the hulls and the rest fail where GEOS throws, as the overlays and phases 6 and 7 already did. A random test of non-finite input through both wrappers (`Parity/WrapperNonFiniteTests`) found where the port went on past GEOS's throw or computed otherwise; each is now GEOS's (see `Docs/PortingParity.md`, phase 8), but one input, recorded there as open.
- **Precision models**: geometries carry their factory, so a cleaned geometry (`setPrecision(0.01)`) is overlaid and buffered by snap rounding on its grid, as with GEOS. `setPrecision` copies, as GEOS's C API does, when the grid is 0 or the one the geometry already has.
- Tests: `Recording/WrapperReplayTests` (every recorded call through both wrappers, as recorded and on the grid of 0.01; the first 3,000 calls of each recording always, all with `TOPOLOGY_LONG_REPLAY=1`; the WKB writer on every recorded geometry), `Parity/WrapperNonFiniteTests`, `Oracle/GEOSWrapper` (the old wrapper, the oracle).
- Topology changed where non-finite input showed GEOS 3.13 computing otherwise (the list is in `Docs/PortingParity.md`, phase 8): new `IO/WKBWriter`, `Index/IntervalSTRtree` (GEOS's index of `IndexedPointInAreaLocator`; `SortedPackedIntervalRTree` is no longer used), `CxxAlgorithms.sortDoubles`, `NonFinite.watch`. One random non-finite input is still open (the same section).
- End to end (`Docs/PortingParity.md`, phase 8): the five tiles' GLB geometry, `stats.json` and palettes identical, the light maps within the bake's noise, seeding and the editor identical, a whole tile in at most 1.29 times GEOS's build time, seeding 1.17 times.

### Every GEOS call of `Geometry.swift` and the port's answer

| GEOS (C API) | Port (`Topology`) |
|---|---|
| `GEOS_init_r`, `GEOSGeom_destroy_r`, `GEOSGeom_clone_r`, `GEOSFree_r`, `GEOSCoordSeq_destroy_r`, `GEOSPreparedGeom_destroy_r`, `GEOSSTRtree_destroy_r` | none needed: values and reference counting; a clone is `Geometry.copy()` |
| `GEOSGeom_createPointFromXY_r` | `GeometryFactory.createPoint(_:)` |
| `GEOSCoordSeq_copyFromBuffer_r`, `GEOSGeom_createLineString_r`, `GEOSGeom_createEmptyLineString_r` | `[Coordinate]`, `createLineString(_:)` |
| `GEOSGeom_createLinearRing_r`, `GEOSGeom_createPolygon_r`, `GEOSGeom_createEmptyPolygon_r` | `createLinearRing(_:)`, `createPolygon(_:_:)` |
| `GEOSGeom_createCollection_r`, `GEOSGeom_createEmptyCollection_r` | `createMultiPoint`, `createMultiLineString`, `createMultiPolygon`, `createGeometryCollection` |
| `GEOSGeomTypeId_r`, `GEOSisEmpty_r`, `GEOSGetNumGeometries_r`, `GEOSGetGeometryN_r` | the geometry classes, `isEmpty()`, `getNumGeometries()`, `getGeometryN(_:)` |
| `GEOSGeom_getCoordSeq_r`, `GEOSCoordSeq_getSize_r`, `GEOSCoordSeq_copyToBuffer_r`, `GEOSGeomGetX_r`, `GEOSGeomGetY_r` | `LineString.points`, `Point.getCoordinate()` |
| `GEOSGetExteriorRing_r`, `GEOSGetNumInteriorRings_r`, `GEOSGetInteriorRingN_r` | `Polygon.getExteriorRing()`, `getNumInteriorRing()`, `getInteriorRingN(_:)` |
| `GEOSGeom_getXMin_r` and the other three | `getEnvelopeInternal()` |
| `GEOSisValid_r` | `isValid()` (`IsValidOp`), phase 6 |
| `GEOSArea_r`, `GEOSLength_r` | `getArea()`, `getLength()` |
| `GEOSGetCentroid_r`, `GEOSPointOnSurface_r` | `getCentroid()`, `getInteriorPoint()` |
| `GEOSWKTWriter_create_r`, `_setRoundingPrecision_r`, `_write_r`, `_destroy_r` | `WKTWriter(roundingPrecision: 3).write(_:)` |
| `GEOSBufferWithStyle_r` | `buffer(_:quadSegs:endCapStyle:joinStyle:mitreLimit:)` |
| `GEOSUnion_r`, `GEOSIntersection_r`, `GEOSDifference_r`, `GEOSUnaryUnion_r` | `union(_:)`, `intersection(_:)`, `difference(_:)`, `union()` |
| `GEOSTopologyPreserveSimplify_r` | `topologyPreserveSimplify(_:)`, phase 6 |
| `GEOSMakeValid_r` | `makeValid()`, phase 6 |
| `GEOSGeom_setPrecision_r` (flags 0) | `setPrecision(_:)`, phase 6 |
| `GEOSConvexHull_r`, `GEOSEnvelope_r`, `GEOSBoundary_r` | `convexHull()`, `getEnvelope()`, `getBoundary()` |
| `GEOSMinimumRotatedRectangle_r` | `MinimumAreaRectangle.getMinimumRectangle(_:)` |
| `GEOSOffsetCurve_r` | `offsetCurve(_:quadSegs:joinStyle:mitreLimit:)` |
| `GEOSInterpolate_r`, `GEOSInterpolateNormalized_r` | `interpolate(_:normalized:)`, phase 7 |
| `GEOSProject_r` | `project(_:)`, phase 7 |
| `GEOSDistance_r`, `GEOSNearestPoints_r` | `distance(_:)`, `DistanceOp.nearestPoints(_:_:)` |
| `GEOSIntersects_r`, `GEOSContains_r`, `GEOSWithin_r` | `intersects(_:)`, `contains(_:)`, `within(_:)` |
| `GEOSConstrainedDelaunayTriangulation_r` | `ConstrainedDelaunayTriangulator.triangulate(_:)`, phase 7 |
| `GEOSPolygonize_r` | `Geometry.polygonize(_:)`, phase 7 |
| `GEOSLineMerge_r` | `lineMerge()`, phase 7 |
| `GEOSPrepare_r`, `GEOSPreparedContains_r`, `GEOSPreparedIntersects_r` | `PreparedGeometryFactory.prepare(_:)`, `contains(_:)`, `intersects(_:)` |
| `GEOSSTRtree_create_r`, `_insert_r`, `_query_r`, `_nearest_r` | `STRtree(nodeCapacity: 10)`, `insert`, `query`, `nearestNeighbour` |

## Left

- The port's speed: after the second pass, a whole tile's recorded calls take 1.48 times GEOS's time (`Docs/PortingParity.md`, "Speed after the second optimization pass"), within the goal's 1.5 but with little margin; the unary union (1.56) is most of it. Reference counting and allocation in the overlay are what is left.
- Phase 8 is done (above); one random non-finite input differs, open (`Docs/PortingParity.md`, phase 8). Phases 9 to 12 follow: GEOS leaves the package only in phase 12.

## Decisions

- **Ties as GEOS breaks them.** GEOS is C++ and sorts and queues with libc++ where JTS uses Java's stable sort and `PriorityQueue`; for elements that compare equal the outcome is the algorithm's own. The STR tree runs libc++'s `std::sort` and heap (`CxxAlgorithms`, translated from the macOS SDK's headers, Apache-2.0 with LLVM exceptions, noted in `Sources/Topology/LICENSE`), which gives GEOS's nearest item on every tie tried. `TieOrder.jts` keeps JTS's order.
- **`MCIndexNoder` indexes its chains in the STR tree** (JTS 1.20 uses a Hilbert R-tree there). The pairs found are the same, and the order they are processed in follows the STR tree.
- **`ScaledNoder` makes the rescaled strings again** instead of changing coordinates in place (they are values here); the result is the same.
- **The port follows GEOS where GEOS 3.13 differs from JTS 1.20**, since parity with GEOS is the bar: each difference is found by a parity test, confirmed on GEOS's output, and listed in `Docs/PortingParity.md` ("Where GEOS 3.13 differs from JTS 1.20"). The JTS XML suites then pass on the port exactly where they pass on GEOS. From phase 4 on, GEOS's sources may be read to understand a difference (the main session's decision), never translated: the port stays JTS's code, changed where GEOS behaves otherwise, each change documented.
- **Two dimensions.** `Coordinate` is x and y: the package's geometry is planar and GEOS is called with XY. The readers drop Z and M.
- **Geometries are classes**, as JTS's (`normalize` changes one in place), their coordinates contiguous arrays of a value type. Envelopes, segments, DD, intersectors and locators are values.
- **Names are JTS's** (`getEnvelopeInternal`, `getNumPoints`), so the port reads side by side with JTS.
- **Programming errors trap** (`precondition`), as JTS's `IllegalArgumentException` and assertions do: a ring that is not closed, the boundary of a collection. The readers check their input and throw instead.
- **GEOS here is built with fused multiply-add.** The `GEOSwift/geos` package compiles GEOS with SwiftPM's default flags, and Apple clang's default `-ffp-contract=on` fuses `a * b + c` inside one expression into one `fmadd` on arm64, in debug and release alike (checked on a two-line function: `fmadd` at `-O0` and `-O2`). JTS on the JVM never fuses. So the GEOS this package runs today does not compute JTS's arithmetic exactly wherever an expression multiplies and adds. The port follows JTS's operations and adds the fusion clang makes (`Fused.swift`, `addingProduct`): the rule is clang's, the left product of a sum or difference first. Every such place is checked against GEOS, and the tests fail without it.
- The oracle and the runner read the JTS sources from `.build/ports/jts` of the package or of a folder above it (a worktree), or `JTS_ROOT`. The XML suites are not copied into the package: 16 MB, and a test target cannot hold non-Swift files without declaring them in `Package.swift`.
- The recordings are outside git. The tests that read them run only when they are there (`.enabled(if: Recording.available)`), the JTS XML tests always. The long replays (overlays and on: tens of minutes in a debug build) run only with `TOPOLOGY_LONG_REPLAY=1` as well (`Recording.longReplay`).
- **Timing.** `swift test -c release` does not work in this package: the release test bundle links the app's executable target and runs its SwiftUI `main`, which waits for events (and a test build with `-O` in its own scratch path hung the same way). The optimized times are taken by a throwaway executable (in the session's scratchpad, not in the package) compiled with `swiftc -O` against the objects of `swift build -c release` (the port, and GEOS at the release flags), which replays the recorded calls and times each side's call alone. The debug replays print their own (slower) times.
- **`MCIndexSnapRounder` is not ported.** Phase 3 deferred it to the buffer, but GEOS 3.13's buffer snaps at a fixed precision with `SnapRoundingNoder`, as JTS 1.20 does (`MCIndexSnapRounder` appears in GEOS only in code disabled by `#if` and in `GeometryNoder` at a fixed precision, which nothing the package calls reaches). Nothing would test it against GEOS.
- `GEOSEngine` maps JTS's old overlay names (`intersection`, `union`) to GEOS's overlay (OverlayNG), the `SR` overlays to the `Prec` functions with grid `1 / scale`, and a fixed precision model to coordinates rounded on reading (as JTS's `WKTReader`) and the `Prec` overlays. GEOS has no oriented Hausdorff distance, so the buffer matcher uses the symmetric one, the stricter check.
- **Make valid is written from its algorithm** (phase 6). GEOS 3.13's default `GEOSMakeValid` ("linework") is GEOS's own `MakeValid` and `BuildArea` (from rttopo and PostGIS, LGPL); JTS 1.20 has nothing to port for it. The port's `MakeValid` and `BuildArea` implement the algorithm as GEOS documents and runs it, on the port's JTS operations, in GEOS's order of operations; GEOS's code was read to understand it and not translated. Taken on the user's behalf as the choice that leaves no function unported; the alternative is to keep `GEOSMakeValid` out of the port (the structural method, JTS's `GeometryFixer`, gives other results). For the user to confirm.
- **GEOS's exception on non-finite points is emulated** (`NonFinite`): the orientation test raises a per-thread flag instead of throwing, and the places where GEOS catches (the robust overlay's stages) or reports (the entry points of the overlays and of the phase 6 and 7 operations) turn it into GEOS's error. Since phase 8 every operation of `Geometry` runs in a scope (the C API's catch), so the predicates, the buffer, the distance and the rest fail where GEOS does too; where the port could not go on past GEOS's throw (an index past a ring, a ring not closed), the computation stops early, its result discarded (`NonFinite.watch`, `raise`).
- **GEOS's ordered containers on NaN keys** follow libc++'s red-black tree (`CxxTree`, translated from the SDK's `__tree`, Apache-2.0 with LLVM exceptions as `CxxAlgorithms`) where a NaN key was seen to matter (the point overlay's maps, make valid's unique points). The other ordered structures stay sorted arrays, equal for finite keys.
- **Where GEOS crashes, its input is not compared**: the triangulator on invalid polygons (a segmentation fault on a hole crossing its shell) is compared on valid input only, as `GEOSNode` on collections with empty members in phase 3. Where GEOS's behaviour is undefined but ends in a definite outcome (a ring collapsed to one point in the triangulator), the port reproduces the outcome.
- **The simplifier's segment index** is a uniform grid, not JTS's quadtree: every query's use is an existence test over the same candidates, so the answers are the same (checked on every recorded call), and the quadtree's order does not matter.
