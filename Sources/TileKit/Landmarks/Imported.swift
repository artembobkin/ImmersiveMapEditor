import Foundation
import Geometry
import GLTF

/// Landmarks: the hand-made models of ~/Desktop/Modeling, read only, never
/// changed there, and the downloaded models of landmarks/models/ (fitted to
/// OSM by the fit tool), each fitted to the tile by hand through its recipe
/// in landmarks/models.json. Every model has a `placement.json` (its GLB,
/// the coordinate of its origin and the OSM elements it replaces) and a GLB
/// in metres around that origin.
///
/// A model whose origin lies within `modelReach` of the work area is brought
/// into the tile the way the engine's baker places it: its origin moved to
/// its coordinate, its metres scaled by the Mercator scale there against the
/// tile's, standing on the ground. The OSM buildings it replaces are left
/// out of the procedural build.
///
/// The model is repainted in the tile's palette, no atlas:
///
/// - Faces are grouped into panels (neighbours turned less than about 25
///   degrees from each other), and each panel takes the colour that covers
///   most of it in the model's atlas (the wall around a window, not the
///   window), replaced by the nearest of the palette's landmark colours, the
///   same in every tile, or by the one glass colour. The recipe can repaint
///   a colour by hand. A panel never breaks into a mosaic of triangles.
/// - The windows the atlas draws on a flat wall become geometry, as an
///   ordinary building's: a recess `windowDepth` deep, its reveals and glass
///   in tones of the wall. Where the windows do not come out whole, the
///   facade's rhythm does: a window where the atlas's dark columns and rows
///   cross, on the model's own bays and storeys. Then the model's geometry:
///   windows between its pilasters, on the storeys its cornices mark. A wall
///   with none of these gets the bays its recipe gives, measured by hand from
///   the model's previews (bays: pitch, storey, window, plinth), or else the
///   ordinary building's grid (fill_windows), so every facade reads as one.
///   On a skyscraper the glass is bright blue.
/// - Each face takes its colour's .lit, .side or .shade tone by where it
///   looks, as every wall of the tile does.
public enum Imported {
    static let modelReach = 400.0
    /// Glass in the models' atlases: blue and teal greys, all painted lm_glass.
    static let glass: [(Int, Int, Int)] = [(126, 157, 176), (92, 126, 142), (72, 100, 116), (142, 176, 186),
                                           (104, 138, 152), (150, 182, 176), (96, 150, 150)]
    /// Cosine: neighbours turned less than about 25 degrees from each other
    /// are one panel, so a low-poly dome or vault is one surface, not a mosaic
    /// of facets.
    static let panelAngle = 0.9
    static let flatCosine = 0.9995      // faces of one flat wall, for its windows
    static let windowGrid = 0.2         // metres between the samples of a wall's atlas
    static let windowDepth = 0.22
    static let pierReach = 1.5          // metres in front of a wall where its pilasters and cornices are looked for
    static let mullion = 1              // grid cells: bars between panes this thin are closed over
    static let windowSize = ((0.5, 5.0), (0.7, 6.0))    // width, height ranges of a window, metres
    static let roofFace = 12.0          // m²: a glass face looking up this large is a roof, not glass
    static let skyscraper = 100.0       // metres: a taller model has bright blue glass
    static let kind = "landmarks"

    /// One face of a model in the tile's metres.
    public final class Face {
        public var corners: [V3] = []
        public var uvs: [P2]?
        public var image: String?
        public var colour: (Int, Int, Int) = (200, 200, 200)
        public var area = 0.0
        public var normal = V3.zero
    }

    /// A model read, repainted and ready to build.
    public struct Model {
        public let id: String
        public let origin: P2
        public let faces: [Face]
        let images: [String: GLTF.Image]
        public let family: [String]
        let windows: Bool
        let fill: Bool
        let bays: [String: Any]?
        let glass: String?
    }

