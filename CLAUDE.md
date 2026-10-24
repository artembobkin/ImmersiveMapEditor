# Immersive Map Editor

The desktop tool for the content of the ImmersiveMap engine (`~/Desktop/ImmersiveMap`), native to the Mac: Swift, AppKit, SwiftUI and Metal, no other packages. It is meant to grow into the place where the engine's content is tuned (decided with the user, 2026-10-24). It works on a TilePipeline folder (`~/Desktop/TilePipeline`, the pipeline that turns a map tile into one 3D model), its workspace, in three views:

- **Map**: OpenStreetMap under the grid of z15 tiles, each coloured by what TilePipeline has of it (built, OSM fetched, a road document). Pick tiles, then show the built ones in 3D, open their road document, or fetch OSM and build them (`pipeline.py --tiles`, which seeds a road document for the tiles that have none).
- **Roads**: corrects a road document by hand, the one source of a tile's roads (its format is the doc comment of TilePipeline's `build/roads.py`).
- **Tiles 3D**: the tiles picked shown together as the engine draws them, so the engine is not needed to look at them.

## Commands

```sh
swift build -c release
./make_app.sh                    # build/Immersive Map Editor.app
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
- `Markings.swift`: what TilePipeline's `build/markings.py` makes of a marking's parameters, the same constants and rules. Change both together.
- `EditorModel.swift`: the state, the selection, every edit with its undo, the roadway test (`RoadwayIndex`).
- `MapView.swift`, `Renderer.swift`: the 2D roads view, its gestures and tools, drawn on demand with Metal. Polygons with holes are filled through the stencil (non-zero winding), with no triangulation.
- `TileModel.swift`, `TileView.swift`: the 3D view. A tile's GLB read as the engine's tooling reads it (one primitive, palette and light map embedded as PNG), drawn as palette × light map, raw values, back faces culled, each tile placed and scaled as the engine places it. The mouse works as the engine's (`MapGestureControllerMac`): the left button drags the ground, the right one (or the left with option) turns sideways and tilts up and down, scrolling zooms toward the ground under the cursor. Keep the two alike. Tab flies (W A S D, Q, E, right-drag to look).
- `Inspector.swift`: the window (`Session`, `ContentView`) and the SwiftUI panels of each view.
- `Icon/make_icon.swift`: draws `Icon/AppIcon.png`, the icon (a tile in isometric view in the tiles' palette). `make_app.sh` makes the `.icns` from it.
- `BuildRunner.swift`: runs TilePipeline's `pipeline.py` and shows its log.

## Rules

- English in every file: code, comments, logs, documentation. Replies to the user are in Russian.
- No em dash (U+2014) and no semicolon joining two clauses in prose.
- Never change TilePipeline or the engine from here without saying so: they have their own repositories and sessions.
- Draw what the engine draws: when the engine's way of drawing a model tile changes (`ImmersiveMap/Sources/ImmersiveMap/SceneModels/ModelTiles/`), the 3D view follows.
- No external packages unless asked for.

## TilePipeline without Blender

Since 2026-10-24 TilePipeline builds without Blender (the user removed it): plain Python with numpy, shapely and Pillow in its `.venv`, and the light map baked on the GPU by its `tools/light_baker` (Swift, Metal ray tracing). The editor runs `pipeline.py` with the system `python3`, which starts `.venv` for every step that needs it.
