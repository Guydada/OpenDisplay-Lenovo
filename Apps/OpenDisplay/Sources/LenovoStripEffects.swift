#if os(macOS) && !PUBLIC_API_ONLY
import DisplayDomain
import Foundation

enum LenovoStripEffect: String, CaseIterable, Codable {
    case steady = "Steady", breathing = "Breathing", marquee = "Marquee", rainbow = "Rainbow"
    case starry = "Starry", fireworks = "Fireworks", flashing = "Flashing"
    case audio = "Audio meter", custom = "Custom wave", off = "Off"

    var animated: Bool { self != .steady && self != .off }
    var adjustableSpeed: Bool { animated && self != .audio }
}

struct LenovoLightingSelection: Codable, Equatable {
    typealias RGB = LenovoStripPalette.RGB
    enum Source: String, Codable { case solid, zones }
    enum Direction: String, Codable, CaseIterable { case forward = "Forward", reverse = "Reverse" }

    var source = Source.solid
    var savedPaletteID: UUID?
    var solid = RGB(red: 255, green: 0, blue: 0)
    var zones = LenovoPalettePreset.spectrum.colors
    var brightness = 50
    var effect = LenovoStripEffect.steady
    var period = 4.0
    var direction = Direction.forward

    var preset: LenovoPalettePreset? { LenovoPalettePreset.allCases.first { $0.colors == zones } }
    var title: String { source == .solid ? "One color" : (preset?.rawValue ?? "Custom zones") }
    var colors: [RGB] { source == .solid ? Array(repeating: solid, count: LenovoStripPalette.zoneCount) : zones }

    init() {}

    // The previous app used a single mode for color and firmware motion. Its effect case
    // discarded which color source was active, but kept the six actual zone colors.
    private enum LegacyMode: Decodable { case solid, zones, effect(Int) }
    private enum LegacyKeys: String, CodingKey { case mode }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        savedPaletteID = try c.decodeIfPresent(UUID.self, forKey: .savedPaletteID)
        solid = try c.decode(RGB.self, forKey: .solid)
        zones = try c.decode([RGB].self, forKey: .zones)
        brightness = try c.decode(Int.self, forKey: .brightness)
        if let saved = try c.decodeIfPresent(Source.self, forKey: .source) {
            source = saved
        } else {
            let old = try decoder.container(keyedBy: LegacyKeys.self).decode(LegacyMode.self, forKey: .mode)
            switch old { case .solid: source = .solid; case .zones, .effect: source = .zones }
        }
        effect = try c.decodeIfPresent(LenovoStripEffect.self, forKey: .effect) ?? .steady
        period = try c.decodeIfPresent(Double.self, forKey: .period) ?? 4
        direction = try c.decodeIfPresent(Direction.self, forKey: .direction) ?? .forward
        guard zones.count == LenovoStripPalette.zoneCount, (0...100).contains(brightness), (1.5...12).contains(period) else {
            throw DecodingError.dataCorruptedError(forKey: .zones, in: c, debugDescription: "Invalid strip settings")
        }
    }

    func frame(elapsed: Double, level: Double = 0) -> LenovoStripPalette {
        let base = colors
        let phase = elapsed / period
        let count = Double(base.count)
        let wheel = LenovoPalettePreset.spectrum.colors
        func wave(_ p: Double) -> Double { (1 + cos(2 * .pi * p)) / 2 }
        func sample(_ stops: [RGB], _ offset: Double) -> RGB {
            let position = (offset - floor(offset)) * Double(stops.count)
            let left = min(Int(position), stops.count - 1)
            return stops[left].mixed(with: stops[(left + 1) % stops.count], fraction: position - Double(left))
        }
        let pixels = base.enumerated().map { index, color -> RGB in
            let x = Double(index) / count
            switch effect {
            case .off: return .black
            case .steady: return color
            case .breathing: return color.scaled(0.08 + 0.92 * wave(phase))
            case .marquee: return color.scaled(0.04 + 0.96 * pow(wave(x - phase), 3))
            case .flashing: return color.scaled(wave(phase) >= 0.5 ? 1 : 0.12)
            case .fireworks: return color.scaled(0.04 + 0.96 * pow(wave(abs(x - 0.5) - phase), 5))
            case .starry: return color.scaled(0.09 + 0.91 * pow(wave(phase * (1 + x / 2) + x * 2.7), 6))
            case .rainbow: return color.mixed(with: sample(wheel, phase + x), fraction: 0.7)
            case .audio: return color.scaled(min(1, max(0, level * count - Double(index))))
            case .custom:
                let travel = direction == .forward ? -phase : phase
                // Phase-shift each selected zone; single-color waves still have visible motion.
                return sample(base, x + travel).scaled(0.25 + 0.75 * wave(x + travel))
            }
        }
        // The editor and decoder enforce the six-zone and 0–100 brightness invariants.
        return LenovoStripPalette(colors: pixels, brightness: brightness)!
    }
}

private extension LenovoStripPalette.RGB {
    static let black = Self(red: 0, green: 0, blue: 0)
    func scaled(_ gain: Double) -> Self { Self.black.mixed(with: self, fraction: gain) }
    func mixed(with other: Self, fraction: Double) -> Self {
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8(clamping: Int((Double(a) + (Double(b) - Double(a)) * fraction).rounded()))
        }
        return Self(red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue))
    }
}
#endif
