import Foundation

/// A thing that can be selected, by its object's id: never by a place in a
/// list, which a deletion would shift.
enum Item: Hashable {
    /// A whole object.
    case object(String)
    /// A point of an object's ring (an area's, a line's, a zigzag's).
    case vertex(String, ring: Int, index: Int)
}

extension Set where Element == Item {
    /// The ids of the whole objects selected.
    var objects: [String] { compactMap { if case .object(let id) = $0 { id } else { nil } } }

    /// The selected points, grouped by the object and ring they belong to,
    /// each group's indices sorted.
    var rings: [(String, Int, [Int])] {
        var groups: [String: (String, Int, [Int])] = [:]
        for case let .vertex(owner, ring, index) in self {
            groups["\(owner)-\(ring)", default: (owner, ring, [])].2.append(index)
        }
        return groups.values.map { ($0.0, $0.1, $0.2.sorted()) }
    }
}
