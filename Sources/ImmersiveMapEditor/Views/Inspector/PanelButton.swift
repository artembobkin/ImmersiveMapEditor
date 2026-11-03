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
