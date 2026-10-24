# Immersive Map Editor

The desktop tool for the content of the ImmersiveMap engine (`~/Desktop/ImmersiveMap`, a Swift and Metal map engine), native to the Mac. It is meant to grow into the place where the engine's content is made and tuned (decided with the user, 2026-10-24). Today it is two things in one Swift package:

- **The tile pipeline** (`TileKit` and the command line `tilepipeline`): OpenStreetMap to one 3D model per z15 map tile (GLB with a palette and a baked light map), which the engine shows over its vector tile. Its rules of style and output are in `~/Desktop/TilePipeline/CLAUDE.md`: read it before changing what a tile looks like.
- **The editor** (the app), on a TilePipeline folder, its workspace (`~/Desktop/TilePipeline`: `data/`, `roads/`, `landmarks/`, `out/`), in three views:
  - **Map**: OpenStreetMap under the grid of z15 tiles, each coloured by what the workspace has of it (built, OSM fetched, a road document). Pick tiles, then show the built ones in 3D, open their road document, or fetch OSM and build them (`tilepipeline build --tiles`, which seeds a road document for the tiles that have none).
  - **Roads**: corrects a road document by hand, the one source of a tile's roads (its format is the doc comment of `Sources/TileKit/Roads.swift`).
  - **Tiles 3D**: the tiles picked, shown together as the engine draws them, so neither the engine nor any other tool is needed to look at them.

Public repository: `github.com/artembobkin/ImmersiveMapEditor`, MIT, as the engine.

## How we work

These are the user's decisions (2026-10-24). Follow them without asking again.

- **Swift only.** Everything is written in Swift: the app, the pipeline, the tools, the scripts. No Python, in any form: not for the build, not for a quick check, not for a one-off conversion (a throwaway check is a small Swift executable or a `swift` script in the scratchpad, never left in the package). No Blender: the user removed it. No JavaScript or web views.
- **Native to the Mac, modern Apple only.** The interface is SwiftUI with its own app life cycle: `@main App`, scenes (`WindowGroup`, `Window`, `Settings`), `.commands` for menus and shortcuts, `.toolbar`, `.inspector`, `.fileImporter`, `.alert`, `Canvas` for 2D drawing. State is Observation (`@Observable`, `@Bindable`, `@Environment`), work is Swift concurrency (`async`/`await`, `Task`, `@MainActor`). The GPU work (drawing, the light bake) is Metal. Forbidden, as old: `NSApplication` delegates and run loops, `NSWindow`, `NSMenu`, `NSAlert`, `NSOpenPanel`, `NSTextView`, `NSHostingView`, AppKit drawing (`NSView.draw`, `NSBezierPath`, `NSImage` drawing), Combine (`ObservableObject`, `@Published`, `sink`), `DispatchQueue`, completion handlers where an `async` API exists. **Where AppKit stays**: only in the folder `Sources/ImmersiveMapEditor/Metal/`, and only for what SwiftUI has no API for: the Metal views (`MTKView`) with their input (scroll wheel, right and other mouse buttons, key up), `MetalHost` (the one `NSViewRepresentable`), the `onScrollWheel` modifier for a SwiftUI view (a local `NSEvent` monitor), and the activation policy of the bare executable (`Platform`). No file outside `Metal/` imports AppKit: a new need for AppKit gets a small bridge there, used from SwiftUI.
- **Libraries.** A Swift library first. A C or C++ library is allowed when nothing in Swift does the job well (GEOS for geometry is one), wrapped in Swift. Each library, wrapper or port is a **target of its own** (`Geometry` wraps GEOS, `GLTF`, `LightBaker`), never mixed into `TileKit` or the app. Name a wrapper's operations as the code it ports named them, so a port reads side by side with its original. Add a package dependency only for such a library, pinned to an exact version.
- **The one exception** is osm2streets (Rust), a small binary in the workspace (`tools/osm2streets_cli`), run only when a road document is seeded. Do not add other non-Swift tools. Porting osm2streets is not planned.
- **A port is faithful.** The same algorithm, constants, order of operations and tie-breaking as the original, then checked against it on real data (see Checking). Improve after the port is checked, not during it.
- **The engine is read, never changed** from here (`~/Desktop/ImmersiveMap`). What the editor shows follows how the engine draws: when the engine's drawing of a model tile changes (`ImmersiveMap/Sources/ImmersiveMap/SceneModels/ModelTiles/`), the 3D view follows. The 3D camera works as the engine's (`UI/Gestures/MapGestureControllerMac.swift`): left button drags the ground, right button (or option with the left) turns sideways and tilts up and down, scrolling zooms toward the ground under the cursor. Keep the two alike.
- **Hand edits are sacred.** A road document in `roads/` holds the user's corrections: never seed it again, overwrite or "regenerate" it without being asked (`tilepipeline seed` refuses without `--force`). The editor writes it byte for byte in the pipeline's layout: an unedited document saved by the editor is identical to the file.
- **Sources are fixed.** `data/` is raw, never edited by hand. An `osm.json` on disk is kept unless the user asks to fetch again.
- **OpenStreetMap's tile server**: only what is on screen, with the app's User-Agent, cached on disk, attributed on the map. Never fetch tiles in bulk.

