import Geometry
import simd

/// Vector helpers in the names the build uses.

public typealias V3 = SIMD3<Double>

public extension SIMD3 where Scalar == Double {
    var length: Double { simd_length(self) }
    var normalized: V3 { let l = simd_length(self); return l > 0 ? self / l : self }
    func dot(_ o: V3) -> Double { simd_dot(self, o) }
    func cross(_ o: V3) -> V3 { simd_cross(self, o) }
}

public extension SIMD2 where Scalar == Double {
    var length: Double { simd_length(self) }
    var normalized: P2 { let l = simd_length(self); return l > 0 ? self / l : self }
    func dot(_ o: P2) -> Double { simd_dot(self, o) }
}

public func v3(_ x: Double, _ y: Double, _ z: Double) -> V3 { V3(x, y, z) }
public func v3(_ p: P2, _ z: Double = 0) -> V3 { V3(p.x, p.y, z) }
