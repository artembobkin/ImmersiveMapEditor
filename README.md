# Immersive Map Editor

<img src="Icon/AppIcon.png" width="128" alt="Immersive Map Editor">

A native macOS tool for the content of the ImmersiveMap engine: Swift, AppKit, SwiftUI, Metal. It holds the tile pipeline too (`tilepipeline`): OpenStreetMap to one 3D model per map tile, all in Swift, with its own geometry (`Topology`, a Swift port of the JTS Topology Suite), its own road reconstruction (`Streets`, a Swift port of osm2streets) and Metal ray tracing for the light map. The package has no dependencies.

- **Map**: pick map tiles on OpenStreetMap, fetch their OSM data and build them with TilePipeline.
- **Roads**: edit the road document of a range of map tiles by hand. Move, add and delete points, straighten edges, round corners, simplify, add or cut roadway. Place, move and rotate zebras, lane lines, bus stop zigzags, bus lane letters and bus shelters.
- **Tiles 3D**: look at the tiles picked as the engine draws them, together, orbiting or flying (W A S D).

```sh
./make_app.sh       # build/Immersive Map Editor.app
```

Open `Package.swift` in Xcode (File > Open, the folder) or build with `swift build -c release`. Requires macOS 15 on Apple silicon and Xcode's Swift toolchain. The work (OSM data, road documents, landmark models, built tiles) lives in a TilePipeline folder.

## License

MIT, as the engine. See `LICENSE`.

The ports of other projects keep their own licences, each in its source folder:

- `Topology`: JTS Topology Suite 1.20.0, EDL-1.0 (`Sources/Topology/LICENSE`). Its translations of libc++'s sorts, heap, hash table and red-black tree (the orders GEOS 3.13 keeps, which the port reproduces) are under the Apache License 2.0 with LLVM Exceptions (`Sources/Topology/LICENSE-LLVM`).
- `Earcut`: earcutr 0.4.3, ISC (`Sources/Earcut/LICENSE`).
- `GeoAlgorithms`: geo 0.27, geo-types 0.7, rstar, polylabel and petgraph where used, MIT (`Sources/GeoAlgorithms/LICENSE`).
- `StreetGeom` (geom, rev `9bb49fc`), `OSMReader` (osm-reader, rev `7892405`), `CountryBoundaries` (country-boundaries 1.2.0) and `Streets` (osm2streets, streets_reader and osm2lanes, rev `fc119c4`): Apache-2.0 (each folder's `NOTICE`). The boundary data `CountryBoundaries` carries is © OpenStreetMap contributors, under the ODbL 1.0.
- `MuvLanes`: Muv's lane reading (muv-osm, rev `2404d40`), MPL-2.0, a file-level licence: those files stay under the MPL, the rest of the package is MIT. It also carries MIT translations of rustc-hash, hashbrown and opening-hours-syntax (`Sources/MuvLanes/LICENSE`).
