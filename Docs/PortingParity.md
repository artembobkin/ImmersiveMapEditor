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
