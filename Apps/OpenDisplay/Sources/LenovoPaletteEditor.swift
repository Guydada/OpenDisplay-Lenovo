#if os(macOS) && !PUBLIC_API_ONLY
import DisplayDomain
import SwiftUI

struct LenovoPaletteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LenovoSavedPalette
    private let isNew: Bool
    let save: (LenovoSavedPalette) -> Void

    init(palette: LenovoSavedPalette, save: @escaping (LenovoSavedPalette) -> Void) {
        _draft = State(initialValue: palette)
        self.save = save
        isNew = palette.name.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New palette" : "Edit palette").font(.headline)
            TextField("Palette name", text: $draft.name).accessibilityLabel("Palette name")
            HStack(spacing: 10) {
                ForEach(draft.colors.indices, id: \.self) { index in
                    VStack(spacing: 4) {
                        ColorPicker("Zone \(index + 1)", selection: Binding(get: { draft.colors[index].color }, set: { color in
                            if let rgb = LenovoStripPalette.RGB(color) { draft.colors[index] = rgb }
                        }), supportsOpacity: false).labelsHidden()
                        Text("Zone \(index + 1)").font(.caption2)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save palette") { save(draft); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(18)
    }
}
#endif