## Writing

- English in every file: code, comments, logs, documentation, commit messages. Replies to the user are in Russian.
- No em dash (U+2014) and no semicolon joining two clauses in prose: two sentences, a comma, a colon or parentheses.
- Comments say what a thing is and why, in full sentences, in the density of the code around them. Every file starts with a doc comment of what it is for.
- Commits end with `Co-Authored-By:` the model that wrote them. The repository is public: no secrets, no personal data, no absolute home paths in code beyond the defaults of the workspace and Modeling.

## Checking

Every change is checked before it is called done, and the check is said plainly (what ran, what came out).

- `swift build -c release` with no errors and no new warnings, and `swift test` passing.
- Looking at a result without a screen: `ImmersiveMapEditor --snapshot WORKSPACE OUT.png X/Y...` (tiles in 3D) and `--map-snapshot WORKSPACE OUT.png` (the map) render offscreen to a PNG that can be read. Do not capture the screen (`screencapture`): it raises a permission prompt the user must answer. The live window is the user's to try.
- The road document: `ImmersiveMapEditor --resave IN OUT` then `cmp IN OUT`, identical.
- A tile: `tilepipeline validate`. A change to the pipeline: build `15/19808/10243` (Red Square, with landmarks, construction sites and roads) before and after and compare `stats.json` (`triangles`, `triangles_by_kind`, landmark windows, shelters) and the light map, and say what changed and why.
- Write builds of a check to the scratchpad, not to `out/tiles/`, unless the user asked for the tiles to be rebuilt.

## The package

Targets:

- `Geometry`: GEOS (the C++ library shapely stands on, from the `GEOSwift/geos` package, built from source) wrapped in Swift with shapely's names: buffer, union, difference, simplify, make valid, precision, offset curve, constrained Delaunay, polygonize, line merge, linear referencing, `Prepared`, `STRtree`. One GEOS context, one thread at a time.
- `GLTF`: glTF binaries read (landmark models, their textures through ImageIO) and written (the tile: one mesh, palette and light map embedded; a fitted model of several materials).
- `LightBaker`: the light map's bake on the GPU, Metal ray tracing: the tile from straight above, every surface white, an even sky a little brighter toward the zenith, three bounces. Needs Apple silicon.
- `TileKit`: the pipeline. `Common` (tile and range projections, OSM, tags), `Constants` (shared levels and sizes, `pipelineRoot`), `Palette`, `PNG`, `Mesh` (the triangle builder, `clean`, `cut`), `Buildings`, `Landmarks` (sorting OSM buildings), `Imported` (the landmark models of Modeling, fitted by their recipes), `Construction`, `Furniture`, `Markings`, `Roads` (the road document: format, seeding, loading), `Ground`, `Lighting`, `Export`, `Build` (one tile or a lab square), `Fetch` (Overpass), `Seed` (osm2streets and the road document of a range), `Validate`, `Fit` (a downloaded landmark fitted to OSM), `Pipeline` (the whole run over a set of tiles).
- `TilePipelineCommand`: the command line over TileKit, built as the program `tilepipeline` (a command keeps the lowercase name of the terminal).
- `ImmersiveMapEditor`: the app. It builds tiles by running `tilepipeline` beside its own executable, so a build never blocks the window and GEOS keeps its one thread.

