#if os(macOS)
/// Options for Y34wz-30 from Lenovo's model-specific LADM tables.
public enum LenovoPictureSetting: UInt8, CaseIterable, Sendable {
    case game = 0xF9, hdr = 0xEF, dynamicContrast = 0xEA

    public var label: String {
        switch self {
        case .game: "Game mode"
        case .hdr: "HDR mode"
        case .dynamicContrast: "Dynamic contrast"
        }
    }

    public var options: [(code: Int, label: String)] {
        switch self {
        case .game:
            [(0, "Off"), (10, "Standard"), (1, "FPS 1"), (2, "FPS 2"), (3, "Racing"),
             (4, "RTS"), (5, "Game 1"), (6, "Game 2")]
        case .hdr:
            [(0, "Off"), (1, "Automatic"), (7, "Game"), (8, "Movie"), (9, "Photo")]
        case .dynamicContrast: [(0, "Off"), (1, "On")]
        }
    }
}
#endif
