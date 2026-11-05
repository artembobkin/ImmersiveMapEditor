import Foundation

/// What the first version of the editor shows of itself (the user,
/// 2026-11-05: the landmarks' models alone, exported and archived; the
/// roads and the lighting kept in the code, hidden from the window, for
/// later). Each flag hides a whole area: its view and tab, its panel, its
/// actions and its part of a build.
enum Features {
    /// The Roads view, the seeding of road documents and the roads of a build.
    static let roads = false
    /// The lighting: the Preview's shading, modifiers, sun, quality and Bake.
    static let lighting = false
}
