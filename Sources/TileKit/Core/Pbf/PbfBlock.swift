import Foundation

/// One decompressed `PrimitiveBlock` of an OSM PBF file, its elements handed
/// to a visitor one by one: its string table, its granularity and offsets,
/// then its groups (plain nodes, dense nodes, ways, relations). An element's
/// tags are handed as a function that builds them, so only the elements a
/// visitor keeps cost their strings: called during the visit, never kept,
/// since it reads the block's bytes.
struct PbfBlock {
    /// Which kinds the visitor wants: the groups of the others are skipped
    /// without being read.
    struct Kinds: OptionSet {
        let rawValue: Int
        static let nodes = Kinds(rawValue: 1), ways = Kinds(rawValue: 2), relations = Kinds(rawValue: 4)
        static let all: Kinds = [.nodes, .ways, .relations]
    }

    /// What a visitor is handed.
    struct Visitor {
        var node: (_ id: Int64, _ lat: Double, _ lon: Double, _ tags: () -> Tags) -> Void = { _, _, _, _ in }
        var way: (_ id: Int64, _ refs: [Int64], _ tags: () -> Tags) -> Void = { _, _, _ in }
        var relation: (_ id: Int64, _ members: () -> [OsmMember], _ memberRefs: [(isWay: Bool, isNode: Bool, ref: Int64)],
                       _ tags: () -> Tags) -> Void = { _, _, _, _ in }
    }

    /// The kinds of element a block holds and its lowest and highest id of
    /// each, from a first read of it, for skipping it later.
    struct Summary {
        var kinds: Kinds = []
        var lowest: Int64 = .max
        var highest: Int64 = .min
        mutating func saw(_ kind: Kinds, _ id: Int64) {
            kinds.insert(kind)
            lowest = min(lowest, id)
            highest = max(highest, id)
        }
    }

    /// Reads the block's elements of `kinds` into the visitor.
    static func read(_ block: [UInt8], kinds: Kinds, visitor: Visitor) throws {
        try block.withUnsafeBufferPointer { bytes in
            var r = ProtoReader(bytes)
            var strings: [Range<Int>] = []
            var groups: [Range<Int>] = []
            var granularity: Int64 = 100, latOffset: Int64 = 0, lonOffset: Int64 = 0
            while r.more {
                let f = try r.field()
                switch f.number {
                case 1:
                    var table = try r.message()
                    while table.more {
                        let g = try table.field()
                        if g.number == 1 { strings.append(try table.range()) } else { try table.skip(g.wire) }
                    }
                case 2: groups.append(try r.range())
                case 17: granularity = try r.int()
                case 19: latOffset = try r.int()
                case 20: lonOffset = try r.int()
                default: try r.skip(f.wire)
                }
            }
            var cache = [String?](repeating: nil, count: strings.count)
            func string(_ i: Int) -> String {
                guard i >= 0, i < strings.count else { return "" }
                if let s = cache[i] { return s }
                let s = r.string(strings[i])
                cache[i] = s
                return s
            }
            func degrees(_ v: Int64, _ offset: Int64) -> Double { Double(offset + granularity * v) * 1e-9 }
            func tags(_ keys: [Int], _ values: [Int]) -> () -> Tags {
                {
                    var out: Tags = [:]
                    for (k, v) in zip(keys, values) { out[string(k)] = string(v) }
                    return out
                }
            }
            func indices(_ reader: inout ProtoReader) throws -> [Int] {
                var out: [Int] = []
                try reader.packed { out.append(Int(try $0.varint())) }
                return out
            }

            for group in groups {
                var g = ProtoReader(bytes, from: group.lowerBound, to: group.upperBound)
                while g.more {
                    let f = try g.field()
                    switch f.number {
                    case 1 where kinds.contains(.nodes):
                        var n = try g.message()
                        var id: Int64 = 0, lat: Int64 = 0, lon: Int64 = 0, keys: [Int] = [], values: [Int] = []
                        while n.more {
                            let h = try n.field()
                            switch h.number {
                            case 1: id = try n.sint()
                            case 2: keys = try indices(&n)
                            case 3: values = try indices(&n)
                            case 8: lat = try n.sint()
                            case 9: lon = try n.sint()
                            default: try n.skip(h.wire)
                            }
                        }
                        visitor.node(id, degrees(lat, latOffset), degrees(lon, lonOffset), tags(keys, values))
                    case 2 where kinds.contains(.nodes):
                        try dense(try g.message(), visitor: visitor, degrees: { degrees($0, latOffset) }, longitude: { degrees($0, lonOffset) },
                                  string: string)
                    case 3 where kinds.contains(.ways):
                        var w = try g.message()
                        var id: Int64 = 0, keys: [Int] = [], values: [Int] = [], refs: [Int64] = []
                        while w.more {
                            let h = try w.field()
                            switch h.number {
                            case 1: id = try w.int()
                            case 2: keys = try indices(&w)
                            case 3: values = try indices(&w)
                            case 8:
                                var last: Int64 = 0
                                try w.packed { last += try $0.sint(); refs.append(last) }
                            default: try w.skip(h.wire)
                            }
                        }
                        visitor.way(id, refs, tags(keys, values))
                    case 4 where kinds.contains(.relations):
                        var m = try g.message()
                        var id: Int64 = 0, keys: [Int] = [], values: [Int] = [], roles: [Int] = [], refs: [Int64] = [], types: [Int] = []
                        while m.more {
                            let h = try m.field()
                            switch h.number {
                            case 1: id = try m.int()
                            case 2: keys = try indices(&m)
                            case 3: values = try indices(&m)
                            case 8: try m.packed { roles.append(Int(try $0.int())) }
                            case 9:
                                var last: Int64 = 0
                                try m.packed { last += try $0.sint(); refs.append(last) }
                            case 10: types = try indices(&m)
                            default: try m.skip(h.wire)
                            }
                        }
                        let count = min(refs.count, types.count)
                        let memberRefs = (0..<count).map { (isWay: types[$0] == 1, isNode: types[$0] == 0, ref: refs[$0]) }
                        let members: () -> [OsmMember] = {
                            (0..<count).map { i in
                                OsmMember(type: types[i] == 0 ? "node" : types[i] == 1 ? "way" : "relation", ref: refs[i],
                                          role: i < roles.count ? string(roles[i]) : "")
                            }
                        }
                        visitor.relation(id, members, memberRefs, tags(keys, values))
                    default:
                        try g.skip(f.wire)
                    }
                }
            }
        }
    }

