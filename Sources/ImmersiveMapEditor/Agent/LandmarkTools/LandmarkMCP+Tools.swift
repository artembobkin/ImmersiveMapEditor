import Foundation
import Geometry
import ImageIO
import simd
import TileKit

/// The landmark's tools as the agent sees them (their names, what they do,
/// their arguments) and each call sent to the code that answers it.
extension LandmarkMCP.Server {
    // MARK: The tools

    static let tools: [[String: Any]] = [
        ["name": "get_landmark",
         "description": "The landmark: its name, centre, and every OSM building and building:part it is made of, a line each (id, part or outline, base and height, plan size and middle in metres east and north of the centre, area, the tags that shape it), then the outline rings of the largest of them in metres: the walls, where every feature on a facade takes its line and points. Then the recipe format and the palette's colours. Read it first.",
         "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "get_outlines",
         "description": "The outline rings of some of the landmark's OSM buildings (up to 40 ids a call), in metres east and north of the centre, simplified to 0.3 m: to place features (colonnades, pediments) on the right lines, or to draw a polygon of your own.",
         "inputSchema": ["type": "object", "properties": ["ids": ["type": "array", "items": ["type": "string"]]], "required": ["ids"]]],
        ["name": "get_recipe",
         "description": "The landmark's current recipe (recipe.json), or a starter recipe made from OSM's tags when it has none yet.",
         "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "set_recipe",
         "description": "Writes the recipe and builds the model from it (model.glb). Returns the problems when it cannot build (nothing is written then), else what was built. The editor shows the model as soon as it is built.",
         "inputSchema": ["type": "object", "properties": ["recipe": ["type": "object", "description": "The whole recipe, in the format get_landmark describes."]],
                         "required": ["recipe"]]],
        ["name": "render_views",
         "description": "Renders the model (or the OSM boxes, with boxes: true) and returns the pictures, to compare with the photos. Views: from-south, from-east, from-north, from-west (eye level), from-south-west, from-north-east (a slant), from-above (north up).",
         "inputSchema": ["type": "object", "properties": [
            "views": ["type": "array", "items": ["type": "string"], "description": "Which views; four by default: from-south-west, from-north-east, from-south, from-above."],
            "boxes": ["type": "boolean", "description": "The OSM buildings as boxes instead of the model."]]]],
        ["name": "satellite_view",
         "description": "The landmark from above, from the satellite imagery (Esri World Imagery): one picture centred on it, north up, its OSM outlines in red, a grid every 20 m in metres east and north of its centre (the recipe's x and y), kept in the references. The roofs: their shapes, ridges, domes, lanterns, courtyards, and where things stand, to place shapes by the grid.",
         "inputSchema": ["type": "object", "properties": ["radius": ["type": "number", "description": "Metres around the centre; the landmark and 25 m by default."]]]],
        ["name": "compare_with_photo",
         "description": "A kept street photo beside the model rendered from the very place and with the very lens the photo was taken (its camera's pose): the photo left, the model right, one picture. The way to see what differs, facade by facade. Street photos only (Commons photos have no pose).",
         "inputSchema": ["type": "object", "properties": ["file": ["type": "string", "description": "The kept photo, photo-NN.jpg"]], "required": ["file"]]],
        ["name": "review_facade",
         "description": "One facade checked against its reference: the model beside the facade's best photo (references/<facade>/best/, the first), from the photo's own camera; its other best photos by name, show_reference for one when a detail needs it. Count what the photo shows (arches, windows, storeys, entrances, the cornice, the relief, the colours) against the model, and fix what differs. Not part of the plan (a build's own comparisons are the review): for the user's request, or a facade a build did not compare.",
         "inputSchema": ["type": "object", "properties": ["facade": ["type": "string", "description": "Its folder: north-facade, south-east-facade, ..."]], "required": ["facade"]]],
        ["name": "compare_with_satellite",
         "description": "The satellite view beside the model rendered from straight above, north up, over the same ground: the masses, roofs and courtyards against the imagery. Needs satellite_view first.",
         "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "render_from",
         "description": "The model as seen from a place of your choice: x and y metres east and north of the landmark's centre, height metres up (2 by default: eye level), heading (a compass bearing: 0 north, 90 east), pitch (degrees, up positive, 0 by default), hfov (degrees wide, 65 by default). For a look from where a Commons photo was taken, or from the square before the entrance.",
         "inputSchema": ["type": "object", "properties": ["x": ["type": "number"], "y": ["type": "number"], "height": ["type": "number"],
                                                          "heading": ["type": "number"], "pitch": ["type": "number"], "hfov": ["type": "number"]],
                         "required": ["x", "y", "heading"]]],
        ["name": "save_reference_photo",
         "description": "Downloads a photo of the landmark into its references and returns it to look at. Only freely licensed photos (Wikimedia Commons: CC BY, CC BY-SA, CC0, public domain) or the user's own: give the direct image URL (upload.wikimedia.org, a thumbnail of about 1280 px is enough), its page, author and licence, and what it shows (which side, from where).",
         "inputSchema": ["type": "object", "properties": [
            "url": ["type": "string"], "page": ["type": "string"], "author": ["type": "string"],
            "licence": ["type": "string"], "shows": ["type": "string"]],
                         "required": ["url", "page", "author", "licence", "shows"]]],
        ["name": "find_street_photos",
         "description": "The automatic walk by fixed rules, which often picks the wrong building: search_street_photos to choose yourself. Street-level photos of the landmark from Mapillary (CC BY-SA 4.0, credited when kept), judged by their camera poses against the landmark's facades (the sides of its outline): a walk around it, facade by facade and station by station along each (from beyond one end, its thirds, from beyond the other end), at each the photos standing there that show the facade best, each from another track (seven at most), each with its id, distance, which facades it shows and how much of each, how much of the frame it fills, date and author, and the facades no photo shows. Every station's photos are kept into the references at once, each into the folder of its facade (north-facade/ and so on), framed in red, the rest painted black. Needs the Mapillary token of Settings.",
         "inputSchema": ["type": "object", "properties": [
            "radius": ["type": "number", "description": "Metres around the centre, 150 by default."],
            "limit": ["type": "integer", "description": "How many at most, 140 by default: up to five stations a facade, seven photos a station."],
            "since": ["type": "string", "description": "Only the photos taken since this date (2023, 2023-06 or 2023-06-15): the building as it is now, when the kept photos are old, show scaffolding or a facade since changed. Their dates are in every list."]]]],
        ["name": "search_street_photos",
         "description": "Searches Mapillary yourself: the street photos that look at one facade (or at the landmark), a pass a line (a car's or a walker's track, its frame with the best look), the newest pass first (order: best for the best look first), a page at a time, as a contact sheet with the landmark framed in red where each photo's pose puts it, and a line each: its id, date, distance, side, how much of the facade it shows, and how sure its pose is. The photos whose compass looks away are left out unless asked for (guesses: true): then shown as if they looked at the building, a guess. Nothing is kept: look at them (the search has a budget, said with every answer: \(LandmarkMCP.Server.pagesAFacade) pages a facade, \(LandmarkMCP.Server.pagesInAll) in all), look_at_street_photo one to be sure, save_street_photo the ones that show the building as it is now. A frame on another building is a wrong pose: skip to the next ones, try another facade, a larger radius or since.",
         "inputSchema": ["type": "object", "properties": [
            "facade": ["type": "string", "description": "The facade, as list_references or get_landmark names it (north-facade, ...); all of them when left out."],
            "order": ["type": "string", "description": "newest (by default) or best."],
            "since": ["type": "string", "description": "Only photos taken since this date: 2023, 2023-06 or 2023-06-15."],
            "radius": ["type": "number", "description": "Metres around the landmark's centre: by default its farthest wall and 80 m beyond, 120 m at least."],
            "count": ["type": "integer", "description": "How many on the page, 9 by default, 16 at most."],
            "skip": ["type": "integer", "description": "How many to skip: the next page."],
            "guesses": ["type": "boolean", "description": "Also the photos whose compass looks away from the building, framed as if they looked at it, a guess: when the others give nothing for a facade."],
            "pass_of": ["type": "string", "description": "A photo's id: the frames of its pass instead, in the order taken, the ones before and after it, whatever their compasses say, with which side of its way the building is on: another angle of the same day, a few metres on."]]]],
        ["name": "skip_landmark",
         "description": "Gives the landmark up, when no photo of the building could be found from any source (Mapillary, Commons, the web): nothing is built, the editor shows it red with the reason. Not for a landmark with a photo kept, nor for one facade without a photo.",
         "inputSchema": ["type": "object", "properties": ["reason": ["type": "string", "description": "Why, in a few words: what was searched and what was missing."]], "required": ["reason"]]],
        ["name": "look_at_street_photo",
         "description": "One photo search_street_photos listed, large, the landmark framed in red where its pose puts it and nothing painted over: to judge whether it shows this building and as it is now.",
         "inputSchema": ["type": "object", "properties": ["id": ["type": "string"]], "required": ["id"]]],
        ["name": "save_street_photo",
         "description": "Keeps a street photo search_street_photos (or find_street_photos) listed, by its id, into the facade's best/ (the facade it shows best, or the one given), credited (Mapillary, its author, CC BY-SA 4.0), the landmark framed in red and the rest painted black, with its camera's pose: every build is compared with it from that pose. Returns it to look at.",
         "inputSchema": ["type": "object", "properties": ["id": ["type": "string"], "facade": ["type": "string", "description": "The facade it is kept for (north-facade, ...)."],
                                                          "shows": ["type": "string", "description": "What it shows: which side, from where."]],
                         "required": ["id", "shows"]]],
        ["name": "find_commons_photos",
         "description": "Photos of the landmark on Wikimedia Commons (freely licensed only: CC0, CC BY, CC BY-SA, public domain): the files of its category (from OSM's wikimedia_commons or wikidata tag) and the files geotagged around it, the best first (views from above and recent large ones), five at most, each with its name, size, date, author, licence and description; their pictures only with pictures: true. The whole from afar, the roofs from above, the details the street does not show. Keep one with save_commons_photo (it comes back to look at).",
         "inputSchema": ["type": "object", "properties": [
            "radius": ["type": "number", "description": "Metres around the centre for geotagged files, 150 by default."],
            "limit": ["type": "integer", "description": "How many, 5 at most and by default."],
            "pictures": ["type": "boolean", "description": "The candidates' pictures too (false by default: their descriptions alone, the pictures cost you)."]]]],
        ["name": "save_commons_photo",
         "description": "Downloads one of find_commons_photos' files by its name (File:...) into the references, credited (its author and licence), and returns it to look at.",
         "inputSchema": ["type": "object", "properties": ["file": ["type": "string"], "shows": ["type": "string", "description": "What it shows: which side, from where."]],
                         "required": ["file", "shows"]]],
        ["name": "drop_reference",
         "description": "Removes a kept reference photo that turned out not to show the landmark (its credit too).",
         "inputSchema": ["type": "object", "properties": ["file": ["type": "string"]], "required": ["file"]]],
        ["name": "show_user_picture",
         "description": "A picture the user attached to a request (a screenshot of the model or of the building, to show what to change), by its file name.",
         "inputSchema": ["type": "object", "properties": ["file": ["type": "string"]], "required": ["file"]]],
        ["name": "list_references",
         "description": "The reference photos kept, with their credits and what they show, which facades they cover and which none does, and as pictures the best street photo of each facade, the satellite view and the Commons photos.",
         "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "gather_references",
         "description": "Gathers every reference at once, no choice to make: Mapillary's street photos facade by facade (find_street_photos), the satellite view, and from Wikimedia Commons the best classic view of the whole and the best view from above, each checked for a building in it. By fixed rules that often pick the wrong building: search for the references yourself instead.",
         "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "show_reference",
         "description": "Returns one kept reference photo to look at again.",
         "inputSchema": ["type": "object", "properties": ["file": ["type": "string"]], "required": ["file"]]],
    ]

