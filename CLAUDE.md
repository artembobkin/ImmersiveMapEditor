# Immersive Map Editor

The desktop tool for the content of the ImmersiveMap engine (`~/Desktop/ImmersiveMap`), native to the Mac: Swift, AppKit, SwiftUI and Metal. It also holds the tile pipeline itself, in Swift (decided with the user, 2026-10-24: no Python), so one package builds both the editor and `tilepipeline`. It is meant to grow into the place where the engine's content is tuned (decided with the user, 2026-10-24). It works on a TilePipeline folder (`~/Desktop/TilePipeline`, the pipeline that turns a map tile into one 3D model), its workspace, in three views:

- **Map**: OpenStreetMap under the grid of z15 tiles, each coloured by what TilePipeline has of it (built, OSM fetched, a road document). Pick tiles, then show the built ones in 3D, open their road document, or fetch OSM and build them (`tilepipeline build --tiles`, which seeds a road document for the tiles that have none).
- **Roads**: corrects a road document by hand, the one source of a tile's roads (its format is the doc comment of `Sources/TileKit/Roads.swift`).
- **Tiles 3D**: the tiles picked shown together as the engine draws them, so the engine is not needed to look at them.

## The package

Targets, each a library a port or a wrapper lives in, as the user asked:

- `Geometry`: GEOS (the C++ library shapely stands on, from the `GEOSwift/geos` package, built from source) wrapped in Swift with shapely's names: buffer, union, difference, simplify, make valid, precision, offset curve, constrained Delaunay, polygonize, line merge, linear referencing, `Prepared`, `STRtree`. One GEOS context, one thread at a time.
- `GLTF`: glTF binaries read (landmark models, their textures through ImageIO) and written (the tile: one mesh, palette and light map embedded; a fitted model of several materials).
- `LightBaker`: the light map's bake on the GPU, Metal ray tracing: the tile from straight above, every surface white, an even sky a little brighter toward the zenith, three bounces.
- `TileKit`: the pipeline. `Common` (tile and range projections, OSM, tags), `Palette`, `PNG`, `Mesh` (the triangle builder, `clean`, `cut`), `Buildings`, `Landmarks` (sorting OSM buildings), `Imported` (the landmark models of Modeling, fitted by their recipes), `Construction`, `Furniture`, `Markings`, `Roads` (the road document: format, seeding, loading), `Ground`, `Lighting`, `Export`, `Build` (one tile or a lab square), `Fetch` (Overpass), `Seed` (osm2streets and the road document of a range), `Validate`, `Fit` (a downloaded landmark fitted to OSM), `Pipeline` (the whole run over a set of tiles). `pipelineRoot` is the TilePipeline folder it works on.
- `tilepipeline`: the command line over TileKit.
- `ImmersiveMapEditor`: the app. It builds tiles by running `tilepipeline` beside its own executable, so a build never blocks the window.

The one tool that is not Swift is osm2streets (Rust), run as `tools/osm2streets_cli` of TilePipeline when a road document is seeded.

## Commands

```sh
swift build -c release
./make_app.sh                    # build/Immersive Map Editor.app, tilepipeline inside it
TP=.build/release/tilepipeline   # run in the TilePipeline folder, or give --root
$TP build 15 --tiles 19808/10243 19810/10243     # fetch, seed roads, build, validate (or Z X Y, or Z X0 Y0 X1 Y1)
$TP lab data/15_19808_10243 out/style_lab [--region CX CY HALF | --whole] [--export]
$TP fetch 15 19808 10243 [--force]
$TP seed 15 19808 10242 19809 10243 [--force]    # never over hand edits without --force
$TP validate out/tiles/15/19808/10243
$TP fit detsky-mir
.build/release/ImmersiveMapEditor [~/Desktop/TilePipeline | ROAD DOCUMENT]
.build/release/ImmersiveMapEditor --resave IN OUT                        # read and write a document, no window
.build/release/ImmersiveMapEditor --snapshot TILEPIPELINE OUT.png X/Y...  # tiles in 3D, no window
.build/release/ImmersiveMapEditor --map-snapshot TILEPIPELINE OUT.png     # the map of tiles, no window
```

With no argument the app opens the workspace opened last, else `~/Desktop/TilePipeline`. The map's background is OpenStreetMap's raster tiles (tile.openstreetmap.org), fetched only for what is on screen with a User-Agent naming the app, cached in `~/Library/Caches/ImmersiveMapEditor/osm/` and attributed on the map, as its usage policy asks. Never fetch them in bulk.

## The sources

- `main.swift`: the app, its menus, building tiles, `--resave`, `--snapshot`, `--map-snapshot`.
- `Workspace.swift`: what TilePipeline has of each tile (fetched, built, its road document), the tiles picked and the tiles shown in 3D, kept between launches.
- `MapPicker.swift`: the Map view and the OpenStreetMap raster tiles under it (`RasterTiles`).
- `RoadDocument.swift`: the road document in local metres, read and written byte for byte in the pipeline's layout (an unedited document comes out the same), and the underlay (`Underlay`).
- `Geometry.swift`: `Vec2`, the projection of a range of tiles (Web Mercator around its centre, as TilePipeline's `Region`), polygon helpers: winding, nearest point, Douglas-Peucker, fillet, offset, dashes.
- `Markings.swift`: what TileKit's `Markings` makes of a marking's parameters, drawn as quads, the same constants and rules. Change both together.
- `EditorModel.swift`: the state, the selection, every edit with its undo, the roadway test (`RoadwayIndex`).
- `MapView.swift`, `Renderer.swift`: the 2D roads view, its gestures and tools, drawn on demand with Metal. Polygons with holes are filled through the stencil (non-zero winding), with no triangulation.
- `TileModel.swift`, `TileView.swift`: the 3D view. A tile's GLB read as the engine's tooling reads it (one primitive, palette and light map embedded as PNG), drawn as palette × light map, raw values, back faces culled, each tile placed and scaled as the engine places it. The mouse works as the engine's (`MapGestureControllerMac`): the left button drags the ground, the right one (or the left with option) turns sideways and tilts up and down, scrolling zooms toward the ground under the cursor. Keep the two alike. Tab flies (W A S D, Q, E, right-drag to look).
- `Inspector.swift`: the window (`Session`, `ContentView`) and the SwiftUI panels of each view.
- `Icon/make_icon.swift`: draws `Icon/AppIcon.png`, the icon (a tile in isometric view in the tiles' palette). `make_app.sh` makes the `.icns` from it.
- `BuildRunner.swift`: runs `tilepipeline build` and shows its log.

## Rules

- English in every file: code, comments, logs, documentation. Replies to the user are in Russian.
- No em dash (U+2014) and no semicolon joining two clauses in prose.
- Never change the engine from here. TilePipeline is now this package's workspace: its data, road documents and landmarks, not code.
- Draw what the engine draws: when the engine's way of drawing a model tile changes (`ImmersiveMap/Sources/ImmersiveMap/SceneModels/ModelTiles/`), the 3D view follows.
- No external packages unless asked for.

## Parity with the Python build

The pipeline was ported from TilePipeline's Python (2026-10-24) and checked against it on 15/19808/10243: the same triangles of every kind but walls and roofs (6 and 3 more of 205 thousand, from triangulating concave faces), the same landmark windows, roads, markings and shelters, the light map within 0.001 per channel, the seeded road document the same but one point of 22 thousand, the fitted Detsky Mir the same. A tile builds in 10 to 20 s.
