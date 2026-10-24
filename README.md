# Immersive Map Editor

<img src="Icon/AppIcon.png" width="128" alt="Immersive Map Editor">

A native macOS tool for the content of the ImmersiveMap engine: Swift, AppKit, SwiftUI, Metal.

- **Map**: pick map tiles on OpenStreetMap, fetch their OSM data and build them with TilePipeline.
- **Roads**: edit the road document of a range of map tiles by hand. Move, add and delete points, straighten edges, round corners, simplify, add or cut roadway. Place, move and rotate zebras, lane lines, bus stop zigzags, bus lane letters and bus shelters.
- **Tiles 3D**: look at the tiles picked as the engine draws them, together, orbiting or flying (W A S D).

```sh
./make_app.sh       # build/Immersive Map Editor.app
```

Requires macOS 14 and Xcode's Swift toolchain. The tiles and road documents come from TilePipeline.

## License

MIT, as the engine. See `LICENSE`.
