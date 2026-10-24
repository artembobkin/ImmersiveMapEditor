import Foundation

/// A thing that can be selected.
enum Item: Hashable {
    /// A point of an area's ring or of a line or zigzag marking.
    case vertex(Owner, ring: Int, index: Int)
    case marking(Int)
    case shelter(Int)
    case area(Int)
}

enum Owner: Hashable {
    case area(Int)
    case marking(Int)
}

extension Set where Element == Item {
    var areas: [Int] { compactMap { if case .area(let a) = $0 { a } else { nil } } }
    var markings: [Int] { compactMap { if case .marking(let m) = $0 { m } else { nil } } }
    var shelters: [Int] { compactMap { if case .shelter(let s) = $0 { s } else { nil } } }

    /// The selected points, grouped by the ring they belong to, each group's
    /// indices sorted.
    var rings: [(Owner, Int, [Int])] {
        var groups: [String: (Owner, Int, [Int])] = [:]
        for case let .vertex(owner, ring, index) in self {
            groups["\(owner)-\(ring)", default: (owner, ring, [])].2.append(index)
        }
        return groups.values.map { ($0.0, $0.1, $0.2.sorted()) }
    }
}