The app's sources (`Sources/ImmersiveMapEditor/`), a folder per area:

- `App/`: `App.swift` (the entry, the SwiftUI app and its scenes), `EditorCommands.swift` (the menus), `Headless.swift` (`--resave`, `--snapshot`, `--map-snapshot`, before any window).
- `Session/`: `Session` (the workspace, the open road document, the build, what the window asks for), `Workspace` (what the TilePipeline folder has of each tile, the tiles picked and shown), `BuildRunner` (runs `tilepipeline build`, its output as an `async` sequence).
- `Map/`: the Map view in SwiftUI. `MapCamera` (centre and zoom), `RasterTiles` (OpenStreetMap's tiles, loaded with `async`), `MapCanvas` (drawn in `Canvas`), `MapPicker` (its gestures).
- `Roads/`: the road document as it is edited. `RoadPlan` (the plan in local metres, read and written through TileKit's `RoadDocument`), `RoadEditor` (the open plan, selection, tool, settings, layers; every change through `change`, one undo step, saved by its `DocumentStore`), `RoadEdits` (every edit as a plain operation on a plan), `Selection`, `Tool`, `RoadHitTest` (what is under a point), `ViewTransform2D`, `RoadwayIndex`, `Geometry2D` (fillet, simplify, offsets, dashes), `MarkingShapes` (markings as quads, with TileKit's constants), `Underlay`. `Tools/`: `RoadToolHandler` (the protocol, `Pointer`, `ToolPreview`, `ToolContext`) and one type per tool (`SelectTool`, `DrawTool`, `DragPlaceTool`, `ClickPlaceTool`).
- `Views/`: `ContentView` (the mode's view, `.toolbar`, `.inspector`, the status line, `.fileImporter`, `.alert`), `StatusLine`, `BuildLogView`, `Panels/` (one panel per mode, and the selection's).
- `Metal/`: everything drawn with Metal and every AppKit bridge. `AppKitBridge.swift` (`MetalHost`, `onScrollWheel`, `Platform`). `Roads2D/`: `RoadsView` (the thin `MTKView`: events to the tool, pan and zoom, keys to commands), `RoadsRenderer` (pipelines, stencil fills), `RoadLayers` (the plan as meshes), `RoadOverlay` (handles, selection, the tool's preview), `Mesh2D` (vertices, meshes, colours). `Tiles3D/`: `TileView` (the thin `MTKView`), `OrbitCamera` (the camera's math), `CameraController` (input to the camera: orbit and flight), `TileLibrary` (the tiles shown, loaded and placed), `TileRenderer` (pipelines, drawing, the offscreen snapshot), `TileModel` (a tile's GLB on the GPU).

TileKit's sources (`Sources/TileKit/`) are in folders the same way: `Core` (projections, tags, OSM, vectors), `Workspace` (`WorkspacePaths`, passed to whatever reads or writes the workspace: no global state), `Mesh`, `Style`, `Roads` (`RoadDocument`, seeding, loading, `Markings`, `Ground`, `Furniture`), `Buildings`, `Landmarks`, `Construction`, `Lighting`, `Output`, `Pipeline`.

## Architecture

Keep the code clean as it grows (the user asked for it, 2026-10-24):

- **One responsibility per type and per file.** A type that keeps state, reads input and draws is three types. A file past about 300 lines is a sign to split by responsibility, into a folder.
- **Math and rules are plain values**, apart from views, AppKit and Metal: cameras, transforms, hit tests, edits are structs or extensions that tests can run (`OrbitCamera`, `ViewTransform2D`, `RoadHitTest`, `RoadEdits`).
- **Views are thin.** A Metal view turns events into calls on a controller or a tool and draws through a renderer. A SwiftUI view reads state and calls the session or the editor.
- **Open for extension**: a new tool is a new `RoadToolHandler`, a new mode a new view and panel, not a new branch in a switch spread over files.
- **One source of truth.** A format, a constant or a rule lives once: the road document's format and the markings' constants are TileKit's, the app uses them.
- **No hidden globals.** What a function reads or writes comes in as a parameter (`WorkspacePaths`), not a mutable global.
- **Names** follow Swift's: types, targets, source folders and files in UpperCamelCase (a file named after the type it holds), everything else in lowerCamelCase, local constants too (no `A`, `X`). The one lowercase name is a program run from the terminal (`tilepipeline`), set by the executable product, not the target. Shell scripts are lowercase (`make_app.sh`).
- **Tests** (`Tests/`, swift-testing) cover the plain parts. A new rule of geometry, editing or a camera comes with a test.

## Commands

```sh
swift build -c release            # or open the folder (Package.swift) in Xcode: there is no .xcodeproj
./make_app.sh                     # build/Immersive Map Editor.app, tilepipeline inside it
TP=.build/release/tilepipeline    # run in the workspace, or give --root
$TP build 15 --tiles 19808/10243 19810/10243     # fetch, seed roads, build, validate (or Z X Y, or Z X0 Y0 X1 Y1)
$TP lab data/15_19808_10243 OUT [--region CX CY HALF | --whole] [--export] [--samples N] [--roads FILE]
$TP fetch 15 19808 10243 [--force]
$TP seed 15 19808 10242 19809 10243 [--force]    # never over hand edits without --force
$TP validate out/tiles/15/19808/10243
$TP fit detsky-mir
.build/release/ImmersiveMapEditor [WORKSPACE | ROAD DOCUMENT]
.build/release/ImmersiveMapEditor --resave IN OUT
.build/release/ImmersiveMapEditor --snapshot WORKSPACE OUT.png X/Y...
.build/release/ImmersiveMapEditor --map-snapshot WORKSPACE OUT.png
```

The package needs macOS 15 and Swift tools 6.0 (in the Swift 5 language mode). In Xcode, use the shared schemes in `.swiftpm/xcode/xcshareddata/xcschemes/` (`ImmersiveMapEditor`, `ImmersiveMapEditor-Package`): they keep code coverage off, because GEOS comes as a dynamic library of a dependency and fails to link when Xcode instruments it for coverage (`___llvm_profile_runtime`), which Xcode does to every target once coverage is on. Do not turn it back on. The first build compiles GEOS from source (about a minute). With no argument the app opens the workspace opened last, else `~/Desktop/TilePipeline`. Started from the Finder, macOS asks once for access to the Desktop folder.

## Planned

- Port GEOS (from JTS, for its licence) and osm2streets to Swift as targets of this package, with proven parity: `Docs/PortingGoal.md` is the task.

## History

- 2026-10-24: the pipeline ported from TilePipeline's Python and Blender to Swift, then the Python removed. Checked on 15/19808/10243 against the Python build: the same triangles of every kind but walls and roofs (6 and 3 more of 205 thousand, from triangulating concave faces), the same landmark windows, roads, markings and shelters, the light map within 0.001 per channel, the seeded road document the same but one point of 22 thousand, the fitted Detsky Mir the same. A tile builds in 10 to 20 s, three to five times faster.
