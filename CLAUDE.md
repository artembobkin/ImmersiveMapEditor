# Immersive Map Editor

The desktop tool for the content of the ImmersiveMap engine (`~/Desktop/ImmersiveMap`), native to the Mac: Swift, AppKit, SwiftUI and Metal, no other packages. It is meant to grow into the place where the engine's content is tuned (decided with the user, 2026-10-24). Today it does two things for TilePipeline (`~/Desktop/TilePipeline`), the pipeline that turns a map tile into one 3D model:

- **Roads**: corrects TilePipeline's road document by hand, the one source of a tile's roads (its format is the doc comment of TilePipeline's `build/roads.py`).
- **Tiles 3D**: shows the built tiles of the document (`out/tiles/<z>/<x>/<y>/` of TilePipeline) as the engine draws them, so neither the live Blender nor the engine is needed to look at them.

## Commands

```sh
swift build -c release
./make_app.sh                    # build/Immersive Map Editor.app
.build/release/ImmersiveMapEditor ~/Desktop/TilePipeline/roads/15_19808_10242_19809_10243.json
.build/release/ImmersiveMapEditor --resave IN OUT              # read and write a document, no window
.build/release/ImmersiveMapEditor --snapshot DOCUMENT OUT.png [X Y]   # the 3D view rendered, no window
```

With no argument the app opens the document opened last, else TilePipeline's first road document, else asks for one. A document's project is the folder above its `roads/`: the underlay comes from its `data/regions/<range>/context.json`, the built tiles from its `out/tiles/`, and Tiles > Build runs its `pipeline.py`.

## The sources

- `main.swift`: the app, its window and menus, `--resave` and `--snapshot`.
- `RoadDocument.swift`: the road document in local metres, read and written byte for byte in the pipeline's layout (an unedited document comes out the same), and the underlay (`Underlay`).
- `Geometry.swift`: `Vec2`, the projection of a range of tiles (Web Mercator around its centre, as TilePipeline's `Region`), polygon helpers: winding, nearest point, Douglas-Peucker, fillet, offset, dashes.
- `Markings.swift`: what TilePipeline's `build/markings.py` makes of a marking's parameters, the same constants and rules. Change both together.
- `EditorModel.swift`: the state, the selection, every edit with its undo, the roadway test (`RoadwayIndex`).
- `MapView.swift`, `Renderer.swift`: the 2D roads view, its gestures and tools, drawn on demand with Metal. Polygons with holes are filled through the stencil (non-zero winding), with no triangulation.
- `TileModel.swift`, `TileView.swift`: the 3D view. A tile's GLB read as the engine's tooling reads it (one primitive, palette and light map embedded as PNG), drawn as palette × light map, raw values, back faces culled, each tile placed and scaled as the engine places it. Orbit and flight cameras.
- `Inspector.swift`: the SwiftUI panels.
- `Icon/make_icon.swift`: draws `Icon/AppIcon.png`, the icon (a tile in isometric view in the tiles' palette). `make_app.sh` makes the `.icns` from it.
- `BuildRunner.swift`: runs TilePipeline's `pipeline.py` and shows its log.

## Rules

- English in every file: code, comments, logs, documentation. Replies to the user are in Russian.
- No em dash (U+2014) and no semicolon joining two clauses in prose.
- Never change TilePipeline or the engine from here without saying so: they have their own repositories and sessions.
- Draw what the engine draws: when the engine's way of drawing a model tile changes (`ImmersiveMap/Sources/ImmersiveMap/SceneModels/ModelTiles/`), the 3D view follows.
- No external packages unless asked for.

## Next

- Building tiles without Blender (decided with the user, 2026-10-24): TilePipeline's geometry on numpy arrays with its own GLB writer, and the light map baked here with Metal ray tracing (sky occlusion from each texel), called by the pipeline.
