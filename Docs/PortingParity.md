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
| MC index noder in an iterated noder, duplicates dropped (`GEOSNode`) | 4,861 | 4,861 |
| the two inputs that differed in the sign of a zero in phase 3 | 2 | 2 |

The tree breaks ties as GEOS does only with libc++'s algorithms: JTS's stable sort and Java's `PriorityQueue` give the same nearest item on 4,609 of 5,495 searches (all the others are ties: equal envelope centres, equal distances), libc++'s `std::sort` and heap (`CxxAlgorithms`) on all 5,495. Queries are the same either way.

`GEOSNode` is not compared on a collection holding an empty geometry: GEOS 3.13 crashes on it (a segmentation fault, `GEOMETRYCOLLECTION (LINESTRING (0 0, 1 1), LINESTRING EMPTY)`). 139 of the 5,000 random inputs.

The difference phase 3 left open, a zero-length segment between `0.0` and `-0.0` (`LINESTRING (1 0, 0 0, -0 0, -1 -1)`: the port gave `(1 0, 0 0), (0 0, -0 0), (0 0, -1 -1)`, GEOS `(1 0, 0 0), (-0 0, -0 0), (-0 0, -1 -1)`), is gone in phase 4: the port now meets the pairs of chains in the order GEOS 3.13 does (its STR tree's packed leaf order, `STRtree.queryPairs`) and keeps the nodes of a string as GEOS does (an array sorted with libc++'s `std::sort` when read, the first of equal nodes kept). Found by reading GEOS's noding sources for the order, as the main session allowed. The code is JTS's with these two changes. No result differs in the sign of a zero any more, and the test fails on any difference.

Snap rounding is not exposed alone by GEOS's C API (its overlays at a precision and `GEOSGeom_setPrecision` of polygons use it): it is compared with GEOS through those in phases 4 and 6. Here it passes JTS's own cases (`SnapRoundingNoderTest`, 18 of 18, each result checked fully noded), and the KD-tree JTS's `KdTreeTest`.

### Phase 4: overlay and union against GEOS

Results in GEOS's normal form, compared bit for bit; where GEOS fails (returns NULL), the port must throw. The results are compared as they come as well (not normalized): every one is GEOS's, the order of parts, rings and points included. The random pairs (`OverlayParityTests`) are a random geometry and one that meets it: another random geometry moved onto it, the same shifted by a share of its size, by 1e-10 of it, along an axis by a quarter of it (edges shared exactly on grids), turned half round about its centre, or itself. Many are invalid (rings of the random generator cross now and then, collections hold overlapping parts), which is where GEOS fails.

| Function | Compared | Equal | GEOS and the port failing alike | Results equal as they come |
|---|---:|---:|---:|---:|
| intersection (`GEOSIntersection`) | 4,000 | 4,000 | 441 | 3,559 of 3,559 |
| union (`GEOSUnion`) | 4,000 | 4,000 | 522 | 3,478 of 3,478 |
| difference (`GEOSDifference`) | 4,000 | 4,000 | 512 | 3,488 of 3,488 |
| symmetric difference (`GEOSSymDifference`) | 4,000 | 4,000 | 553 | 3,447 of 3,447 |
| unary union (`GEOSUnaryUnion`), 2 to 7 parts | 2,000 | 2,000 | 491 | 1,509 of 1,509 |
| intersection at a fixed precision (`GEOSIntersectionPrec`) | 1,677 | 1,677, 3 of them equal but for the sign of zeros | 262 | 1,412 of 1,415 |
| union at a fixed precision (`GEOSUnionPrec`) | 1,696 | 1,696, 10 equal but for the sign of zeros | 324 | 1,362 of 1,372 |
| difference at a fixed precision (`GEOSDifferencePrec`) | 1,707 | 1,707, 3 equal but for the sign of zeros | 307 | 1,397 of 1,400 |
| symmetric difference at a fixed precision (`GEOSSymDifferencePrec`) | 1,685 | 1,685, 6 equal but for the sign of zeros | 336 | 1,343 of 1,349 |