    struct Placement {
        let id: String
        let glb: URL
        let origin: P2
        let latitude: Double
        let altitude: Double
        let replaces: Set<String>
    }

    // MARK: The landmarks of a tile

    /// The models near `work`, read and repainted, ready to build, the OSM
    /// elements they replace, and what they cover in plan.
    public static func load(_ tile: Tile, _ work: Geometry, _ paths: WorkspacePaths)
        -> (models: [Model], replaced: Set<String>, covered: Geometry) {
        let book = recipes(paths)
        var models: [Model] = []
        var replaced = Set<String>()
        for place in placements(tile, work, paths) {
            guard let (faces, images) = try? readModel(place, tile) else {
                print("[landmarks] cannot read \(place.glb.path)")
                continue
            }
            let recipe = recipe(place.id, book)
            let colours = recipe["colours"] as? [String: String] ?? [:]
            replaced.formUnion(place.replaces)
            let group = groups(faces, panelAngle)
            // Votes per panel, in the order the colours came, so a tie goes
            // to the first.
            var votes: [Int: [(String, Double)]] = [:]
            for (f, g) in zip(faces, group) {
                let atlas = family(f.colour)
                let fam = colours[atlas] ?? atlas
                var list = votes[g] ?? []
                if let k = list.firstIndex(where: { $0.0 == fam }) { list[k].1 += f.area } else { list.append((fam, f.area)) }
                votes[g] = list
            }
            var chosen: [Int: String] = [:]
            for (g, list) in votes {
                var best = list[0]
                for v in list.dropFirst() where v.1 > best.1 { best = v }
                chosen[g] = best.0
            }
            var fam = group.map { chosen[$0]! }
            // A roof the atlas paints blue-grey is not glass: the recipe's
            // flat_glass repaints each plane holding a large glass face looking
            // up (a roof, a slope), while the small facets of a dome or a vault
            // stay glass.
            if let flatGlass = recipe["flat_glass"] as? String {
                let planes = groups(faces, flatCosine, samePlane: true)
                var roofs = Set<Int>()
                for i in faces.indices where fam[i] == "lm_glass" && faces[i].normal.z > 0.05 && faces[i].area > roofFace {
                    roofs.insert(planes[i])
                }
                for (i, g) in planes.enumerated() where fam[i] == "lm_glass" && roofs.contains(g) { fam[i] = flatGlass }
            }
            // glass_below: real glass only up to this height, above it the
            // atlas's blue-grey is an attic or a roof, painted flat_glass.
            if let below = (recipe["glass_below"] as? NSNumber)?.doubleValue {
                let top = Level.ground + below
                let glassFaces = faces.indices.filter { fam[$0] == "lm_glass" }
                // Above glass_below only a dome stays glass: the glass within
                // dome_radius of the model's highest glass, in plan.
                var dome = Set<Int>()
                if !glassFaces.isEmpty, let radius = (recipe["dome_radius"] as? NSNumber)?.doubleValue, radius != 0 {
                    var peak = glassFaces[0]
                    for i in glassFaces where faces[i].corners.map(\.z).max()! > faces[peak].corners.map(\.z).max()! { peak = i }
                    func middle(_ f: Face) -> P2 {
                        P2(f.corners.map(\.x).reduce(0, +) / Double(f.corners.count),
                           f.corners.map(\.y).reduce(0, +) / Double(f.corners.count))
                    }
                    let p = middle(faces[peak])
                    for i in glassFaces where (middle(faces[i]) - p).length <= radius { dome.insert(i) }
                }
                for i in glassFaces where !dome.contains(i) && faces[i].corners.map(\.z).min()! > top {
                    fam[i] = recipe["flat_glass"] as? String ?? "lm_stone"
                }
            }
            let height = faces.isEmpty ? 0 : faces.flatMap { $0.corners.map(\.z) }.max()! - Level.ground
            let sky = recipe["skyscraper"] as? Bool ?? (height > skyscraper)
            models.append(Model(id: place.id, origin: place.origin, faces: faces, images: images, family: fam,
                                windows: recipe["windows"] as? Bool ?? true, fill: recipe["fill_windows"] as? Bool ?? true,
                                bays: recipe["bays"] as? [String: Any], glass: sky ? "lm_sky_glass" : nil))
        }
        // What the models cover in plan: an OSM building standing mostly under
        // a model is the model's too, listed in its `replaces` or not.
        var cover: [Geometry] = []
        for m in models {
            for f in m.faces where abs(f.normal.z) > 0.2 && f.corners.count >= 3 {
                cover.append(Geometry.polygon(f.corners.map { P2($0.x, $0.y) }).buffer(0.05))
            }
        }
        print("[landmarks] \(models.count) models: \(models.map(\.id).joined(separator: ", "))")
        return (models, replaced, .unaryUnion(cover))
    }

