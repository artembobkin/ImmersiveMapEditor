/// Operations on coordinate sequences: JTS's `CoordinateSequences` (a
/// sequence is an array of coordinates here).
public enum CoordinateSequences {
    /// The index of the least coordinate in `from...to`, the first of equals.
    public static func minCoordinateIndex(_ seq: [Coordinate], _ from: Int, _ to: Int) -> Int {
        var minIndex = -1
        var minCoord: Coordinate?
        if from <= to {
            for i in from...to where minCoord == nil || minCoord!.compareTo(seq[i]) > 0 {
                minCoord = seq[i]
                minIndex = i
            }
        }
        return minIndex
    }

    /// Turns the sequence so it starts at `first`, closing a ring again.
    public static func scroll(_ seq: inout [Coordinate], _ first: Int, ensureRing: Bool) {
        if first <= 0 { return }
        let copy = seq
        let last = ensureRing ? seq.count - 1 : seq.count
        for j in 0..<last { seq[j] = copy[(first + j) % last] }
        if ensureRing { seq[last] = seq[0] }
    }

    /// Whether it is a ring: empty, or closed with at least four points.
    public static func isRing(_ seq: [Coordinate]) -> Bool {
        let n = seq.count
        if n == 0 { return true }
        if n <= 3 { return false }
        return seq[0].x == seq[n - 1].x && seq[0].y == seq[n - 1].y
    }
}
