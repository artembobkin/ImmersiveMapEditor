import Foundation
import TileKit

/// The budget of the search for references, and what ends it (the user,
/// 2026-11-21: the agent must not search for long; with no reference at
/// all the landmark is skipped, never modelled from nothing). Counted
/// here, in the server, where a word in the brief would only ask: so many
/// pages of search_street_photos a facade and in all, so many photos
/// looked at large, each answer saying what is left. A facade whose pages
/// are spent is modelled from OSM and the satellite view; a landmark with
/// no photo of it from any source is skipped (skip_landmark), and
/// set_recipe builds nothing for it.
extension LandmarkMCP.Server {
    /// The pages of search_street_photos one facade gets.
    static let pagesAFacade = 3
    /// The pages of search_street_photos a landmark gets in all.
    static let pagesInAll = 12
    /// The photos look_at_street_photo shows in all.
    static let looksInAll = 8

    /// Takes a page of the search of `facade` ("" the whole landmark): nil
    /// when there is one, else what to do instead of searching on.
    func spendPage(_ facade: String) -> String? {
        let all = searched.values.reduce(0, +)
        if all >= Self.pagesInAll {
            return "The search is spent (\(Self.pagesInAll) pages in all): no more street photos. " + whatNow()
        }
        if searched[facade, default: 0] >= Self.pagesAFacade {
            return "The search of \(facade.isEmpty ? "the landmark as a whole" : facade) is spent (\(Self.pagesAFacade) pages): keep the best of what you saw of it, "
                + "or leave this facade to OSM and the satellite view, plain. \(Self.pagesInAll - all) pages left for the other facades."
        }
        searched[facade, default: 0] += 1
        return nil
    }

    /// What is left of the search, for the end of an answer.
    func searchLeft(_ facade: String) -> String {
        let all = searched.values.reduce(0, +)
        return "Search left: \(max(0, Self.pagesAFacade - searched[facade, default: 0])) pages of this " + (facade.isEmpty ? "(the whole landmark)" : "facade")
            + ", \(max(0, Self.pagesInAll - all)) in all, \(max(0, Self.looksInAll - looked)) looks at one large."
    }

    /// What to do once the street search is spent, by what is kept.
    func whatNow() -> String {
        hasPhoto
            ? "Model from the photos you kept; a facade with none from OSM and the satellite view, plain."
            : "No photo of the building is kept: find_commons_photos once, then the web once (save_reference_photo, freely licensed only). "
              + "If there is still none, skip_landmark: it is not modelled from nothing, and the work on it ends there."
    }

    /// Whether a photo of the building itself is kept: a street photo or a
    /// Commons or web one. The satellite view alone is none.
    var hasPhoto: Bool {
        credited().contains { $0["file"] as? String != "satellite.jpg" }
    }

    /// The landmark given up on: marked skipped with the reason, for the
    /// editor to show red, and nothing built.
    func skipLandmark(_ args: [String: Any]) throws -> String {
        guard TileLandmark.model(in: folder) == nil else { throw Failure("it has a model already: nothing to skip") }
        guard !hasPhoto else { throw Failure("a photo of the building is kept: model it from that, a facade with none from OSM and the satellite view") }
        let reason = (args["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "no reference photo found"
        try LandmarkSkip.write(reason, in: folder)
        return "Skipped: \(reason). The editor shows it red. Your work on this landmark is done: answer that it was skipped and why. (Only this landmark: the run of the others goes on.)"
    }
}
