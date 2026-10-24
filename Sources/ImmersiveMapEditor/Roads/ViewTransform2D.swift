import Foundation

/// How a top view of local metres lies on the screen: its centre in metres
/// and its scale in points per metre. Screen points have Y up, as metres do.
struct ViewTransform2D {
    var centre = Vec2.zero
    var scale = 1.0

    func world(_ p: CGPoint, in size: CGSize) -> Vec2 {
        centre + (Vec2(p.x, p.y) - Vec2(size.width, size.height) / 2) / scale
    }

    /// The bounds of what is in view, in metres.
    func visible(in size: CGSize) -> (Vec2, Vec2) {
        (world(.zero, in: size), world(CGPoint(x: size.width, y: size.height), in: size))
    }

    /// Showing the rectangle a..b whole, with a little room.
    mutating func frame(_ a: Vec2, _ b: Vec2, in size: CGSize) {
        centre = (a + b) / 2
        let w = max(size.width, 400), h = max(size.height, 300)
        scale = min(w / (b.x - a.x), h / (b.y - a.y)) * 0.95
    }

    /// Zoomed by `factor` about a screen point, which stays where it is.
    mutating func zoom(by factor: Double, at p: CGPoint, in size: CGSize) {
        let before = world(p, in: size)
        scale = min(max(scale * factor, 0.05), 400)
        centre += before - world(p, in: size)
    }

    /// Moved by a drag of screen points: the ground follows the pointer.
    mutating func pan(by d: CGSize) {
        centre -= Vec2(d.width, d.height) / scale
    }
}
