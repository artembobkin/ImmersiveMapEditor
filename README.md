# Immersive Map Editor

<img src="Icon/AppIcon.png" width="128" alt="Immersive Map Editor">

A native macOS tool for the content of the ImmersiveMap engine: Swift, AppKit, SwiftUI, Metal. It holds the tile pipeline too (`ImmersiveMapEditor pipeline COMMAND`, one app, one binary): OpenStreetMap to one 3D model per map tile, all in Swift, with its own geometry (`Topology` of [SwiftTopology](https://github.com/artembobkin/SwiftTopology), a Swift port of the JTS Topology Suite), its own road reconstruction (`Streets` of [SwiftStreets](https://github.com/artembobkin/SwiftStreets), a Swift port of osm2streets) and Metal ray tracing for the light map. Those two packages, both in Swift, are its only dependencies.

- **Map**: pick map tiles on OpenStreetMap, fetch their OSM data and build them with TilePipeline.
- **Roads**: edit the road document of a range of map tiles by hand. Move, add and delete points, straighten edges, round corners, simplify, add or cut roadway. Place, move and rotate zebras, lane lines, bus stop zigzags, bus lane letters and bus shelters.
- **Tiles 3D**: look at the tiles picked as the engine draws them, together, orbiting or flying (W A S D).

```sh
./make_app.sh       # build/Immersive Map Editor.app
```

Open `Package.swift` in Xcode (File > Open, the folder) or build with `swift build -c release`. Requires macOS 15 on Apple silicon and Xcode's Swift toolchain. The work (OSM data, road documents, landmark models, built tiles) lives in a TilePipeline folder.

## License

MIT, as the engine. See `LICENSE`.

The geometry and the road reconstruction are packages of their own, with their own licences:

- [SwiftTopology](https://github.com/artembobkin/SwiftTopology): a Swift port of the JTS Topology Suite 1.20.0 that behaves as GEOS 3.13, EDL-1.0 (and the Apache License 2.0 with LLVM Exceptions for its translations of libc++).
- [SwiftStreets](https://github.com/artembobkin/SwiftStreets): a Swift port of osm2streets (rev `fc119c4`) and the libraries it stands on, Apache-2.0, ISC, MIT and, for its `MuvLanes` target, MPL-2.0 (each target's licence in its folder there).
