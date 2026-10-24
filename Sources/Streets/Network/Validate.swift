/// osm2streets's `check_invariants`: the links between roads and
/// intersections are consistent. Fails a precondition otherwise.

extension StreetNetwork {
    public func checkInvariants() {
        for r in roads.values {
            for i in r.endpoints() {
                precondition(intersections[i]!.roads.contains(r.id), "\(i) doesn't list \(r.id)")
            }
            precondition(!r.laneSpecsLTR.isEmpty, "\(r.id) has no lanes")
        }
        for i in intersections.values {
            precondition(!i.roads.isEmpty, "\(i.id) has no roads")
            for r in i.roads {
                let road = roads[r]!
                precondition(road.srcI == i.id || road.dstI == i.id, "\(i.id) contains \(r), which doesn't point to it")
            }
            for (r1, r2) in i.movements {
                precondition(i.roads.contains(r1), "\(i.id) has a movement for the wrong road \(r1)")
                precondition(i.roads.contains(r2), "\(i.id) has a movement for the wrong road \(r2)")
            }
        }
    }

    /// Applies the transformations, checking the invariants after each.
    public mutating func applyTransformationsWithInvariantChecks(_ transformations: [Transformation]) {
        for t in transformations {
            t.apply(&self)
            checkInvariants()
        }
    }
}
