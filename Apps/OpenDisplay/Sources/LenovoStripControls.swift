#if os(macOS) && !PUBLIC_API_ONLY
import AppKit
import DisplayDomain
import ExperimentalLifecycleProvider
import OpenDisplayDesignSystem
import SwiftUI

struct LenovoStripControls: View {
    @ObservedObject var lighting: LenovoLightingController
    let compact: Bool
    @State private var pickingColor = false
    @State private var paletteDraft: LenovoSavedPalette?
    @State private var deletingPalette: LenovoSavedPalette?

    private var selection: LenovoLightingSelection { lighting.selection }

    private var colorTitle: String {
        if selection.source == .zones, let saved = lighting.savedPalettes.first(where: { $0.id == selection.savedPaletteID }) {
            return saved.name
        }
        return selection.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 3) {
            if compact {
                quickRow.disabled(!lighting.usbAvailable)
                if pickingColor && lighting.usbAvailable {
                    LenovoStripColorPicker(initial: selection.colors[0], choose: lighting.chooseColor) {
                        pickingColor = false
                    }
                }
            } else {
                settingsControls
            }
            if let message = lighting.usbError {
                HStack {
                    Text(message)
                    Button("Check USB") { Task { await lighting.refreshUSB() } }
                }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            if let error = lighting.writeError, error != lighting.usbError {
                Text(error).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
        }
        .task(id: lighting.displayID) { await lighting.refreshUSB() }
    }

    private var quickRow: some View {
        HStack(spacing: 8) {
            Button { pickingColor.toggle() } label: {
                swatch(selection.colors)
                    .frame(width: 19, height: 16)
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.30), lineWidth: 0.7))
                    .frame(width: 20, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Choose any strip color")
            .accessibilityLabel("Choose strip color").accessibilityValue(colorTitle)

            Slider(value: brightness, in: 0...100)
                .accessibilityLabel("Strip brightness").help("Strip brightness")

            Menu {
                paletteChoices
            } label: {
                Image(systemName: "paintpalette").frame(width: 18, height: 24)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary).help("Strip palettes · \(colorTitle)").accessibilityLabel("Strip palettes")

            Menu {
                Picker("Effect", selection: effectBinding) { effectChoices }.pickerStyle(.inline)
            } label: {
                Image(systemName: "waveform.path").frame(width: 18, height: 24)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(selection.effect.animated ? Color.accentColor : .secondary)
            .help("Strip effect · \(selection.effect.rawValue)").accessibilityLabel("Strip effect")
            .accessibilityValue(selection.effect.rawValue)

            Text("\(selection.effect == .off ? 0 : selection.brightness)%")
                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
        .onDisappear { pickingColor = false }
    }

    @ViewBuilder private var settingsControls: some View {
        ODRow("Strip color") {
            solidPicker
            Menu(colorTitle) {
                Button("One color") { editColors { $0.source = .solid } }
                Button("Six zones") { editColors { $0.source = .zones } }
                Divider()
                paletteChoices
            }.fixedSize()
        }.disabled(!lighting.usbAvailable)
        if lighting.usbAvailable {
            presetButtons
            if selection.source == .zones { zonePickers }
        }
        paletteLibrary
        ODRow("Effect") {
            Picker("Effect", selection: effectBinding) { effectChoices }.labelsHidden().fixedSize()
        }.disabled(!lighting.usbAvailable)
        if lighting.usbAvailable && selection.effect != .off {
            ODRow("Strip brightness") {
                Slider(value: brightness, in: 0...100).frame(maxWidth: 130).accessibilityLabel("Strip brightness")
                Text("\(selection.brightness)%").monospacedDigit()
            }
            if selection.effect == .audio {
                ODRow("Mac audio") {
                    ProgressView(value: lighting.audioLevel ?? 0).frame(width: 65).accessibilityLabel("Playback level")
                    Text((lighting.audioLevel ?? 0) > 0.01 ? "Playing" : "Waiting for sound").font(.caption)
                }
            }
            if selection.effect.adjustableSpeed {
                ODRow("Cycle length") {
                    Slider(value: Binding(get: { selection.period }, set: { t in lighting.edit { $0.period = t } }),
                           in: 1.5...12, step: 0.5).frame(maxWidth: 130).accessibilityLabel("Cycle length")
                    Text("\(selection.period, specifier: "%.1f") s").monospacedDigit()
                }
            }
            if selection.effect == .custom {
                ODRow("Wave direction") {
                    Picker("Wave direction", selection: Binding(get: { selection.direction }, set: { d in
                        lighting.edit { $0.direction = d }
                    })) {
                        ForEach(LenovoLightingSelection.Direction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().pickerStyle(.segmented).fixedSize()
                }
            }
        }
    }

    private var effectBinding: Binding<LenovoStripEffect> {
        Binding(get: { selection.effect }, set: { choice in lighting.edit { $0.effect = choice } })
    }

    @ViewBuilder private var effectChoices: some View {
        ForEach(LenovoStripEffect.allCases, id: \.self) { Text($0.rawValue).tag($0) }
    }

    @ViewBuilder private var paletteChoices: some View {
        ForEach(LenovoPalettePreset.allCases, id: \.self) { preset in
            Button(preset.rawValue) { select(preset) }
        }
        if !lighting.savedPalettes.isEmpty {
            Divider()
            ForEach(lighting.savedPalettes) { saved in
                Button(saved.name) {
                    pickingColor = false
                    lighting.choosePalette(saved.colors, id: saved.id)
                }
            }
        }
    }

    private var paletteLibrary: some View {
        VStack(spacing: 0) {
            ODRow("Saved palettes") {
                Button("Add palette…") {
                    paletteDraft = LenovoSavedPalette(name: "", colors: selection.zones)
                }
            }
            ForEach(lighting.savedPalettes) { saved in
                HStack {
                    Button {
                        lighting.choosePalette(saved.colors, id: saved.id)
                    } label: {
                        HStack {
                            swatch(saved.colors).frame(width: 46, height: 9)
                            Text(saved.name).lineLimit(1)
                        }
                    }.buttonStyle(.plain).disabled(!lighting.usbAvailable)
                    Spacer()
                    Button("Edit…") { paletteDraft = saved }
                    Button { deletingPalette = saved } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete \(saved.name)")
                }
                .font(.caption).padding(.horizontal, 11).padding(.bottom, 5)
            }
        }
        .sheet(item: $paletteDraft) { draft in
            LenovoPaletteEditor(palette: draft) { updated in
                let wasActive = selection.source == .zones && selection.savedPaletteID == updated.id
                lighting.savePalette(updated)
                if wasActive && lighting.usbAvailable && updated.colors != selection.zones { lighting.choosePalette(updated.colors, id: updated.id) }
            }
        }
        .alert("Delete palette?", isPresented: Binding(get: { deletingPalette != nil }, set: { if !$0 { deletingPalette = nil } }),
               presenting: deletingPalette) { palette in
            Button("Delete", role: .destructive) { lighting.deletePalette(palette.id) }
            Button("Cancel", role: .cancel) {}
        } message: { palette in Text(palette.name) }
    }

    private var brightness: Binding<Double> {
        Binding(get: { selection.effect == .off ? 0 : Double(selection.brightness) }, set: { value in
            let level = Int(value.rounded())
            guard level != selection.brightness || selection.effect == .off else { return }
            lighting.edit {
                $0.brightness = level
                if $0.effect == .off { $0.effect = .steady }
            }
        })
    }

    private func editColors(_ change: (inout LenovoLightingSelection) -> Void) {
        lighting.edit {
            if $0.effect == .off { $0.effect = .steady }
            change(&$0)
        }
    }

    private var presetButtons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6)], spacing: 6) {
            ForEach(LenovoPalettePreset.allCases, id: \.self) { preset in
                let selected = selection.source == .zones && selection.preset == preset
                Button {
                    select(preset)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        swatch(preset.colors).frame(height: 7)
                        HStack {
                            Text(preset.rawValue)
                            Spacer(minLength: 0)
                            if selected { Image(systemName: "checkmark") }
                        }.font(.caption)
                    }
                    .padding(6)
                    .background(selected ? ODColor.accentTint : ODColor.fillSecondary, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset.rawValue) palette")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 3)
    }

    private func select(_ preset: LenovoPalettePreset) {
        pickingColor = false
        lighting.choosePalette(preset.colors)
    }

    private func swatch(_ colors: [LenovoStripPalette.RGB]) -> some View {
        HStack(spacing: 0) {
            ForEach(colors.indices, id: \.self) { i in Rectangle().fill(colors[i].color) }
        }
        .clipShape(Capsule()).accessibilityHidden(true)
    }

    private var solidPicker: some View {
        ColorPicker("Solid strip color", selection: Binding(get: { selection.solid.color }, set: { color in
            if let rgb = LenovoStripPalette.RGB(color) { lighting.chooseColor(rgb) }
        }), supportsOpacity: false).labelsHidden()
    }

    private var zonePickers: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
            ForEach(selection.zones.indices, id: \.self) { index in
                VStack(spacing: 2) {
                    ColorPicker("Zone \(index + 1)", selection: Binding(get: { selection.zones[index].color }, set: { color in
                        guard let rgb = LenovoStripPalette.RGB(color), rgb != selection.zones[index] else { return }
                        editColors {
                            $0.savedPaletteID = nil
                            $0.zones[index] = rgb
                            $0.source = .zones
                        }
                    }), supportsOpacity: false).labelsHidden()
                    Text("Zone \(index + 1)").font(.caption2)
                }
            }
        }.padding(.horizontal, 11).padding(.vertical, 4)
    }
}

#endif
