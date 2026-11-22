import Foundation
import TileKit

/// The landmarks' agent, run by the user in a terminal (the user,
/// 2026-11-20: the editor no longer launches Claude Code or Codex, the
/// user runs their own `claude` or `codex` and pastes the prompt). What the
/// editor gives it: the brief (`prompt`, the system words and the first
/// request with its plan, copied from the landmark's panel) and the
/// landmark's folder set up so an agent started in it finds the editor's
/// modelling tools (`AgentSetup`). The agent finds its references itself
/// (search_street_photos, the satellite view, Commons), writes the landmark's recipe, renders
/// it and corrects it; the editor shows each model it builds as it lands.
enum LandmarkAgent {
    static let system = """
    You make stylized low-poly 3D models of real landmarks for a cartoon-style city map, through the landmark tools only (the MCP server "landmark"): \
    do not run commands or edit files yourself. Every model is a recipe of a few architectural words (get_landmark explains \
    them); the generator builds it in the map's one style and palette. Work from the landmark's OSM buildings (its \
    outlines and heights) and from the references you find yourself: the street photos of Mapillary you search and choose \
    (search_street_photos), the satellite view, and freely licensed photos of Wikimedia Commons (find_commons_photos, or \
    save_reference_photo with their author and licence); never use Google or Yandex imagery. Compare your renders with the \
    photos and correct the recipe until the silhouette, proportions, main colours and the few telling details agree. \
    Write short notes of what you do, in English.
    """

    /// The whole prompt to paste into the agent started in the landmark's
    /// folder: the system words, then the first request with its plan.
    static func prompt(_ name: String, monument: Bool, fine: Bool) -> String {
        system + "\n\n" + firstRequest(name, monument: monument, fine: fine)
    }

    /// What the agent makes in a landmark's folder, besides the photos (and
    /// what the editor's own runs of it left there before 2026-11-20: the
    /// conversation, its log, its stream and its pid).
    static let work = ["rounds", "search", "views", "recipe.json", "model.glb", LandmarkSkip.file, "agent.json", "agent.log", "agent.stream.jsonl", "agent.pid"]

