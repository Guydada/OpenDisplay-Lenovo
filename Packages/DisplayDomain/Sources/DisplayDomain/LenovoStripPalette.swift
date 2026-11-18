/// A static palette for the Lenovo Y34wz-30's USB ambient lighting controller.
public struct LenovoStripPalette: Equatable, Sendable {
    public static let reportID: UInt8 = 0x72
    public static let reportLength = 168
    public static let zoneCount = 6

    public struct RGB: Equatable, Codable, Sendable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public init?(hex: String) {
            let digits = hex.hasPrefix("#") ? hex.dropFirst() : hex[...]
            guard digits.utf8.count == 6, digits.allSatisfy(\.isHexDigit),
                  let rgb = UInt32(digits, radix: 16) else { return nil }
            self.init(red: UInt8(rgb >> 16), green: UInt8(truncatingIfNeeded: rgb >> 8),
                      blue: UInt8(truncatingIfNeeded: rgb))
        }
    }

    public let zones: [RGB]
    public let brightness: Int

    public init?(colors: [RGB], brightness: Int) {
        guard (0...100).contains(brightness) else { return nil }
        if colors.count == 1, let solid = colors.first {
            zones = Array(repeating: solid, count: Self.zoneCount)
        } else {
            guard colors.count == Self.zoneCount else { return nil }
            zones = colors
        }
        self.brightness = brightness
    }

    public var featureReport: [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.reportLength)
        // Preserve the vendor header and its reserved fields. In the strip record,
        // byte 12 selects static mode and byte 17 carries brightness.
        let header: [UInt8] = [
            Self.reportID, 1, 255, 0, 0, 0, 100, 0, 255, 0, 128, 0,
            1, 255, 0, 0, 0, UInt8(brightness), 0, 255, 0, 128
        ]
        bytes.replaceSubrange(0..<header.count, with: header)
        // The six logical zones span alternating groups of three and two RGB emitters.
        var offset = 0x5F
        for (color, count) in zip(zones, [3, 2, 3, 2, 3, 2]) {
            for _ in 0..<count {
                bytes[offset] = color.red
                bytes[offset + 1] = color.green
                bytes[offset + 2] = color.blue
                offset += 3
            }
        }
        return bytes
    }
}
