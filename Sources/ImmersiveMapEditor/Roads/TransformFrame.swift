import Foundation

/// The frame around what is selected in the Roads view, as in a drawing app:
/// its box, a handle at each corner that scales it (about the opposite
/// corner, about its centre with option), and a handle above it that turns
/// it. The Select tool takes hold of the handles, the overlay draws them,
/// both from here. None for a single point: it has nothing to scale.
struct TransformFrame {
    enum Handle: Equatable {
        case corner(Int)    // 0 south-west, 1 south-east, 2 north-east, 3 north-west
        case turn
    }

    let lo, hi: Vec2
    /// Metres a screen pixel covers: the handles keep their size on screen.
    let pixel: Double

    init?(_ plan: RoadPlan, _ selection: Set<Item>, pixel: Double) {
        if selection.count == 1, case .vertex = selection.first! { return nil }
        guard let (a, b) = plan.bounds(of: selection) else { return nil }
        // A little room around it, so the frame does not hide its edges.
        let pad = Vec2(repeating: 6 * pixel)
        lo = a - pad
        hi = b + pad
        self.pixel = pixel
    }

    var centre: Vec2 { (lo + hi) / 2 }
    var corners: [Vec2] { [lo, Vec2(hi.x, lo.y), hi, Vec2(lo.x, hi.y)] }
    /// The turning handle, above the frame's top edge.
    var turnHandle: Vec2 { Vec2(centre.x, hi.y + 28 * pixel) }
    var top: Vec2 { Vec2(centre.x, hi.y) }

    /// The handle under a point, within `reach` metres.
    func handle(at p: Vec2, reach: Double) -> Handle? {
        if (turnHandle - p).length < reach { return .turn }
        for (i, c) in corners.enumerated() where (c - p).length < reach { return .corner(i) }
        return nil
    }

    /// What a corner scales about: the corner across, or the centre.
    func pivot(of corner: Int, aboutCentre: Bool) -> Vec2 {
        aboutCentre ? centre : corners[(corner + 2) % 4]
    }
}
