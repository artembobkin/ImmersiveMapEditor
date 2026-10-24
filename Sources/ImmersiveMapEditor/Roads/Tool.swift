import Foundation

/// A tool of the Roads view, with its key and its hint.
enum Tool: String, CaseIterable, Identifiable {
    case select = "Select"
    case addArea = "Add roadway"
    case cutArea = "Cut roadway"
    case line = "Line"
    case zebra = "Zebra"
    case zigzag = "Zigzag"
    case letter = "Letter A"
    case shelter = "Shelter"
    var id: String { rawValue }
    var key: String {
        switch self {
        case .select: "V"
        case .addArea: "A"
        case .cutArea: "C"
        case .line: "L"
        case .zebra: "Z"
        case .zigzag: "G"
        case .letter: "T"
        case .shelter: "B"
        }
    }
    var hint: String {
        switch self {
        case .select: "Click, shift-click or drag a box to select. Drag to move, option-drag to rotate markings. Double-click an edge to add a point."
        case .addArea, .cutArea: "Click the corners, Return or a click on the first point closes. Backspace drops the last point."
        case .line: "Click the points, Return finishes."
        case .zebra: "Drag across the road from kerb to kerb."
        case .zigzag: "Drag along the kerb, the roadway on the left of the drag."
        case .letter: "Click where the letter goes, then rotate it with [ and ]."
        case .shelter: "Click where the shelter stands, the road on its left; rotate with [ and ]."
        }
    }
}
