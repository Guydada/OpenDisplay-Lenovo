#if os(macOS) && !PUBLIC_API_ONLY
import AppKit
import DisplayDomain
import SwiftUI

/// Lives inside the status popover so a drag never hands focus to another window.
struct LenovoStripColorPicker: View {
    typealias RGB = LenovoStripPalette.RGB
    @State private var hue: Double
    @State private var saturation: Double
    @State private var value: Double
    @State private var hex: String
    let choose: (RGB) -> Void
    let close: () -> Void

    init(initial: RGB, choose: @escaping (RGB) -> Void, close: @escaping () -> Void) {
        let c = NSColor(srgbRed: Double(initial.red)/255, green: Double(initial.green)/255,
                        blue: Double(initial.blue)/255, alpha: 1)
        _hue = State(initialValue: c.hueComponent)
        _saturation = State(initialValue: c.saturationComponent)
        _value = State(initialValue: c.brightnessComponent)
        _hex = State(initialValue: initial.hex)
        self.choose = choose
        self.close = close
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { box in
                ZStack {
                    Rectangle().fill(LinearGradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                                                    startPoint: .leading, endPoint: .trailing))
                    Rectangle().fill(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                    Circle().stroke(.white, lineWidth: 2).shadow(radius: 1).frame(width: 10, height: 10)
                        .position(x: cursor(saturation, in: box.size.width), y: cursor(1 - value, in: box.size.height))
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    saturation = fraction(drag.location.x, in: box.size.width)
                    value = 1 - fraction(drag.location.y, in: box.size.height)
                    publish()
                })
                .accessibilityLabel("Saturation and brightness")
            }.frame(height: 92)
            GeometryReader { box in
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: (0...6).map {
                        Color(hue: Double($0)/6, saturation: 1, brightness: 1)
                    }, startPoint: .leading, endPoint: .trailing)).frame(height: 8)
                    Circle().fill(Color(hue: hue, saturation: 1, brightness: 1)).overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(radius: 1).frame(width: 12, height: 12)
                        .position(x: cursor(hue, in: box.size.width), y: box.size.height/2)
                }.frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    hue = fraction(drag.location.x, in: box.size.width)
                    publish()
                })
                .accessibilityLabel("Hue")
                .accessibilityAdjustableAction { direction in
                    hue = min(1, max(0, hue + (direction == .increment ? 1.0/36 : -1.0/36)))
                    publish()
                }
            }.frame(height: 16)
            HStack {
                Text("Hex").font(.caption).foregroundStyle(.secondary)
                TextField("RRGGBB", text: Binding(get: { hex }, set: { text in
                    hex = text
                    guard let rgb = RGB(hex: text) else { return }
                    let c = NSColor(srgbRed: Double(rgb.red)/255, green: Double(rgb.green)/255, blue: Double(rgb.blue)/255, alpha: 1)
                    if c.saturationComponent > 0 { hue = c.hueComponent }
                    saturation = c.saturationComponent
                    value = c.brightnessComponent
                    choose(rgb)
                })).font(.system(.caption, design: .monospaced)).frame(width: 74)
                    .accessibilityLabel("Hex color")
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Close color picker")
            }
        }
        .padding(9).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 7).padding(.bottom, 3)
        .onExitCommand(perform: close)
    }

    private func cursor(_ value: Double, in size: CGFloat) -> CGFloat { min(size - 6, max(6, value * size)) }
    private func fraction(_ point: CGFloat, in size: CGFloat) -> Double { min(1, max(0, point / max(1, size))) }
    private func publish() {
        let color = NSColor(hue: hue, saturation: saturation, brightness: value, alpha: 1)
        let rgb = RGB(red: UInt8((color.redComponent * 255).rounded()),
                      green: UInt8((color.greenComponent * 255).rounded()), blue: UInt8((color.blueComponent * 255).rounded()))
        hex = rgb.hex
        choose(rgb)
    }
}

extension LenovoStripPalette.RGB {
    var hex: String { String(format: "%02X%02X%02X", red, green, blue) }
    var color: Color { Color(.sRGB, red: Double(red)/255, green: Double(green)/255, blue: Double(blue)/255) }

    init?(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> UInt8 { UInt8((min(1, max(0, component)) * 255).rounded()) }
        self.init(red: byte(rgb.redComponent), green: byte(rgb.greenComponent), blue: byte(rgb.blueComponent))
    }
}
#endif
