#if os(macOS) && !PUBLIC_API_ONLY
import Combine
import CoreGraphics
import DisplayDomain
import ExperimentalLifecycleProvider
import Foundation

enum LenovoPalettePreset: String, CaseIterable {
    case spectrum = "Spectrum", aurora = "Aurora", sunset = "Sunset", ocean = "Ocean"

    var colors: [LenovoStripPalette.RGB] {
        let hex: [UInt32]
        switch self {
        case .spectrum: hex = [0xFF294B, 0xFF901F, 0xFFDF36, 0x22D57F, 0x2288FF, 0xAA48FF]
        case .aurora:   hex = [0x21765F, 0x28DA89, 0x81F7AD, 0x37C6D7, 0x5164FF, 0xA74BED]
        case .sunset:   hex = [0xFFCC55, 0xFFA039, 0xFB643A, 0xEB3871, 0xB3339B, 0x6B47AB]
        case .ocean:    hex = [0x153B98, 0x205DE5, 0x0098DF, 0x00BDCA, 0x24DDC1, 0x9AF3DD]
        }
        return hex.map { .init(red: UInt8($0 >> 16), green: UInt8(truncatingIfNeeded: $0 >> 8),
                               blue: UInt8(truncatingIfNeeded: $0)) }
    }
}

struct LenovoSavedPalette: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var colors: [LenovoStripPalette.RGB]
}

/// Both lighting surfaces edit a single selection. A worker owns one USB connection and
/// at most one audio tap; it serializes edits and animation frames until the effect ends.
@MainActor
final class LenovoLightingController: ObservableObject {
    typealias Output = (LenovoStripPalette) async throws -> Void
    typealias Level = @Sendable () -> Double?
    let displayID: CGDirectDisplayID
    @Published private(set) var selection: LenovoLightingSelection
    @Published private(set) var usbAvailable = false
    @Published private(set) var usbError: String?
    @Published private(set) var writeError: String?
    @Published private(set) var audioLevel: Double?
    @Published private(set) var savedPalettes: [LenovoSavedPalette] = []

    private let defaults: UserDefaults
    private let key: String
    private let checkUSB: () async throws -> Void
    private let openWriter: () async throws -> Output
    private let openAudio: () async throws -> Level
    private var lastAccepted: LenovoLightingSelection
    private var revision = 0
    private var worker: Task<Void, Never>?

