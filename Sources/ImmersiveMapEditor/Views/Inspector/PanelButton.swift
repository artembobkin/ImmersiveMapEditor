import SwiftUI

/// A button of the inspector's panels: the full width of its section, its
/// title in the middle and, when it has one, its key at the right edge in
/// grey. Every button of a panel is then the same size, whatever its title
/// (the user, 2026-11-01: buttons of different widths look untidy).
struct PanelButton: View {
    let title: String
    let systemImage: String?
    let key: String?
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, key: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.key = key
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            ZStack {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
                if let key {
                    HStack {
                        Spacer()
                        Text(key).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

/// The detail asked of the next run of Claude, beside every button that
/// queues one (the user, 2026-11-05: to be set right where the modelling is
/// started, not in a settings group): Normal, or Fine with the ornament.
struct DetailPicker: View {
    @AppStorage(ClaudeSettings.detailKey) private var detail = "normal"

    var body: some View {
        Picker("Detail", selection: Binding(get: { ClaudeSettings.detail }, set: { detail = $0 })) {
            ForEach(ClaudeSettings.details, id: \.id) { Text($0.title).tag($0.id) }
        }
        .pickerStyle(.segmented)
        .help("How much of the landmark Claude models in the run queued next. Normal: everything that reads from across the street. Fine: the ornament too, bays, porches, brackets, balustrades and trim from shapes, with twice the turns and five fix builds, slower and dearer. Each run keeps the level it is queued with.")
    }
}