    func call(_ name: String, _ args: [String: Any]) throws -> [[String: Any]] {
        switch name {
        case "get_landmark": return [text(try landmark())]
        case "get_outlines": return [text(try outlines(args["ids"] as? [String] ?? []))]
        case "get_recipe": return [text(try recipeText())]
        case "set_recipe":
            let said = try setRecipe(args["recipe"])
            guard said.hasPrefix("Built") else { return [text(said)] }
            // The build, and at once the model beside a kept street photo
            // of each facade this recipe changed (all on the first build)
            // from that photo's place: one of its best/, the next one
            // each round, so the rounds go through all of them (a facade
            // without best/, its best look); six at most.
            var content: [[String: Any]] = [text(said)]
            var picked: [String] = []
            var compared: [String] = []
            if let scene = try? StreetScene(folder: folder) {
                let kept = keptViews(scene)
                let round = Int(currentRound.lastPathComponent) ?? 0
                let changed = lastTouched ?? Array(scene.facades.indices)
                if lastTouched != nil {
                    content.append(text(changed.isEmpty ? "The recipe changed no element: no comparison this round." : "Compared below: the facades this recipe changed, \(changed.map { scene.facades[$0].name }.joined(separator: ", ")). review_facade for any other."))
                }
                for f in changed.sorted(by: { scene.facades[$0].length > scene.facades[$1].length }) {
                    compared.append(scene.facades[f].name)
                    let best = bestPhotos(Self.facadeFolder(scene.facades[f].name))
                    if !best.isEmpty {
                        // Fine detail: two of its best each round, from two
                        // stations, so the ornament is checked from two angles
                        // (the user, 2026-11-05).
                        for k in 0..<min(best.count, Self.fine ? 2 : 1) {
                            let file = best[(round + k) % best.count]
                            if !picked.contains(file) { picked.append(file) }
                        }
                        continue
                    }
                    guard let look = kept.filter({ $0.view.seen[f] >= StreetView.enough && $0.view.looks[f] > 0 })
                        .max(by: { $0.view.looks[f] < $1.view.looks[f] }), !picked.contains(look.file) else { continue }
                    picked.append(look.file)
                }
            }
            for file in picked.prefix(Self.fine ? 10 : 6) {
                if let shown = try? compare(["file": file]) { content += shown }
            }
            if picked.isEmpty && compared.isEmpty && lastTouched == nil { content.append(text("No street photo with a camera pose is kept yet: find_street_photos keeps them, and every build will come back beside them.")) }
            if let above = try? compareSatellite() { content += above }
            return content
        case "review_facade": return try reviewFacade(args["facade"] as? String ?? "")
        case "render_views": return try render(args)
        case "save_reference_photo": return try savePhoto(args)
        case "find_street_photos": return try streetPhotos(args)
        case "compare_with_photo": return try compare(args)
        case "compare_with_satellite": return try compareSatellite()
        case "satellite_view": return try satellite(args)
        case "render_from": return try renderFrom(args)
        case "find_commons_photos": return try commonsPhotos(args)
        case "save_commons_photo": return try saveCommonsPhoto(args)
        case "drop_reference": return [text(try dropReference(args["file"] as? String ?? ""))]
        case "save_street_photo": return try saveStreetPhoto(args)
        case "search_street_photos": return try searchStreetPhotos(args)
        case "look_at_street_photo": return try lookAtStreetPhoto(args)
        case "skip_landmark": return [text(try skipLandmark(args))]
        case "list_references": return try listReferences()
        case "gather_references": return try gather()
        case "show_user_picture":
            let file = (args["file"] as? String ?? "") as NSString
            let url = folder.appendingPathComponent("requests").appendingPathComponent(file.lastPathComponent)
            guard let shown = image(url) else { throw Failure("no picture \(file) in the requests") }
            return [text("The user's picture \(file.lastPathComponent)"), shown]
        case "show_reference":
            let file = args["file"] as? String ?? ""
            guard let found = reference(file), let shown = image(found.url) else { throw Failure("no reference \(file)") }
            return [shown]
        default: throw Failure("no tool \(name)")
        }
    }
}
