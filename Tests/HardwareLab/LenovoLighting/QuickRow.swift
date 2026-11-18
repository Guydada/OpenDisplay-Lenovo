import AppKit
import DisplayDomain
import SwiftUI

/// Exercises the actual status-row swatch and picker in a private window with a fake USB writer.
@main struct QuickRowCheck {
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let suite = "OpenDisplay.GestureTest." + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        var reports: [LenovoStripPalette] = []
        let editor = LenovoLightingController(displayID: 2, recordID: .init(rawValue: "test"), defaults: prefs,
                                             checkUSB: {}, openWriter: { { reports.append($0) } })
        await editor.refreshUSB()
        editor.choosePalette(LenovoPalettePreset.ocean.colors)
        try await Task.sleep(for: .milliseconds(80))
        let host = NSHostingView(rootView: LenovoStripControls(lighting: editor, compact: true).frame(width: 288))
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 288, height: 200), styleMask: [.nonactivatingPanel, .titled], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderBack(nil)
        window.makeKey()
        func layout() {
            window.setContentSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
        }
        func at(_ x: CGFloat, _ top: CGFloat) -> NSPoint {
            host.convert(NSPoint(x: x, y: host.isFlipped ? top : host.bounds.height - top), to: nil)
        }
        func mouse(_ x: CGFloat, _ top: CGFloat, _ kind: NSEvent.EventType) {
            let ev = NSEvent.mouseEvent(with: kind, location: at(x, top), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            app.sendEvent(ev)
        }
        func click(_ x: CGFloat, _ top: CGFloat) async throws {
            mouse(x, top, .leftMouseDown)
            try await Task.sleep(for: .milliseconds(60))
            mouse(x, top, .leftMouseUp)
            try await Task.sleep(for: .milliseconds(100))
            layout()
        }
        layout()
        try await Task.sleep(for: .milliseconds(300))
        let closed = host.fittingSize.height
        precondition(closed <= 32, "The quick controls should occupy one row")
        try await click(18, closed / 2)
        precondition(host.fittingSize.height > closed + 70, "The swatch should open the in-menu picker")

        let before = reports.count
        mouse(135, closed + 45, .leftMouseDown)
        try await Task.sleep(for: .milliseconds(100))
        precondition(reports.count > before && editor.selection.source == .solid, "Color should change before releasing the mouse")
        let first = editor.selection.solid
        mouse(195, closed + 25, .leftMouseDragged)
        try await Task.sleep(for: .milliseconds(100))
        precondition(editor.selection.solid != first)
        mouse(195, closed + 25, .leftMouseUp)
        precondition(reports.last?.zones.allSatisfy { $0 == editor.selection.solid } == true)

        try await click(80, host.fittingSize.height - 21)
        guard let field = window.firstResponder as? NSTextView else { fatalError("Hex field did not receive focus") }
        field.selectAll(nil)
        field.insertText("#84C72A", replacementRange: field.selectedRange())
        try await Task.sleep(for: .milliseconds(100))
        precondition(editor.selection.solid.hex == "84C72A", "A complete hex value should apply while the field still has focus")
        precondition(reports.last?.zones.allSatisfy { $0 == editor.selection.solid } == true)
        try await click(18, closed / 2)
        precondition(host.fittingSize.height == closed)
        print("Passed single row, live color drag from a palette, immediate hex entry, and collapse.")
    }
}
