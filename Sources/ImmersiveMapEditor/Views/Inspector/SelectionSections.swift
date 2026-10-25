import SwiftUI

/// The parameters of the one selected marking or shelter, editable.
struct SelectionSections: View {
    @Bindable var model: RoadEditor

    var body: some View {
        let items = model.selection
        if items.isEmpty {
            Text("Nothing selected").foregroundStyle(.secondary)
        } else if items.count == 1, case .marking(let i) = items.first!, i < model.doc.markings.count {
            marking(i)
        } else if items.count == 1, case .shelter(let i) = items.first!, i < model.doc.shelters.count {
            Text("Shelter \(model.doc.shelters[i].id)")
            number("Heading °", { model.doc.shelters[i].heading }) { d, v in d.shelters[i].heading = v }
        } else if items.count == 1, case .area(let i) = items.first!, i < model.doc.areas.count {
            let a = model.doc.areas[i]
            Text("Area \(a.id): \(a.rings.count - 1) holes, \(a.rings.reduce(0) { $0 + $1.count }) points")
            Picker("Op", selection: Binding(get: { a.op }, set: { v in model.change("Edit") { $0.areas[i].op = v } })) {
                Text("Add roadway").tag("add")
                Text("Cut roadway").tag("cut")
            }
        } else {
            let points = items.filter { if case .vertex = $0 { true } else { false } }.count
            Text("\(items.count) selected" + (points > 0 ? ", \(points) points" : ""))
        }
    }

    @ViewBuilder
    func marking(_ i: Int) -> some View {
        let m = model.doc.markings[i]
        Text("\(m.kind.capitalized) \(m.id)")
        switch m.kind {
        case "line":
            Picker("Style", selection: Binding(get: { m.style }, set: { v in model.change("Edit") { $0.markings[i].style = v } })) {
                Text("Solid").tag("solid")
                Text("Dashed").tag("dashed")
                Text("Double").tag("double")
            }
            Picker("Colour", selection: Binding(get: { m.colour }, set: { v in model.change("Edit") { $0.markings[i].colour = v } })) {
                Text("White").tag("white")
                Text("Yellow").tag("yellow")
            }
        case "zebra":
            number("Heading °", { model.doc.markings[i].heading }) { d, v in d.markings[i].heading = v }
            number("Span m", { model.doc.markings[i].span }) { d, v in d.markings[i].span = max(1, v) }
            number("Bar m", { model.doc.markings[i].bar }) { d, v in d.markings[i].bar = max(0.1, v) }
            number("Length m", { model.doc.markings[i].length }) { d, v in d.markings[i].length = max(0.5, v) }
        case "zigzag":
            number("Step m", { model.doc.markings[i].step }) { d, v in d.markings[i].step = max(0.5, v) }
            number("Depth m", { model.doc.markings[i].depth }) { d, v in d.markings[i].depth = v }
            Button("Flip side  X") { model.change("Flip Zigzag") { $0.markings[i].side *= -1 } }
        default:
            number("Heading °", { model.doc.markings[i].heading }) { d, v in d.markings[i].heading = v }
        }
    }

    func number(_ label: String, _ get: @escaping () -> Double, _ set: @escaping (inout RoadPlan, Double) -> Void) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: Binding(get: get, set: { v in model.change("Edit") { set(&$0, v) } }),
                      format: .number.precision(.fractionLength(0...3)))
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
        }
    }
}
