import DisplayDomain
import Foundation
import os

/// Run the menu/settings controller against an isolated preference domain and fake USB/audio.
@main @MainActor
struct LightingChecks {
    static func main() async throws {
        let suite = "OpenDisplay.StripChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = DisplayRecordID(rawValue: "test")
        let key = "LenovoStripLighting." + id.rawValue
        var base = LenovoLightingSelection()
        base.source = .zones
        base.brightness = 26
        let encoder = JSONEncoder()
        var legacy = try JSONSerialization.jsonObject(with: encoder.encode(base)) as! [String: Any]
        for field in ["source", "effect", "period", "direction"] { legacy.removeValue(forKey: field) }
        legacy["mode"] = ["effect": ["_0": 3]]
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: key)

        for effect in LenovoStripEffect.allCases {
            var s = base
            s.effect = effect
            let frames = (0..<12).map { i in s.frame(elapsed: Double(i) * 0.4, level: Double(i)/12) }
            precondition(frames.allSatisfy { $0.brightness == 26 && $0.featureReport.count == 168 })
            precondition(frames.dropFirst().contains { $0 != frames[0] } == effect.animated, effect.rawValue)
        }
        var solid = base
        solid.source = .solid
        solid.effect = .marquee
        precondition(solid.frame(elapsed: 0) != solid.frame(elapsed: 1))
        var custom = base
        custom.effect = .custom
        let forward = custom.frame(elapsed: 0.7)
        custom.direction = .reverse
        precondition(custom.frame(elapsed: 0.7) != forward)
        precondition(LenovoAudioMeter.normalized(rms: 0) == 0 && LenovoAudioMeter.normalized(rms: 0.8) == 1)
        precondition(LenovoAudioMeter.normalized(rms: 0.01) < LenovoAudioMeter.normalized(rms: 0.1))

        let sine = (0..<480).map { Float(0.2 * sin(2 * Double.pi * Double($0) / 48)) }
        let rms = LenovoAudioMeter.rms(sine, count: sine.count)
        precondition(abs(rms - 0.2 / sqrt(2)) < 0.0001)
        let silence = [Float](repeating: 0, count: 480)
        precondition(LenovoAudioMeter.rms(silence, count: silence.count) == 0)

        var frames: [LenovoStripPalette] = []
        var gate: CheckedContinuation<Void, Never>?
        var audioStarts = 0
        var denied = false
        let input = OSAllocatedUnfairLock(initialState: 0.0)
        func make() -> LenovoLightingController {
            LenovoLightingController(displayID: 1, recordID: id, defaults: defaults, checkUSB: {}, openWriter: {
                return { frame in
                    frames.append(frame)
                    if frames.count == 1 { await withCheckedContinuation { gate = $0 } }
                }
            }, openAudio: {
                audioStarts += 1
                if denied { throw LenovoAudioMeter.Failure(message: "Permission denied") }
                return { input.withLock { $0 } }
            })
        }
        defaults.set(try encoder.encode(base.zones), forKey: key + ".palette")
        let editor = make()
        precondition(editor.savedPalettes.count == 1 && editor.savedPalettes[0].colors == base.zones)
        let oldID = editor.savedPalettes[0].id
        editor.deletePalette(oldID)
        precondition(make().savedPalettes.isEmpty) // The legacy slot must not reappear.
        await editor.refreshUSB()
        precondition(editor.usbAvailable && editor.selection == base && frames.isEmpty && audioStarts == 0)
        editor.edit { $0.effect = .marquee }
        try await until { gate != nil }
        for level in 1...31 { editor.edit { $0.brightness = level } }
        editor.edit { $0.zones = LenovoPalettePreset.ocean.colors }
        gate?.resume()
        try await until { frames.count >= 4 }
        precondition(frames.dropFirst().allSatisfy { $0.brightness == 31 })
        precondition(frames[2] != frames[3] && editor.selection.effect == .marquee)
        var favorite = LenovoSavedPalette(name: " Ocean mist ", colors: editor.selection.zones)
        editor.savePalette(favorite)
        let dusk = LenovoSavedPalette(name: "Dusk", colors: LenovoPalettePreset.sunset.colors)
        editor.savePalette(dusk)
        precondition(make().savedPalettes.map(\.name) == ["Ocean mist", "Dusk"])
        favorite.name = "Warm mist"
        favorite.colors[2] = .init(red: 211, green: 50, blue: 75)
        editor.savePalette(favorite)
        precondition(make().savedPalettes == [favorite, dusk])
        editor.choosePalette(favorite.colors, id: favorite.id)
        precondition(editor.selection.savedPaletteID == favorite.id)
        // The swatch must work from any source, even if the new RGB matches the last solid.
        editor.chooseColor(editor.selection.solid)
        precondition(editor.selection.source == .solid && editor.selection.effect == .marquee)
        let rgb = LenovoStripPalette.RGB(red: 39, green: 157, blue: 218)
        editor.chooseColor(rgb)
        precondition(editor.selection.solid == rgb && editor.selection.effect == .marquee)
        editor.edit { $0.effect = .off }
        editor.chooseColor(rgb)
        try await until { frames.last?.zones.allSatisfy { $0 == rgb } == true }
        precondition(editor.selection.effect == .steady)
        editor.deletePalette(dusk.id)
        precondition(make().savedPalettes == [favorite])

        editor.edit { $0.effect = .audio }
        try await until { audioStarts == 1 && editor.audioLevel == 0 }
        let dark = frames.last!
        input.withLock { $0 = 0.95 }
        try await until { editor.audioLevel == 0.95 && frames.last != dark }
        editor.edit { $0.effect = .steady }
        try await until { editor.audioLevel == nil && frames.last == editor.selection.frame(elapsed: 0) }
        let idle = frames.count
        try await Task.sleep(for: .milliseconds(240))
        precondition(frames.count == idle && make().selection == editor.selection)
        denied = true
        editor.edit { $0.effect = .audio }
        try await until { editor.writeError != nil }
        precondition(editor.selection.effect == .steady)
        editor.edit { $0.effect = .custom }
        try await until { frames.last != editor.selection.frame(elapsed: 0) && editor.writeError == nil }
        editor.stop()
        let stopped = frames.count
        try await Task.sleep(for: .milliseconds(240))
        precondition(frames.count == stopped && make().selection.effect == .steady && audioStarts == 2)
        print("Passed legacy migration, all effect frames, live edits, custom direction, saved palette, audio levels, denial, stop and silent relaunch.")
    }

    static func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for lighting editor")
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