The fixed precision grids are a seventh, a hundredth and a ten-thousandth of the geometry's size, 1 and 0.001.

**The sign of zeros at a fixed precision is GEOS's own randomness.** GEOS 3.13's snap rounding adds a string's vertices to its hot pixel index in a random order (`std::shuffle` seeded by `std::random_device`; JTS shuffles with `Random(13)`, as the port does). Where two vertices of one pixel round to `0.0` and `-0.0`, the pixel keeps the first one added, so GEOS's results change sign from run to run: on each of the 22 inputs above GEOS itself gave a different result within ten more runs (on 7 checked by hand, 2 to 8 distinct results in 20 runs). As the main session decided, such results are compared by value (`0.0 == -0.0`) and counted apart; every other coordinate is equal bit for bit.

Every recorded call (`OverlayReplayTests`), GEOS's normal form and as they come:

| Function | Recorded calls | Equal |
|---|---:|---:|
| intersection | 14,804 | 14,804 |
| difference | 2,462 | 2,462 |
| union | 6 | 6 |
| unaryUnion | 41,654 (41,629 given to GEOS: the wrapper answers 25 of only empty parts itself) | 41,629 |

Time of the recorded calls, the operation alone, in an optimized build (a throwaway executable in the scratchpad, `swiftc -O` against the release build's `Topology` objects and GEOS's library from the same build; `swift test -c release` cannot run here, see Docs/PortingTopologyProgress.md, "Timing"):

| Function | Calls | Port | GEOS | Port / GEOS |
|---|---:|---:|---:|---:|
| intersection | 14,804 | 33.7 s | 7.0 s | 4.8 |
| difference | 2,462 | 2.2 s | 0.56 s | 3.9 |
| union | 6 | 0.41 s | 0.12 s | 3.4 |
| unaryUnion | 41,629 | 47.4 s | 12.9 s | 3.7 |

The port is a faithful translation not yet optimized ("port, then optimise"): its speed is the next work on it, with these parity tests green before and after.


The JTS XML suites, the overlay operations: the port passes exactly the tests GEOS passes (`JTSXMLTopologyTests.portPassesWhatGEOSPasses`), and its results are GEOS's bit for bit on every test of an operation it has (`portResultsAreGEOSs`: 3,130 of 3,130, phase 2's included).

| Operation | Tests | Passed (as GEOS) |
|---|---:|---:|
| `intersection` | 219 | 215 |
| `intersectionNG` | 63 | 63 |
| `intersectionSR` | 20 | 20 |
| `union` | 115 | 82 |
| `unionNG` | 63 | 51 |
| `unionSR` | 20 | 20 |
| `difference` | 131 | 131 |
| `differenceNG` | 109 | 109 |
| `differenceSR` | 40 | 40 |
| `symdifference` | 99 | 99 |
| `symdifferenceNG` | 63 | 54 |
| `symdifferenceSR` | 20 | 20 |
| `unionArea` | 8 | 8 |
| `unionLength` | 11 | 10 |
| `overlayAreaTest` | 2,039 | 2,039 |

The JTS unit cases of snap rounding (`SnapRoundingNoderTests`) are now checked against JTS's expected lines made precise by the port's model, which rounds as GEOS's does (below): in `testMCIndexNoderTolerance` the scale 0.0016339869 is 1 / 612.0000105, just outside GEOS's integer tolerance, so GEOS rounds on that grid size and JTS by the scale, a difference in the last digits.

#### Where GEOS 3.13 differs from JTS 1.20 in phase 4, and the port follows GEOS

Each was found by a parity test, then understood from GEOS's sources (read, never translated), and confirmed on GEOS's output.

