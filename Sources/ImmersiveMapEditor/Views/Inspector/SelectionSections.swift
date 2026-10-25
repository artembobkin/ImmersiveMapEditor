import SwiftUI

/// What is selected in the Roads view: the one object's title and its
/// parameters (each object says which, RoadObject.parameters), else how
/// many things are. Every value is read from the object of the id as the
/// document has it now, and set as one step of undo: a deleted object shows
/// nothing and takes nothing.
struct SelectionSections: View {
    @Bindable var model: RoadEditor

    var body: some View {
        let items = model.selection
        if items.isEmpty {
            Text("Nothing selected").foregroundStyle(.secondary)
        } else if items.count == 1, case .object(let id) = items.first!, let o = model.doc.object(id) {
            Text(o.title)
            ForEach(o.parameters) { parameter in control(parameter, of: id) }
        } else {
            let points = items.filter { if case .vertex = $0 { true } else { false } }.count
            Text("\(items.count) selected" + (points > 0 ? ", \(points) points" : ""))
        }
    }

    @ViewBuilder
    private func control(_ parameter: Parameter, of id: String) -> some View {
        switch parameter.control {
        case let .number(_, get, set):
            HStack {
                Text(parameter.label)
                Spacer()
                TextField(parameter.label, value: Binding(get: { model.doc.object(id).map(get) ?? 0 },
                                                          set: { v in model.set(id, "Edit") { set($0, v) } }),
                          format: .number.precision(.fractionLength(0...3)))
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
            }
        case let .choice(options, get, set):
            Picker(parameter.label, selection: Binding(get: { model.doc.object(id).map(get) ?? "" },
                                                       set: { v in model.set(id, "Edit") { set($0, v) } })) {
                ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
            }
        case let .action(body):
            Button(parameter.label) { model.set(id, parameter.label) { body($0) } }
        }
    }
}
