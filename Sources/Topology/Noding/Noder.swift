/// Nodes segment strings: JTS's `Noder`.
public protocol Noder: AnyObject {
    func computeNodes(_ segStrings: [SegmentString]) throws
    func getNodedSubstrings() -> [SegmentString]
}
