# Goal: port GEOS and osm2streets to Swift, with proven parity

This is a self-contained task for an agent (Fable). Read the package's `CLAUDE.md` first and follow it (Swift only, modern Apple APIs, naming, architecture, tests, English in files, replies to the user in Russian). The user asked for this on 2026-10-24.

## What and why

The package has two dependencies that are not Swift:

1. **GEOS** (C++), the geometry library behind the `Geometry` target (`Sources/Geometry/Geometry.swift`, a thin wrapper over its C API). It comes from the SwiftPM package `GEOSwift/geos` 9.0.0, which packages GEOS 3.13.0. Because it is a dynamic library of a dependency, Xcode cannot build it with code coverage (see `CLAUDE.md`).
2. **osm2streets** (Rust), run as the binary `~/Desktop/TilePipeline/tools/osm2streets_cli` by `TileKit`'s `Seed` (`Sources/TileKit/Pipeline/Seed.swift`): it reconstructs roads, lanes and intersections from OSM, and the road documents are seeded from its output.

Port both to Swift, as targets of this package, **behaving exactly as they do today**, prove it with tests, then remove the originals from the build. Nothing outside the new targets and their wiring should notice the change.

## Running this as a goal, unattended

This task is far larger than one session: expect weeks of agent work, not a night. A goal run therefore works on a **range of phases** and ends in one of three states. The state is the first line of `Docs/PortingStatus.md`, and the goal counts as reached when that line is any of them:

- `DONE`: the Definition of done holds in full.
- `PHASES DONE <first>-<last>`: the phases this run was asked for are green (build, tests, their parity checks) and committed.
- `BLOCKED: <one line>`: something cannot be made to behave identically, or a source, tool or download the task needs is missing, after **three distinct attempts**. The status file then holds the phase, what was tried, the smallest input that shows the problem, and what the user should decide. `Docs/PortingParity.md` holds the full record.

The phases of a run come from the goal text (for example "phases 1 to 3"). With no range given, the run takes the next unfinished phase in the status file and the ones after it until an end state. The right size for one night is one to three phases.

Checkpointing, so a new session continues where the last stopped:

- `Docs/PortingStatus.md` holds the current phase, the last green commit, the next step, and every decision taken on the user's behalf. Update it after every finished step, not only at the end.
- A session's first actions: read this document and the status file. Its last action: update the status file.

Forbidden during an unattended run, whatever the phase says:

- `git push`, force pushes, rebases, history rewrites, amends of earlier commits. Commits stay local, the user pushes.
- Deleting `~/Desktop/TilePipeline/tools/osm2streets_cli`, removing the `GEOSwift/geos` dependency before phase 12, or changing anything in `~/Desktop/TilePipeline` outside a scratch folder. (Phase 11 keeps the Rust CLI in place; whether to delete it is the user's later decision, noted in the status file.)
- Network beyond fetching the JTS 1.20.0 sources and the crates named above; installing anything system-wide.
- Loosening a tolerance, skipping a parity check or marking a test as expected to fail to get past it. A parity failure after three approaches is `BLOCKED`, never a lower bar.
- Asking the user and waiting. Decide, take the conservative choice (the one that changes less and deletes nothing), and record the decision in the status file.

## Definition of done

- New targets build with no errors and no warnings (`swift build -c release`) and `swift test` passes, also in Xcode with the shared schemes, **with code coverage turned back on** in `.swiftpm/xcode/xcshareddata/xcschemes/` once GEOS is gone.
- `Package.swift` no longer depends on `GEOSwift/geos`. `TileKit`'s `Seed` no longer runs a Rust binary. No C, C++, Rust, Python or other non-Swift code anywhere in the build.
- Every parity check below passes and its results are written to `Docs/PortingParity.md` (numbers, not adjectives): what was compared, on what data, what matched, every difference found and why it is accepted.
- `CLAUDE.md` (this package and `~/Desktop/TilePipeline/CLAUDE.md`) describe the new targets, and the "Known issue" about coverage is gone.
- Licences and attributions are in place (see Licences).
- Work is committed in steps (one per phase at least), each building and testing green, with the commit attribution the session gives.

## Licences: what may be ported, from where

The package is MIT (`LICENSE`). Only port from sources whose licence allows it, keep their notices, and put each port's licence next to it.

| Source | Licence | Use |
|---|---|---|
| **JTS Topology Suite 1.20.0** (`github.com/locationtech/jts`, tag `1.20.0`) | EPL-2.0 **or** EDL-1.0 (EDL is BSD-3-Clause) | **Port the geometry from JTS, under EDL-1.0.** GEOS 3.13 is a C++ port of JTS 1.20 and behaves the same. |
| GEOS 3.13.0 | LGPL-2.1 | **Do not port or copy from GEOS.** A port would be a derived work under LGPL, which does not fit an MIT package statically linked into an app. GEOS may be read to understand a behaviour difference and stays the test oracle until the end (see Parity). |
| osm2streets, streets_reader, osm2lanes (`github.com/a-b-street/osm2streets`, rev `fc119c4`) | Apache-2.0 | Port. |
| geom (`github.com/a-b-street/geom`, rev `9bb49fc`) | Apache-2.0 | Port the parts osm2streets uses. |
| abstutil (`github.com/a-b-street/abstreet`, rev `ca1fb9a`) | Apache-2.0 | Only `Tags`, `Timer` (may be a no-op), `wraparound_get`. |
| osm-reader (`github.com/a-b-street/osm-reader`, rev `7892405`) | Apache-2.0 | Port (OSM XML reading). |
| geo 0.27.0, geo-types 0.7 (crates.io) | MIT or Apache-2.0 | Port the algorithms geom and osm2streets call (`BooleanOps` and the rest used, see below). |
| rstar 0.11 / 0.12, petgraph 0.6.5, polylabel 3.2.0, ordered-float | MIT or Apache-2.0 | Port what is used, or replace by an equivalent Swift structure if the results are provably the same. |
| earcutr 0.4.3 | ISC | Port. |
| country-boundaries 1.2.0 | code Apache-2.0, data ODbL (OpenStreetMap) | Port the lookup, carry the data with ODbL attribution (as OSM's). |
| **Muv** (`muv-osm`, GitLab LeLuxNet/Muv rev `2404d40`) | MPL-2.0 (apps GPL-3.0) | **Do not port.** osm2streets uses only `muv_osm::lanes::highway::driving_side`, the side of the road a country drives on. Write that table yourself from public facts (left-hand traffic countries), not from Muv's source, and test that it gives the same answer for every country code Muv knows. |

Each ported target gets a `LICENSE` (or `NOTICE` for Apache-2.0) file in its source folder naming the original project, its licence, the revision ported and that the code was translated to Swift. The package `README.md` lists them.

Exact sources are on this machine: osm2streets and its git dependencies in `~/.cargo/git/checkouts/` (`osm2streets-*/fc119c4`, `geom-*/9bb49fc`, `abstreet-*/ca1fb9a`, `osm-reader-*/7892405`), the crates in `~/.cargo/registry/src/index.crates.io-*/`. Fetch JTS 1.20.0 from GitHub. Pin every revision in the ports' notices.

## Target layout

Each library its own target, named in UpperCamelCase (see `CLAUDE.md`):

- `Topology`: the port of JTS (the subset below). Value types and contiguous arrays on the hot paths (coordinates, segment chains, indexes): a class-for-class translation of Java is too slow.
- `Geometry` (exists): keeps its public API exactly (shapely's names, `Geometry`, `Prepared`, `STRtree`, `P2`), now implemented on `Topology` instead of GEOS. `TileKit` and the app must not change because of the swap.
- For osm2streets, by the crate boundaries:
  - `StreetGeom` (geom),
  - `GeoAlgorithms` (the geo subset),
  - `Earcut`,
  - `OSMReader` (osm-reader),
  - `CountryBoundaries`,
  - `Streets` (osm2streets, streets_reader, osm2lanes).

  Merge small ones if that is clearly simpler, but keep each licence's code apart.
- Tests: `Tests/TopologyTests`, `Tests/StreetsTests`, and a parity harness (see Parity). Large fixtures stay outside git (generated into `.build` or read from `~/Desktop/TilePipeline/data`), small ones may be committed.

## The scope of each port

### GEOS / JTS: what the package calls

Every GEOS function `Sources/Geometry/Geometry.swift` uses must have a JTS-ported equivalent with the same semantics as GEOS 3.13:

- **Constructing and reading:** points, line strings, linear rings, polygons, collections (create, clone, rings, parts, coordinates), type, empty, valid, area, length, bounds, centroid, point on surface, WKT output.
- **Overlay:** union, intersection, difference, unary union. These are OverlayNG with the floating precision model, as GEOS 3.13 uses by default.
- **Buffer and offset curve:** quadrant segments, cap and join styles, mitre limit, negative distances.
- **Validity and precision:** make valid (GEOS `GEOSMakeValid`, the "linework" method), set precision (GEOS `GEOSGeom_setPrecision` with a grid size, which is JTS's `GeometryPrecisionReducer` with snap-rounding), topology-preserving simplify.
- **Hulls:** convex hull, envelope, boundary, minimum rotated rectangle.
- **Linear referencing:** interpolate (by distance and normalized, negative distances from the end, on multi-lines), project.
- **Distance and predicates:** distance, nearest points, intersects, contains, within. Point-in-polygon and polygon-polygon both occur.
- **Prepared geometry:** contains, intersects.
- **Triangulation:** constrained Delaunay of a polygon (GEOS `GEOSConstrainedDelaunayTriangulation`, JTS `ConstrainedDelaunayTriangulator` in `triangulate.polygon`).
- **Lines:** polygonize, line merge.
- **STRtree:** query by envelope, nearest.

The robustness machinery comes with them and must be ported faithfully:

- `Orientation` with double-double (DD) arithmetic, `CGAlgorithmsDD`, `RobustLineIntersector`;
- the noders: monotone chains, `MCIndexNoder`, snap-rounding with `HotPixel`, KD-tree;
- the overlay graph and labelling;
- the buffer curve builder and its noding.

Do not simplify these: they are why overlays never come out broken on real data.

### osm2streets: what the pipeline calls

`tools/osm2streets_cli/src/main.rs` (58 lines) shows the whole surface:

- `streets_reader::osm_to_street_network(osm XML, clip polygon, MapConfig { inferred_sidewalks: true, inferred_kerbs: true, ..default })`;
- `apply_transformations(Transformation::standard_for_clipped_areas())`;
- the four GeoJSON outputs: `to_geojson`, `to_lane_polygons_geojson`, `to_lane_markings_geojson`, `to_intersection_markings_geojson`.

The Swift port exposes the same, returning the four GeoJSON documents (and, better, typed values `Seed` reads directly, once parity on the GeoJSON is proven).

Size to port, roughly, in lines of Rust:

| Crate | Lines |
|---|---|
| osm2streets | 5.7k |
| streets_reader | 1.2k |
| osm2lanes | 2.3k |
| geom | 5.2k, the part used |
| osm-reader | 0.4k |
| the geo algorithms used | to measure (`BooleanOps` and its sweep, `Area`, `Contains`, `ConvexHull`, `Intersects`, `SimplifyVwPreserve`, coordinate mapping, and whatever else geom's `polygon.rs`, `ring.rs`, `polyline.rs`, `tessellation.rs` call) |
| earcutr, polylabel, rstar parts | small |

## Parity: how "the same" is proven

The bar is **one to one**. A difference is a failure until it is explained, and an explanation is either a documented difference between GEOS 3.13 and JTS 1.20 or a floating point difference below the tolerances here. Write the results to `Docs/PortingParity.md`.

### Topology against GEOS

Keep GEOS as a **test-only** dependency until the last phase, wrapped in a small oracle in the test target. Compare the Swift result with GEOS's for the same input:

- **Same inputs, same outputs.** Normalize both results (as `GEOSNormalize` / JTS `normalize()`). Then:
  - they must be equal exactly: same structure and every coordinate bit-for-bit;
  - where an algorithm is known to be sensitive (buffer arcs, offset curves), a coordinate tolerance of 1e-9 m, recorded per case;
  - predicates and counts equal exactly;
  - areas and lengths within 1e-9 relative.
- **The JTS XML test suites** (`modules/tests/src/test/resources/testxml/` of JTS 1.20.0: `general`, `validate`, `robust`, `misc`): parsed and run against `Topology`. All must pass as they pass in JTS.
- **Real data**: every polygon, line and point the pipeline makes for the five built tiles (`15/19808/10242`, `15/19809/10242`, `15/19808/10243`, `15/19809/10243`, `15/19810/10243`). Record every geometry operation's inputs through the `Geometry` wrapper in a recording mode, then replay them against both implementations. Hundreds of thousands of calls: all must match.
- **Random data**: property tests with seeded random polygons with holes, near-degenerate cases (collinear points, touching rings, slivers, coordinates far from the origin), compared with GEOS.

### Streets against the Rust osm2streets

The oracle is the existing binary (`~/Desktop/TilePipeline/tools/osm2streets_cli/target/release/osm2streets-cli`, built from rev `fc119c4`).

- **osm2streets's own 30 test cases** (`tests/src/*/input.osm` with `boundary.json`): run both, and require identical GeoJSON:
  - the same features in the same order;
  - the same properties, every value;
  - the same coordinates, exactly, or within 1e-9 degrees where float formatting alone differs.

  Also check against the committed `geometry.json` the Rust tests check.
- **Moscow**: the merged OSM of `~/Desktop/TilePipeline/data/regions/15_19808_10242_19809_10243/osm.json` with its clip (written by `Seed`), and each tile's own `data/<z>_<x>_<y>/osm.json`. The four GeoJSON outputs must be identical under the same rules.
- **Every country's driving side**: the replacement for Muv's `driving_side` gives the same side as Muv for every country code it handles.

### The whole pipeline, end to end

With both ports in place, and the originals still at hand to compare:

- **Building tiles.** `tilepipeline lab data/15_19808_10243 <scratch> --whole --export --samples 64` before and after. These must be identical:
  - `triangles`;
  - every entry of `triangles_by_kind`;
  - `landmark_windows`, `bus_shelters`, `overhang_m`;
  - `palette.png`.

  The light map may differ only by the bake's own run-to-run noise (measure it by running the old binary twice).

  Do the same for the four other tiles.
- **Seeding roads.** `tilepipeline seed 15 19808 10242 19809 10243` into a temporary root (symlink the four tiles' `data/` folders, empty `roads/`) before and after: the road documents byte-identical except the `"seeded"` date line.
- **The editor.** The editor's `--resave` of the user's real road document is byte-identical, `--snapshot` of tiles pixel-identical, and the editor's own tests pass.
- **Performance.** A whole tile builds in at most 1.5 times the time it takes now (10 to 20 s), and seeding the 2x2 block in at most 1.5 times now (about 14 s). Measure and record before and after.

## Phases

Each phase ends green (build, tests, its parity checks) and committed.

1. **Oracle and recording.** A test-only GEOS oracle, the JTS XML test runner (against GEOS first, to validate the runner), and a recording mode in `Geometry` that writes every call's inputs. Record the five tiles.
2. **Topology core.** Coordinates, envelopes, geometry model, WKT, `Orientation` and DD, point location, area, length, centroid, interior point, convex hull, minimum rotated rectangle.
3. **Indexes and noding.** STRtree, monotone chains, KD-tree, `MCIndexNoder`, snap-rounding.
4. **Overlay.** OverlayNG, unary union, then predicates (intersects, contains, within, prepared), distance and nearest points.
5. **Buffer and offset curve.**
6. **Make valid, precision, simplify.**
7. **Triangulation, polygonize, line merge, linear referencing.**
8. **Swap `Geometry` onto `Topology`.** Every replayed call matches, the pipeline end-to-end checks pass. GEOS stays only in tests.
9. **Streets foundations.** `StreetGeom` and `GeoAlgorithms` (with their own tests against the Rust crates' behaviour: write small Rust-side fixtures from the Rust sources' tests where they exist), `Earcut`, `OSMReader`, `CountryBoundaries`, the driving side table.
10. **Streets.** osm2lanes, streets_reader, osm2streets, its transformations, the four outputs. Parity on the 30 cases and Moscow.
11. **Swap `Seed` onto `Streets`.** Seeding parity, then remove the Rust CLI from the pipeline (keep `tools/osm2streets_cli` in TilePipeline as the oracle for the tests, documented as such; whether to delete it is the user's decision later, noted in the status file).
12. **Remove GEOS.** Drop `GEOSwift/geos` from `Package.swift`, keep the recorded parity cases as regression tests against stored expected outputs, turn code coverage back on in the shared Xcode schemes, update both `CLAUDE.md` files, `README.md`, and write `Docs/PortingParity.md` in full.

## Rules for the work

- Port, then optimise: the first version follows the original's algorithms, branch for branch and in the same order of floating point operations. Speed up only with parity tests green before and after.
- Never change the user's road documents (`~/Desktop/TilePipeline/roads/`) or built tiles in `out/tiles/`: compare in a scratch folder.
- Keep the `Geometry` API, `TileKit` and the app untouched by the swap, except `Seed` in phase 11.
- If something cannot be made identical after three distinct attempts, record it in `Docs/PortingParity.md` with the smallest input that shows it, write `BLOCKED` to `Docs/PortingStatus.md` and end the run (see "Running this as a goal"). Never go on past a known difference.
