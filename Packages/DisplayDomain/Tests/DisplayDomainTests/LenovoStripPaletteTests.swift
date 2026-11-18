import XCTest
@testable import DisplayDomain

final class LenovoStripPaletteTests: XCTestCase {
    func testVendorNoAnimationFrame() throws {
        // Captured at the vendor HID writer's boundary in an offline CPU emulator.
        // All 168 bytes are part of the comparison, including reserved bytes.
        let expected = """
        7201ff0000006400ff00800001ff0000
        002a00ff008000000000000000000000
        00000000000000000000000000000000
        00000000000000000000000000000000
        00000000000000000000000000000000
        00000000000000000000000000000012
        34561234561234561234561234561234
        56123456123456123456123456123456
        12345612345612345612345600000000
        00000000000000000000000000000000
        0000000000000000
        """.split(whereSeparator: \.isWhitespace).joined()
        let color = try XCTUnwrap(LenovoStripPalette(colors: [try XCTUnwrap(.init(hex: "#123456"))], brightness: 42))
        XCTAssertEqual(color.featureReport.map { String(format: "%02x", $0) }.joined(), expected)
    }

    func testVendorZoneOrderAndLengths() throws {
        let hex = ["010203", "112233", "445566", "778899", "aabbcc", "ddee0f"]
        let colors = hex.compactMap(LenovoStripPalette.RGB.init(hex:))
        let palette = try XCTUnwrap(LenovoStripPalette(colors: colors, brightness: 85))
        let actual = palette.featureReport[95..<140].map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actual, "010203010203010203112233112233445566445566445566778899778899aabbccaabbccaabbccddee0fddee0f")
        for invalid in [[], Array(colors.prefix(2)), Array(colors.prefix(5)), colors + colors] {
            XCTAssertNil(LenovoStripPalette(colors: invalid, brightness: 85))
        }
    }

    func testValidationAndIndependentChannels() throws {
        for invalid in ["", "123", "0x123456", "gg1122", "12345600", "+12345", " 12345"] {
            XCTAssertNil(LenovoStripPalette.RGB(hex: invalid))
        }
        for invalid in [-1, 101, 256] {
            XCTAssertNil(LenovoStripPalette(colors: [.init(red: 255, green: 0, blue: 0)], brightness: invalid))
        }
        for brightness in [0, 1, 100] {
            let color = try XCTUnwrap(LenovoStripPalette(colors: [try XCTUnwrap(.init(hex: "00fFaE"))], brightness: brightness))
            let bytes = color.featureReport
            XCTAssertEqual(bytes.count, 168)
            XCTAssertEqual(Int(bytes[17]), brightness)
            XCTAssertEqual(Array(bytes[95..<140]), Array(repeating: [UInt8(0), 255, 174], count: 15).flatMap { $0 })
        }
    }
}