- **Noding order** (phase 3's open difference): pairs of chains by the STR tree's packed leaf order (`STRtree.queryPairs`), a segment string's nodes kept in an array sorted with libc++'s `std::sort` when read.
- **The nodes of the overlay graph** are iterated in the order of GEOS's libc++ `unordered_map` keyed by its coordinate hash (`CxxUnorderedMap`; JTS: a Java `HashMap`). Where a nearly collinear edge gets conflicting line locations at its two ends, the node labelled last decides; with the nodes in insertion order, 1 of 2,000 random unary unions differed by a vertex.
- **The area check of an overlay result** (`isResultAreaConsistent`): GEOS checks results of lines and points too (their area is 0, so a union of areas collapsed to lines fails and the robust overlay goes on to snapping), and checks a difference as at least the difference of the areas less a tenth (JTS: less a tenth of the first area). 12 of 2,000 random unary unions differed before.
- **The precision model**: a scale or grid size within 1e-5 of an integer is made that integer, the grid size is kept beside the scale, a value is rounded on the grid size when it is above 1 (else by the scale), and with GEOS's rounding (`java_math_round` of `floor` and `ceil`: a value in (-0.5, 0] rounds to `-0.0`, where Java's `Math.round` gives `0.0`). About 10% of the random fixed precision overlays differed before, in last digits and zero signs. The same rounding is used by the hot pixels and the scaled noder.
- **The safe scale of snap rounding** with an empty input: GEOS's null envelope has NaN ordinates (JTS's 0 and -1), so an empty input does not change the scale.
- **Duplicate edges** are merged by their key's value (GEOS: an ordered map, JTS: a hash map, where `-0.0` and `0.0` hash apart).
- **Point results** come in coordinate order: GEOS keeps the points of a point overlay in an ordered map and sorts the points of a mixed overlay (JTS: hash map and hash set orders). The union of points with a polygonal input takes every non-empty member of the unioned input, lines too (JTS fails on a collection there).
- **The overlay methods** (`GeometryOverlay`): no shortcuts for empty inputs (OverlayNG's empty results apply), but a union or symmetric difference of inputs with disjoint envelopes (an empty one included) is their members put together; a collection of mixed dimensions is overlaid dimension by dimension (`MixedDimensionOverlay`, JTS refuses it).
- **The unary union** (`UnaryUnionOp`, `CascadedPolygonUnion`, `PointGeometryUnion`): every point, line and polygon extracted, empty ones included; lines and points cleaned by a union with an empty collection (JTS: an empty point, which sends points through the point overlay instead of the mixed one); polygons in an STR tree of capacity 10, unioned in its packed order by halving the list (JTS: capacity 4, node by node); each partial result restricted to its polygons; an empty collection when nothing is left; empty points skipped where points are added to a union.
- **GEOS's first robust stage catches every error** (any `std::runtime_error`: topology failures, failed assertions, illegal arguments), its later stages only topology failures, as JTS does with `RuntimeException`: the port throws JTS's exception kinds as errors and catches the same ones.

### Phase 4: predicates, distance and nearest points against GEOS

GEOS 3.13 evaluates every predicate with RelateNG (`USE_RELATENG` in its `Geometry.cpp`), after an envelope test for `intersects` and `touches` and the rectangle's fast path for `intersects`; its prepared polygons keep JTS's fast paths for `intersects`, `contains`, `covers` and `containsProperly`, and the other prepared predicates are a prepared RelateNG. The port does the same. Every answer is compared; where GEOS fails (returns 2), the port must throw.

| Function | Compared | Equal |
|---|---:|---:|
| intersects, contains, within, covers, coveredBy, touches, crosses, overlaps, disjoint, equalsTopo (each `GEOS<name>`), each pair both ways | 8,000 each | 8,000 each |
| the intersection matrix (`GEOSRelate`), as text | 4,000 (48 failing alike: a point against an empty collection, `Unknown target dimension: -1`) | 4,000 |
| prepared contains, intersects, covers, within (`GEOSPrepared<name>`), a new prepared geometry per pair | 4,000 each | 4,000 each |
| distance (`GEOSDistance`), pairs meeting and apart | 8,000 | 8,000 |
| nearest points (`GEOSNearestPoints`) | 8,000 | 8,000 |

The pairs are those of the overlays, a quarter of them a point near the geometry or one of its vertices; half of the distance pairs are moved apart by up to twice their size.

Every recorded call:

| Function | Recorded calls | Equal | Port, optimized | GEOS | Port / GEOS |
|---|---:|---:|---:|---:|---:|
| intersects | 1,428,861 | 1,428,861 | 1.46 s | 0.77 s | 1.9 |
| contains | 16,649 | 16,649 | 63 ms | 27 ms | 2.4 |
| Prepared.contains (14 prepared geometries) | 175,334 | 175,334 | 283 ms | 56 ms | 5.0 |
| distance | 100,452 | 100,452 | 92 ms | 29 ms | 3.1 |
| nearestPoints | 34 | 34 | 2 ms | 1 ms | 1.6 |

`within` and `Prepared.intersects` are never called by the pipeline. The STR tree's recorded nearest searches (279) and its random ones (5,495) now find the nearest item with the port's own distance on the port's side, all GEOS's.

The JTS XML suites, the predicates and distance: the port passes exactly the tests GEOS passes, and all 9,195 results of the operations it has are GEOS's.

| Operation | Tests | Passed (as GEOS) |
|---|---:|---:|
| `intersects` | 592 | 592 |
| `contains` | 583 | 582 |
| `within` | 526 | 526 |
| `covers` | 561 | 561 |
| `coveredBy` | 535 | 535 |
| `touches` | 525 | 525 |
| `crosses` | 525 | 525 |
| `overlaps` | 525 | 525 |
| `disjoint` | 525 | 525 |
| `equalsTopo` | 525 | 524 |
| `relate` (patterns) | 589 | 589 |
| `distance` | 32 | 32 |
| `isWithinDistance` | 22 | 22 |

#### Where GEOS 3.13 differs from JTS 1.20 in the predicates and distance

- **The dispatch**: RelateNG for every predicate (JTS 1.20's `Geometry` methods run its old relate by default).
- **RelateNG on two empty inputs**: evaluated as any others (JTS returns the predicate's final value at once). Its `equalsTopo` takes two empty geometries as equal whatever their dimensions, and needs no interaction (52 of 8,000 random `equalsTopo` differed before).
- **Sorts** of node sections by libc++'s `std::sort` (JTS: a stable sort), the nodes of the topology evaluated in coordinate order (an ordered map), the pairs of chains of one index by `queryPairs` (JTS: a Hilbert R-tree queried chain by chain).
- **The rectangle's intersects**: its last test meets each segment of the rectangle's ring with each segment of the other's lines (JTS: each segment with the rectangle's diagonals). The answers agree.
- **Prepared polygons**: the point locator is the simple one the first time and the indexed one afterwards (JTS: always indexed); on invalid polygons they locate some points differently (14 of 16,000 random prepared predicates differed before). `contains` and `covers` decide first on the outermost location of the test components (JTS: whether all are in), as GEOS's `OutermostLocationFilter` has it.
- **Distance**: the second geometry's polygons are tried first for containment (JTS: the first's), segment envelopes are compared by their squared distance with the minimum's square, envelope distance is the root of GEOS's `distanceSquared` (JTS: `hypot` of the gaps), and `isWithinDistance` of an empty geometry is false. These were read in GEOS's sources; the random and recorded inputs give the same results with JTS's forms, so they are not observed differences, but they are GEOS's arithmetic.

## Phase 5: buffer and offset curve against GEOS

The buffer is compared with `GEOSBufferWithStyle`, the offset curve with `GEOSOffsetCurve`: results in GEOS's normal form bit for bit, and as they come; where GEOS fails, the port must throw. The random inputs are those of the overlays (polygons with holes, lines with repeated points and closed lines, points, multi-geometries, collections, empties, some on a grid), with distances of 0.001, 0.05, 0.3, 1 and 3 times their size (times 0.5 to 1.5), a third of them negative and one in twenty zero, segments a quadrant 1, 2, 3, 4, 8, 16, 0 and -1, every cap and join style, mitre limits 0.5 to 10.

| Function | Compared | Equal (normalized) | Equal as they come |
|---|---:|---:|---:|
| buffer, random | 8,000 | 8,000 | 8,000 |
| offset curve, random (60% lines) | 4,000 | 4,000 | 4,000 |
| buffer, every recorded call | 112,586 | 112,586 | 112,586 |
| offset curve, every recorded call | 273 | 273 | 273 |

No tolerance was used: the arcs come out bit for bit, as GEOS and the port take `sin` and `cos` from the same system library.

| Function | Recorded calls | Port, optimized | GEOS | Port / GEOS |
|---|---:|---:|---:|---:|
| buffer | 112,586 | 10.9 s | 2.6 s | 4.1 |
| offsetCurve | 273 | 3 ms | 1 ms | 2.2 |

The JTS XML suites: `buffer` 151 tests, all passed as on GEOS; `bufferMitredJoin` 5, 2 passed, the 3 GEOS does not pass not passed either (`GEOSBaseline`). Every result of the operations the port has, 9,351 now, is GEOS's. The buffer matcher of the port's engine measures the symmetric difference with the port and the boundaries' Hausdorff distance with GEOS (the port has no Hausdorff distance yet).

#### Where GEOS 3.13 differs from JTS 1.20 in the buffer and the offset curve

- **Retries**: after a topology failure at the input's precision, the buffer is retried snap-rounded at 12 significant digits down to 6 (JTS: down to 0). Only topology failures lead to a retry, the first try's too (JTS's first try catches any runtime error).
- **Offset segments**: their length is `sqrt(dx * dx + dy * dy)` (JTS: `hypot`); the input simplification tolerance is the distance divided by 100 (JTS: times 0.01, another double); a point of an outside turn whose offsets nearly meet is the first offset's end, within 1e-3 of the distance (JTS: the longer segment's, within 0.05); a repeated next point leaves the generator's segments as they are (JTS moves them on); the limited mitre join is built from the bisector's outward direction; the curve's points are taken with the ring closed, so the raw offset curve of a line ends where it starts.
- **Input simplification** (`BufferInputLineSimplifier`): the scan starts at the second vertex for rings too, the sampled test measures the middle vertex against the segments from the first to each sample (JTS: each sample against the first and middle), the kept points have no repeats.
- **Curves of a polygon**: a shell is tested for complete erosion before its repeated points go, a shell with no valid point fails, a ring buffered by zero is itself at any size, the test for an inverted ring curve takes every vertex of the curve.
- **Noding and the graph**: the noding of a zero buffer is not validated, repeated points are removed from each noded edge, the parts of the graph are sorted by `std::sort` (equal rightmost x in its order), an edge end of a direction already at a node is left out (JTS's `TreeMap` keeps the later), a part with no forward edge fails, the depth locator skips parts and edges left of the point.
- **Polygons**: a free hole is placed by an indexed point-in-area locator per shell (JTS: the point against the ring, the same answer), two shells among minimal rings fail as topology (JTS asserts).
- **Offset curve**: a buffer segment matches a raw segment when both its ends are within the match distance of it (JTS tests the shorter segment's ends against the longer), sections are sorted by `std::sort`, only polygons count for the buffer's largest.
- **The union by buffer is out of reach for floating inputs.** GEOS's `ClassicUnionStrategy` falls back to the buffer by zero of two areas when their overlay throws a `TopologyException`, but robust OverlayNG keeps its first failure in a `std::runtime_error` (sliced) and throws that when every strategy fails, which the fallback does not catch. The port throws that failure as a `RuntimeError` likewise. Found when the buffer arrived: with the fallback reaching the buffer, 446 of 2,000 random unary unions gave a result where GEOS fails.

## Speed after the first optimization pass

Optimized, on every recorded call (the port's objects of `swift build -c release`, GEOS at its release flags; each side's call alone). The pass changed no result: the full suite with the long replays was green before and after.

| Function | Recorded calls | Port | GEOS | Port / GEOS (before the pass) |
|---|---:|---:|---:|---:|
| intersection | 14,804 | 15.9 s | 7.6 s | 2.1 (about 4) |
| difference | 2,462 | 1.6 s | 0.63 s | 2.6 (3.5) |
| union | 6 | 286 ms | 135 ms | 2.1 (2.9) |
| unaryUnion | 41,629 | 38.8 s | 13.2 s | 2.9 (3.5) |
| intersects | 1,428,861 | 1.5 s | 0.79 s | 1.9 (1.9) |
| contains | 16,649 | 63 ms | 27 ms | 2.4 (2.4) |
| Prepared.contains | 175,334 | 229 ms | 77 ms | 3.0 (5.0) |
| distance | 100,452 | 124 ms | 45 ms | 2.8 (3.1) |
| buffer | 112,586 | 5.4 s | 2.4 s | 2.3 (4.1) |
| offsetCurve | 273 | 3 ms | 1 ms | 2.2 (2.2) |

What changed: the stable merge sort behind JTS's sorts (`javaSorted`) merges in one scratch buffer instead of allocating arrays at every level (the same order, the same comparisons); the STR tree is queried from one flat array of its nodes; the line intersector keeps its points inline instead of in arrays; the segment envelope test uses GEOS's `std::min` and `std::max`; the intersectors held by noders skip the dynamic exclusivity checks. The rest is reference counting and allocation, for a later pass. Run to run the times vary by about 10%.

## Phases 6 and 7: validity, make valid, precision, simplify, triangulation, polygonize, line merge, linear referencing against GEOS

Every comparison is exact: geometries in GEOS's normal form bit for bit and as they come (not normalized), numbers by their bits, the validity with its reason and its location bit for bit (`GEOSisValidDetail`); where GEOS fails, the port must throw. The random inputs are phase 2's (`RandomGeometries`) and new often invalid ones (`InvalidGeometries`: rings of shuffled grid points, bow-ties and figure eights, spikes and gores, holes inside, crossing, touching or outside their shell, nested and repeated holes, holes touching each other and the shell in a cycle, a hole touching its shell twice, inverted rings, overlapping, touching and nested parts of multipolygons, rings and lines of too few distinct points, NaN and infinite ordinates, collections of these). The linework of the polygonizer and the line merger is pieces of random walks on grids (shared ends, reversed pieces, loops, repeats), the noded boundaries of random geometries (GEOS's unary union of them), polygons and raw crossing lines.

| Function (GEOS) | Inputs | Compared | Equal | Failing alike | Equal as they come |
|---|---|---:|---:|---:|---:|
| `isValid` (`GEOSisValidDetail`: answer, reason, location) | random | 6,000 (811 invalid) | 6,000 | 0 | |
| the same | often invalid | 12,000 (9,477 invalid) | 12,000 | 0 | |
| `makeValid` (`GEOSMakeValid`) | random | 4,000 | 4,000 | 0 | 4,000 |
| the same | often invalid | 8,000 | 8,000 | 601 | 7,399 of 7,399 |
| `setPrecision` (`GEOSGeom_setPrecision`, flags 0) | random, grids of a seventh, a hundredth and a ten-thousandth of the size, 1, 0.01, 0.001 | 6,000 | 6,000, 5 of them equal but for the sign of zeros | | |
| the same | often invalid | 4,000 | 4,000 | | |
| `simplify` (`GEOSTopologyPreserveSimplify`), tolerances 0 and 0.001 to 2 times the size | random | 6,000 | 6,000 | 0 | 6,000 |
| the same | linework | 3,000 | 3,000 | 0 | 3,000 |
| the same | often invalid | 3,000 | 3,000 | 131 | 2,869 of 2,869 |
| `polygonize` (`GEOSPolygonize`, a list of geometries) | linework (1,955 with polygons) | 4,000 | 4,000 | 0 | 4,000 |
| `lineMerge` (`GEOSLineMerge`) | linework (1,780 with lines merged) | 4,000 | 4,000 | 0 | 4,000 |
| `constrainedDelaunay` (`GEOSConstrainedDelaunayTriangulation`) | random polygons, multipolygons, grid polygons with holes (cocircular, collinear vertices), valid ones | 3,105 | 3,105 | 0 | 3,105 |
| the same | often invalid, the valid ones | 646 | 646 | 0 | 646 |
| `interpolate` (`GEOSInterpolate`, `GEOSInterpolateNormalized`), inside, past the ends, negative | random lines and multi-lines | 6,000 | 6,000 | | 6,000 |
| `project` (`GEOSProject`), a vertex or a point near | the same | 6,000 | 6,000 | | |

The five set-precision results equal but for the sign of zeros are the snap rounding of phase 4 (GEOS shuffles its hot pixels at random): GEOS itself gave another result within ten more runs on each of the five, and they are counted apart as the main session decided in phase 4.

The triangulation is compared only on valid polygonal input (`GEOSisValid`): GEOS's triangulator requires it, and crashes on some invalid polygons (a segmentation fault on `POLYGON ((0 0, 6 0, 6 6, 0 6, 0 0), (-1 5, 1 5, 1 4, -1 4, -1 5))`, a hole crossing its shell), as `GEOSNode` did in phase 3. 895 random and 2,354 often invalid inputs were not given to it.

Every recorded call (`Recording/ValidityReplayTests`, `LinesReplayTests`, `ShapeReplayTests`, `RepairReplayTests` long):

| Function | Recorded calls | Equal (normalized and as they come) |
|---|---:|---:|
| isValid (answer, reason, location) | 47,724 (25 invalid) | 47,724 |
| makeValid | 32,248 | 32,248 |
| setPrecision | 16,124 | 16,124 |
| simplify | 6,276 | 6,276 |
| polygonize | 14,663 | 14,663 |
| lineMerge | 14,668 | 14,668 |
| constrainedDelaunay | 9,495 | 9,495 |
| interpolate | 3,062 | 3,062 |
| project | 311 | 311 |

The JTS XML suites: `isValid` 922 tests, `polygonize` 6 and `simplifyTP` 18, all passed as on GEOS, and every result of the operations the port has (10,297 now) is GEOS's.

### Where GEOS 3.13 differs from JTS 1.20 in phases 6 and 7, and the port follows GEOS

Some were found by a parity test (the pairs of the STR tree, the validity message, the simplifier's non-finite segments, the non-finite coordinates, the triangulator's collapsed rings), then understood from GEOS's sources (read, never translated); the others were read in GEOS's sources while porting (orders of containers and sorts JTS takes from hash maps or stable sorts). All are confirmed by the parity tests, which pass with them.

- **The STR tree's pairs** (`queryPairs`, used by `MCIndexNoder`): when the visitor stops, GEOS stops the search of the current item's pairs only and goes on with the next item, so a noder whose intersector is done still sees the first pair of each later item (the port stopped everything). With the old semantics 472 of 6,000 random validity checks and 2,480 of 12,000 often invalid ones reported another invalid location; with GEOS's all are equal, and every earlier parity suite is unchanged.
- **Validity**: GEOS's message for too few points ("Too few points in geometry component"); the touches of a ring visited in the order of the rings' indices (GEOS's ordered map; JTS a `HashMap`).
- **The planar graph**: edges and directed edges in insertion order (GEOS's vectors; JTS's `HashSet`s, whose order is random from run to run), the edges around a node sorted with libc++'s `std::sort`.
- **The polygonizer**: rings always checked for validity, shells not sorted by envelope (JTS 1.20 sorts them), invalid rings sorted with `std::sort` by the area of their envelope's geometry, dangles listed once, a hole's shell found as GEOS finds it (a shell of the same envelope skipped, the envelope contained, the hole's first point not on the shell not outside it), the disjoint shells by GEOS's recursive update.
- **The line merger**: GEOS's directed mode exists (unused here); the result is built with `buildGeometry`.
- **Set precision**: a collection reduced to one geometry is made a multi-geometry again (GEOS's `createMulti`), changing the precision model copies the result without empty members and empty holes (GEOS's `GeometryEditor`), the snap-rounded union's topology failure is not turned into an illegal argument, a collapsed line is extended by repeating its last point.
- **The transformer** (`GeometryTransformer`): GEOS's rules (empty members pruned, collection type kept, a polygon whose shell is no longer a ring becomes the geometry of its parts).
- **The simplifier**: lines simplified in the order of the components (JTS: a `HashMap`'s); a kept segment enters the result as a copy, so taking out a ring's end point removes only the very segments from the indexes (JTS removes equal ones); a section with no inner points keeps its segments; a non-finite segment fails at insertion into the index, as GEOS's quadtree does.
- **The triangulator**: the in-circle test is GEOS's (`isInCircleNormalized`: the two sums of the determinant's terms compared, in `long double`, which is `double` on arm64, with clang's fused products), not JTS's; the rings are always replaced by their noded coordinates (repeated points removed); holes sorted with `std::sort`; the search for a joinable vertex stops at the first vertex; an empty polygon gives no triangles.
- **Linear referencing**: a component that is not a line fails only when read, the end location of a geometry with no components is its start.
- **Non-finite coordinates**: GEOS's orientation test throws on a NaN or infinite point (`CGAlgorithmsDD::orientationIndex`, `signOfDet2x2`), JTS computes on; GEOS's envelopes are null when `maxX` is NaN and do not intersect anything with a NaN ordinate; GEOS's ordered sets and maps (red-black trees) take a NaN coordinate as equivalent to any. The port follows all three (`NonFinite`, `Envelope`, `CxxTree`). Before this, 245 of the 8,000 often invalid make-valid inputs differed (GEOS failing, the port giving a result), then 57 (the port failing where GEOS's envelopes skip the NaN segment), then 19 and 2 (collapsed NaN points kept); now none.
- **Undefined behaviour of GEOS, reproduced by its outcome**: the triangulator on a ring collapsed to one point (all its points repeated) reads past the ring; GEOS gives no triangles for such a shell and fails ("Unable to find shell join index") for such a hole, and so does the port.

### Make valid: written from the algorithm, not translated

GEOS 3.13's default `GEOSMakeValid` (the "linework" method) is GEOS's `MakeValid` and `BuildArea`, ported to GEOS from rttopo and PostGIS (LGPL): JTS 1.20 has no equivalent (only the structural `GeometryFixer`). The port's `MakeValid` and `BuildArea` are written for this port from the algorithm as GEOS documents and runs it (node the boundary by a union with its first point, keep the points that collapse, build areas from the cut edges by polygonizing, keeping faces with an even number of parents and dissolving them by a cascaded union, add each area by symmetric difference and remove its boundary from the cut edges until no area can be built), in GEOS's order of operations and with GEOS's containers, on the port's own JTS operations. They are not a translation of GEOS's code. This is a decision taken on the user's behalf (the conservative alternative, BLOCKED, would leave `GEOSMakeValid` without a port); it is listed in `Docs/PortingTopologyProgress.md`, Decisions, for the user to confirm.

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