    /// Whether the agent has built anything in `folder`.
    static func hasBuilt(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("rounds").path)
    }

    /// Whether the agent has made anything in `folder`.
    static func hasWork(_ folder: URL) -> Bool {
        (work + ["references"]).contains { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    /// Removes everything the agent made in `folder`: its photos, renders,
    /// recipe, model and conversation. The landmark itself (landmark.json,
    /// footprint.geojson) stays.
    static func forget(_ folder: URL) {
        for name in work + ["references"] { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
    }

    /// The first request: the brief with the plan. Every landmark is
    /// modelled in full detail (the user, 2026-10-28: no levels), and
    /// `fine` asks for the ornament too, with five fix builds (the user,
    /// 2026-11-05: the Painted Ladies as plain gabled boxes).
    static func firstRequest(_ name: String, monument: Bool = false, fine: Bool = false) -> String {
        if monument { return monumentRequest(name) }
        let level = """
            DETAIL: everything that reads from across the street: every mass of the building with its own roof, \
            the windows with the real storeys and rhythm of each facade (arched where they are arched), every entrance with \
            its portal, the plinth, string courses, the cornice with its depth, pilasters and columns where the facade has \
            them, balustrades and parapets, the sculpture, chimneys and roof lanterns, the attic and its windows. Model from \
            shapes what the words do not cover (a balustrade of cylinders in a row, a rusticated base as thin boxes, a \
            moulding as a loft). Up to \(fine ? "150 000" : "60 000") triangles (set_recipe tells the count).
            """ + (fine ? """

            FINE DETAIL, asked for this landmark: the ornament too, everything a person sees from the pavement, modelled \
            from shapes at its real size and placed from the walls' corners: every bay window as a prism (or a cylinder, \
            or a corner turret with its cone) standing proud of the wall with its own windows, base and cornice; the \
            porch with its columns, its arch or pediment, its balustrade and the stairs with their rails; the brackets \
            under the cornice and under the bays as rows of small boxes; the window surrounds with their pediments and \
            hoods; the gable's trim along its edges and its finial; the balustrades as rows of cylinders between posts; \
            the string courses between the storeys; the base's rustication; the chimneys. Count the ornament of each \
            facade in its photo and give the model the same count.
            """ : "")
        let fixes = fine ? "five" : "three"
        return """
        Make the stylized low-poly model of the landmark "\(name)" (its folder is the working directory).
        \(level)
        The plan, and the budget: one build of the whole from the references, then builds of the fixes while the \
        comparisons still show something to fix, \(fixes) of them at most, each with everything that differed, and a \
        summary. A plain building takes two builds, a rich facade \(fine ? "all of them" : "four"); never a build for a detail alone, and stop as \
        soon as a build changes little. The search for the references is yours and comes first: as many pages and looks as a \
        facade needs to find a photo of it as it is now. After it, work from what each build returns, with no renders besides.
        1. get_landmark (the building, its walls' corners in metres, the recipe format), then list_references (what is \
        kept, and the facades no photo shows). Then find the references yourself, the building as it is now: satellite_view \
        (the roofs from straight above with the OSM outlines and a grid in metres, the recipe's x and y: the roof shapes, \
        ridges, domes and lanterns, the courtyards, where the parts stand); for each facade search_street_photos (the newest \
        first, the landmark framed in red where each photo's pose puts it), look at the sheet, look_at_street_photo one you \
        are not sure of, and save_street_photo the one or two that show that facade best, square on and recent, into its \
        best/ (north-facade/best/photo-03.jpg, the path to give show_reference, compare_with_photo and drop_reference). A \
        frame on another building, a facade hidden by trees or scaffolding, or one since rebuilt: the next page, since, or \
        a larger radius. find_commons_photos for a view of the whole or from above. Every build compares with what you kept.
        The search has a budget, counted for you and said with every answer (so many pages a facade and in all): when a \
        facade's is spent, keep the best you saw of it, or model that facade from OSM and the satellite view, plain. \
        With no photo of the building at all from Mapillary, try find_commons_photos once and the web once \
        (save_reference_photo, freely licensed only); if there is still none, skip_landmark with the reason, and your work on this landmark is done: a \
        landmark is never modelled from nothing.
        A wall is one wall (the user, 2026-10-28): the building's walls are its OSM outline, and each stretch of them \
        belongs to one mass. A building of parts with different heights, windows or roofs is the one outline cut into \
        them (cuts: a line through the outline and the side to keep; the rest of it minus the parts), never a polygon of \
        your own drawn along the outline, which the build refuses. A polygon only for what OSM has no outline of (a \
        tower on the roof, a drum, a porch), clear of the walls. Tidiness before likeness: a toy is symmetrical, one \
        rhythm of windows a wall in one grid with its pilasters and bands; where the photos show irregularity, draw the \
        regular version of it.
        2. The build: write the whole recipe with set_recipe from these pictures, every facade from its best photo: \
        the masses and their roofs, the windows of each facade in their rhythm, the entrances with their portals, the \
        cornice, the plinth, the relief (pilasters, bands), the sculpture that makes it recognisable; the walls' colours \
        from the photos and the roofs' colours satellite_view read, in the palette's words. The build comes back with the \
        model rendered beside the best photo of every facade from that photo's own camera, and beside the satellite view \
        from above: that is your review. Count what each photo shows against the model (columns, windows, storeys, \
        arches, entrances, the cornice, the relief, the roof, the colours).
        3. The fixes: a set_recipe with everything that differed, all of it in one build, never one thing at a time. It \
        comes back beside the best photo of every facade it changed: count again, and build again only while a photo \
        still shows something the model lacks (a bay, a balcony stack, a storey, a roof of another shape), \(fixes) fix \
        builds at most. When a build changes little, that is the end.
        \(AgentSettings.emphasis != "off" ? """
        4. What makes it recognisable: the one or two things a person points at from afar (a sculpture, a star, a cross, a ball finial: what stands free on the building), \\
        never more. The building's own body, a tower, a dome, a cone, a drum, a portico, a platform, lettering, is never one: it is given \\
        its real size in the recipe and drawn at it, emphasis on anything but a statue, a ring or a sphere ignored and said back with the build. First ask yourself: you may know this place by its name and its OSM tags \\
        (a quadriga over a theatre's portico, a star in a ring on a store's corner, a gilded flame on a monument's tip, a \\
        crescent over a dome). Any country, any age: the words are the same. If you know it, just model \\
        it from what you know, placed by the satellite view, and open a photo only if you want to, when you lack its \\
        place or size. \\
        \(AgentSettings.emphasis == "photos" ? "Only when you do not know the building, look along the roof and at the corners of the whole-building photo for what stands there. " : "If you do not know the building, leave this step out: no photos for it. ")\\
        Model each in full in the build of the fixes, a star as a statue of shape star (in a ring shape where it \\
        has one), and mark it "emphasis": true: the generator draws it \\(String(format: "%.2g", AgentSettings.exaggeration)) times its size, \\
        larger than life, as a cartoon map does. Lettering is never one of these: solid letters that really stand on \\
        the building (on its roof or its cornice) are a text shape at their real size; a shop's signboard, a banner or \\
        an advertisement is not modelled at all.
        5.
        """ : "4.") End with a short summary: a line for each facade, what its photo shows and what the model has; then what you \
        were not sure of.
        """
    }

    /// The first request for a monument (the user, 2026-11-05: a statue, a
    /// helicopter on a pedestal, a point in OSM with no outline): no walls,
    /// no facades, the thing itself from the photos around it.
    static func monumentRequest(_ name: String) -> String {
        """
        Make the stylized low-poly model of the monument "\(name)" (its folder is the working directory).
        It is a monument, not a building: a statue, a sculpture, a vehicle or a stone on a pedestal, a point in OSM \
        with no outline. DETAIL: what a person sees from the pavement: the pedestal with its steps and mouldings, and \
        the figure or the object on it with its real silhouette (a rider and a horse, a standing person, a helicopter \
        with its rotor, tail boom and skids, an obelisk with its tip), at its real size from the photos and OSM's height. \
        Up to 20 000 triangles (set_recipe tells the count).
        The plan, and the budget: one build from the references, then a build of the fixes while the comparisons still \
        show something to fix, two of them at most, and a summary. The search for the references is yours and comes first; \
        after it, work from what each build returns.
        1. get_landmark (the plot, the recipe format: the ring it gives is the plot round the point, not a wall, and \
        nothing of it is built), then list_references, then find the references yourself: search_street_photos round it \
        (the newest first, the monument framed in red where each photo's pose puts it), look_at_street_photo one you are not \
        sure of, and save_street_photo two or three from different sides (north-facade/best/photo-03.jpg, the path to give \
        show_reference, compare_with_photo and drop_reference); satellite_view (its shadow and its base tell its footprint \
        and heading); find_commons_photos for a view of the whole. The search has a budget, said with every answer: \
        with no photo of the monument at all from Mapillary, Commons or the web (save_reference_photo, freely licensed \
        only), skip_landmark with the reason, and your work on it is done: it is never modelled from nothing.
        2. The build: set_recipe with no masses. The pedestal a box, a cylinder, a prism or a loft shape standing on \
        the ground at (0, 0), its real size; the figure on it a statue feature where one fits (figure, equestrian, \
        obelisk, cross, star, flame), marked "emphasis": true, since it is what stands free; otherwise the object \
        assembled from shapes at its real size (a loft or a sweep for a body, cylinders for booms and barrels, thin boxes \
        for blades, wings and plates, spheres), facing the heading the photos and the satellite view show. Colours in \
        the palette's words: bronze lm_dark, stone lm_stone, gilt lm_gold, a painted machine its own colours. The build \
        comes back rendered beside the best photo from each side, from that photo's own camera, and beside the \
        satellite view: that is your review. Count the parts and compare the proportions.
        3. The fixes: one set_recipe with everything that differed; build again only while a photo still shows \
        something the model lacks, two fix builds at most. End with a short summary: what the photos show, what the \
        model has, and what you were not sure of.
        """
    }
}