    /// The models with a face in `work`, in the tile's mesh: their flat walls
    /// with the atlas's windows as recesses, the rest face by face. Returns
    /// the faces made, the windows and the windows by model and by how they
    /// were found.
    public static func build(_ b: Builder, _ models: [Model], _ work: Geometry, region: Geometry? = nil)
        -> (made: Int, windows: Int, byModel: [String: [String: Int]]) {
        let (x0, y0, x1, y1) = work.bounds
        var made = 0, windows = 0
        var byModel: [String: [String: Int]] = [:]
        let landmarkNames = Set(Palette.landmark.map(\.0))
        for m in models {
            let faces = m.faces, family = m.family
            if faces.allSatisfy({ $0.corners.allSatisfy { $0.x < x0 || $0.x > x1 || $0.y < y0 || $0.y > y1 } }) { continue }
            var done = Set<Int>()
            if let region { b.whole = region.contains(m.origin) ? .whole : .foreign }
            if m.windows {
                let flat = groups(faces, flatCosine, samePlane: true)
                var walls: [Int: [Int]] = [:]
                var order: [Int] = []
                for (i, g) in flat.enumerated() {
                    if walls[g] == nil { order.append(g) }
                    walls[g, default: []].append(i)
                }
                for g in order {
                    let members = walls[g]!
                    var cover: [(String, Double)] = []
                    for i in members {
                        if let k = cover.firstIndex(where: { $0.0 == family[i] }) {
                            cover[k].1 += faces[i].area
                        } else {
                            cover.append((family[i], faces[i].area))
                        }
                    }
                    var best = cover[0]
                    for c in cover.dropFirst() where c.1 > best.1 { best = c }
                    let fam = best.0
                    // Glass, faces already repainted as a model's own window,
                    // or a colour of the tile's own (a roof) with no window tones.
                    if !landmarkNames.contains(fam) { continue }
                    var wall = wallWindows(members.map { faces[$0] }, m.images)
                    var how = "atlas"
                    if wall == nil && m.fill {
                        wall = geometryWindows(faces, members)
                        how = "geometry"
                    }
                    if wall == nil && m.fill {
                        // The atlas's windows did not read: the ordinary
                        // building's grid, so the facade reads as one.
                        wall = gridWindows(members.map { faces[$0] }, m.bays)
                        how = m.bays != nil ? "bays" : "grid"
                    }
                    guard let wall else { continue }
                    made += buildWall(b, wall, fam, m.glass, kind)
                    windows += wall.rects.count
                    var count = byModel[m.id] ?? ["atlas": 0, "grid": 0]
                    count[how, default: 0] += wall.rects.count
                    byModel[m.id] = count
                    done.formUnion(members)
                }
            }
            for (i, f) in faces.enumerated() where !done.contains(i) {
                let fam = family[i]
                let n = fam == "lm_glass" ? b.flat(f.corners, m.glass ?? fam, kind) : b.sided(f.corners, fam, kind)
                if n > 0 { made += 1 }
            }
        }
        if region != nil { b.whole = .cut }
        return (made, windows, byModel)
    }
}