    init(displayID: CGDirectDisplayID, recordID: DisplayRecordID, defaults: UserDefaults = .standard,
         checkUSB: @escaping () async throws -> Void, openWriter: @escaping () async throws -> Output,
         openAudio: @escaping () async throws -> Level = LenovoAudioMeter.open) {
        self.displayID = displayID
        self.defaults = defaults
        self.checkUSB = checkUSB
        self.openWriter = openWriter
        self.openAudio = openAudio
        key = "LenovoStripLighting." + recordID.rawValue
        var saved = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LenovoLightingSelection.self, from: $0) }
            ?? LenovoLightingSelection()
        // A running effect (especially system audio capture) requires an explicit selection.
        if saved.effect.animated { saved.effect = .steady }
        lastAccepted = saved
        selection = saved
        if let data = defaults.data(forKey: key + ".palettes") {
            let library = try? JSONDecoder().decode([LenovoSavedPalette].self, from: data)
            savedPalettes = library?.filter { !$0.name.isEmpty && $0.colors.count == LenovoStripPalette.zoneCount } ?? []
        } else if let data = defaults.data(forKey: key + ".palette"),
                  let colors = try? JSONDecoder().decode([LenovoStripPalette.RGB].self, from: data),
                  colors.count == LenovoStripPalette.zoneCount {
            savedPalettes = [LenovoSavedPalette(name: "My palette", colors: colors)]
            persistPalettes()
        }
    }

    func refreshUSB() async {
        do {
            try await checkUSB()
            usbAvailable = true
            usbError = nil
        } catch {
            usbAvailable = false
            usbError = error.localizedDescription
        }
    }

    func savePalette(_ palette: LenovoSavedPalette) {
        var clean = palette
        clean.name = clean.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.name.isEmpty, clean.colors.count == LenovoStripPalette.zoneCount else { return }
        if let index = savedPalettes.firstIndex(where: { $0.id == clean.id }) {
            savedPalettes[index] = clean
        } else {
            savedPalettes.append(clean)
        }
        persistPalettes()
    }

    func deletePalette(_ id: UUID) {
        savedPalettes.removeAll { $0.id == id }
        persistPalettes()
    }

    private func persistPalettes() {
        if let data = try? JSONEncoder().encode(savedPalettes) { defaults.set(data, forKey: key + ".palettes") }
    }

    func chooseColor(_ rgb: LenovoStripPalette.RGB) {
        guard selection.solid != rgb || selection.source != .solid || selection.effect == .off else { return }
        edit {
            $0.solid = rgb
            $0.source = .solid
            if $0.effect == .off { $0.effect = .steady }
        }
    }

    func choosePalette(_ colors: [LenovoStripPalette.RGB], id: UUID? = nil) {
        guard colors.count == LenovoStripPalette.zoneCount else { return }
        edit {
            $0.zones = colors
            $0.savedPaletteID = id
            $0.source = .zones
            if $0.effect == .off { $0.effect = .steady }
        }
    }

    func edit(_ change: (inout LenovoLightingSelection) -> Void) {
        var next = selection
        change(&next)
        selection = next
        revision += 1
        writeError = nil
        if worker == nil { worker = Task { await run() } }
    }

    func stop() {
        worker?.cancel()
        worker = nil
        audioLevel = nil
        if selection.effect.animated { selection.effect = .steady }
        if lastAccepted.effect.animated { lastAccepted.effect = .steady }
    }

    private func run() async {
        var output: Output?
        var meter: Level?
        var previous: LenovoStripPalette?
        var appliedRevision = -1
        var motion: LenovoStripEffect?
        var start = ProcessInfo.processInfo.systemUptime
        var envelope = 0.0
        var nextUSBCheck = start + 2
        defer { if !Task.isCancelled { worker = nil; audioLevel = nil } }

        while !Task.isCancelled {
            let ticket = revision
            let current = selection
            let changed = appliedRevision != ticket
            do {
                if output == nil { output = try await openWriter() }
                // A silent audio meter can produce identical frames for minutes. Detect a
                // removed USB upstream even when no changed frame would hit the writer.
                if current.effect.animated && ProcessInfo.processInfo.systemUptime >= nextUSBCheck {
                    try await checkUSB()
                    nextUSBCheck = ProcessInfo.processInfo.systemUptime + 2
                }
                guard !Task.isCancelled, ticket == revision else { continue }
                if current.effect == .audio {
                    if meter == nil { meter = try await openAudio() }
                } else {
                    meter = nil
                    if audioLevel != nil { audioLevel = nil }
                }
                guard !Task.isCancelled, ticket == revision, let output else { continue }
                let now = ProcessInfo.processInfo.systemUptime
                if motion != current.effect {
                    motion = current.effect
                    start = now
                    envelope = 0
                }
                if let meter {
                    let reading = meter()
                    envelope = max(reading ?? 0, envelope - 0.09)
                    audioLevel = reading
                }
                let frame = current.frame(elapsed: now - start, level: envelope)
                if changed || frame != previous {
                    try await output(frame)
                    guard !Task.isCancelled else { return }
                    previous = frame
                }
                if changed {
                    lastAccepted = current
                    appliedRevision = ticket
                    if let data = try? JSONEncoder().encode(current) { defaults.set(data, forKey: key) }
                }
            } catch {
                guard !Task.isCancelled else { return }
                meter = nil
                if ticket != revision { output = nil; continue }
                let message = error.localizedDescription
                // An audio permission/start failure can leave a previous animation frozen mid-frame.
                // Restore its chosen colors when we still have a usable USB connection.
                var fallback = lastAccepted
                if fallback.effect.animated { fallback.effect = .steady }
                if error is LenovoAudioMeter.Failure, let output {
                    try? await output(fallback.frame(elapsed: 0))
                }
                guard !Task.isCancelled, ticket == revision else { continue }
                selection = fallback
                lastAccepted = fallback
                writeError = message
                await refreshUSB()
                if ticket != revision { continue }
                return
            }
            if ticket != revision { continue }
            try? await Task.sleep(for: .milliseconds(current.effect.animated ? 100 : 40))
            if ticket == revision && !current.effect.animated { return }
        }
    }
}
#endif
