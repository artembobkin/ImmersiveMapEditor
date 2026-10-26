import AppKit
import SwiftUI
import TileKit

/// The Style view: the palette every build paints with, colour by colour,
/// with the tones derived from each (lit, side and shade by the sun, the
/// window reveals and glass), and a picker to change it. A change is saved
/// to the data folder's palette at once; a tile shows it when built again.
struct StyleView: View {
    @Environment(Session.self) private var session

    var body: some View {
        let _ = session.palette.revision
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Palette.defaults, id: \.group) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.group).font(.title3.bold())
                        Text(Self.about[group.group] ?? "").font(.callout).foregroundStyle(.secondary)
                        ForEach(group.colours, id: \.0) { colour in
                            ColourRow(name: colour.0, defaultHex: colour.1, group: group.group)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Glass").font(.title3.bold())
                    Text("The map's one glass and a tower's bright glass, flat, not sided.").font(.callout).foregroundStyle(.secondary)
                    ForEach(["lm_glass", "lm_sky_glass"], id: \.self) { name in
                        HStack(spacing: 10) {
                            Swatch(hex: Palette.hex(name) ?? "#000000", size: CGSize(width: 44, height: 28))
                            Text(name).font(.system(.body, design: .monospaced)).frame(width: 150, alignment: .leading)
                            Text(Palette.hex(name) ?? "").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static let about = [
        "Roads and ground": "The roadway and its markings, the kerb, the roofs and the rims that outline every building from above, the plinths.",
        "Walls": "The plaster family of the typical house, brick, the modern grey, and the box of every other building. Each wall has a lit, a side and a shade tone by the sun, and its windows' reveals and glass in tones of its own.",
        "Props": "Construction sites and street things, sided like walls.",
        "Landmarks": "The colours a landmark's model is painted in, the same in every tile, sided like walls, with window tones.",
    ]
}

/// One colour: its swatch, its name, the tones derived from it, and the
/// picker and hex to change it.
private struct ColourRow: View {
    let name: String
    let defaultHex: String
    let group: String
    @Environment(Session.self) private var session
    @State private var typed = ""

    var hex: String { PaletteEdits.colour(name) ?? defaultHex }
    var changed: Bool { session.palette.colours[name] != nil }

    /// The derived tones to show: the sides of a wall, prop or landmark
    /// colour, with a wall's reveal and glass, or the roof's slopes.
    var tones: [(String, String)] {
        let sided = group == "Walls" || group == "Props" || group == "Landmarks"
        var out: [(String, String)] = []
        if sided {
            for side in ["lit", "side", "shade"] { if let h = Palette.hex("\(name).\(side)") { out.append((side, h)) } }
            if group != "Props" {
                if let h = Palette.hex("\(name).reveal.side") { out.append(("reveal", h)) }
                if let h = Palette.hex("\(name).glass.side") { out.append(("glass", h)) }
            }
        } else if name == "roof" {
            for side in ["lit", "side", "shade"] { if let h = Palette.hex("roof.\(side)") { out.append((side, h)) } }
        }
        return out
    }

    var body: some View {
        HStack(spacing: 10) {
            Swatch(hex: hex, size: CGSize(width: 44, height: 28))
            Text(name).font(.system(.body, design: .monospaced)).frame(width: 150, alignment: .leading)
            ColorPicker("", selection: Binding(get: { Self.color(hex) }, set: { session.palette.set(name, Self.hex($0)) }), supportsOpacity: false)
                .labelsHidden()
            TextField("#RRGGBB", text: Binding(get: { typed.isEmpty ? hex : typed }, set: { typed = $0 }))
                .font(.system(.body, design: .monospaced))
                .frame(width: 90)
                .onSubmit {
                    let t = typed.trimmingCharacters(in: .whitespaces).uppercased()
                    let h = t.hasPrefix("#") ? t : "#" + t
                    if h.count == 7, Int(h.dropFirst(), radix: 16) != nil { session.palette.set(name, h) }
                    typed = ""
                }
            if changed {
                Button("Reset") { session.palette.reset(name) }.controlSize(.small)
                    .help("Back to the default \(defaultHex)")
            }
            HStack(spacing: 6) {
                ForEach(tones, id: \.0) { tone in
                    VStack(spacing: 2) {
                        Swatch(hex: tone.1, size: CGSize(width: 22, height: 18))
                        Text(tone.0).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, 8)
            Spacer()
        }
    }

    static func color(_ hex: String) -> Color {
        let (r, g, b) = Palette.rgb(hex)
        return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }

    static func hex(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}

private struct Swatch: View {
    let hex: String
    let size: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(ColourRow.color(hex))
            .frame(width: size.width, height: size.height)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.15)))
    }
}