    /// A `DenseNodes` group: ids, latitudes and longitudes delta-coded in
    /// three packed arrays, the tags of all of them in one array of key and
    /// value indices, each node's ended by a 0.
    private static func dense(_ message: ProtoReader, visitor: Visitor, degrees: (Int64) -> Double, longitude: (Int64) -> Double,
                              string: @escaping (Int) -> String) throws {
        var d = message
        var ids: [Int64] = [], lats: [Int64] = [], lons: [Int64] = [], keysValues: [Int] = []
        while d.more {
            let f = try d.field()
            switch f.number {
            case 1:
                var last: Int64 = 0
                try d.packed { last += try $0.sint(); ids.append(last) }
            case 8:
                var last: Int64 = 0
                try d.packed { last += try $0.sint(); lats.append(last) }
            case 9:
                var last: Int64 = 0
                try d.packed { last += try $0.sint(); lons.append(last) }
            case 10:
                try d.packed { keysValues.append(Int(try $0.varint())) }
            default:
                try d.skip(f.wire)
            }
        }
        guard ids.count == lats.count, ids.count == lons.count else { throw ProtoReader.Damaged() }
        var at = 0
        for i in 0..<ids.count {
            // This node's pairs in keysValues: from `at` to its closing 0
            // (no array at all when no node of the group has a tag).
            let start = at
            if !keysValues.isEmpty {
                while at < keysValues.count, keysValues[at] != 0 { at += 2 }
            }
            let stop = min(at, keysValues.count)
            if !keysValues.isEmpty { at += 1 }
            let tags: () -> Tags = {
                var out: Tags = [:]
                for j in stride(from: start, to: stop - 1, by: 2) {
                    out[string(keysValues[j])] = string(keysValues[j + 1])
                }
                return out
            }
            visitor.node(ids[i], degrees(lats[i]), longitude(lons[i]), tags)
        }
    }
}
