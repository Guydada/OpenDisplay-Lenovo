#if os(macOS)
import CoreGraphics
import DisplayDomain
import Foundation
import IOKit.hid

/// USB lighting on the Y34wz-30. Discovery only inspects local device metadata.
public actor LenovoStripLighting {
    public static let shared = LenovoStripLighting()

    public enum Failure: LocalizedError {
        case displayUnavailable, ambiguous, usbUnavailable, open(IOReturn), write(IOReturn)

        public var errorDescription: String? {
            switch self {
            case .displayUnavailable: return "The selected Lenovo Y34wz-30 is offline."
            case .ambiguous: return "Multiple Lenovo devices are connected. The light strip cannot be identified."
            case .usbUnavailable: return "The monitor’s USB lighting controller is unavailable on this Mac."
            case .open(let code): return "Couldn’t open the lighting controller (\(String(format: "0x%08X", code)))."
            case .write(let code): return "The lighting controller rejected the color (\(String(format: "0x%08X", code)))."
            }
        }
    }

    public func check(displayID: CGDirectDisplayID) throws {
        _ = try device(for: displayID)
    }

    public func apply(_ palette: LenovoStripPalette, to displayID: CGDirectDisplayID) throws {
        try openHandle(for: displayID).write(palette)
    }

    /// Retain this binding for one animation. Its fixed device reference cannot retarget
    /// another controller after unplugging. Releasing the writer closes the USB handle.
    public func openWriter(for displayID: CGDirectDisplayID) throws -> Writer {
        try Writer(handle: openHandle(for: displayID))
    }

    public actor Writer {
        fileprivate let handle: Handle
        fileprivate init(handle: Handle) { self.handle = handle }
        public func write(_ palette: LenovoStripPalette) throws { try handle.write(palette) }
    }

    fileprivate final class Handle: @unchecked Sendable {
        private let device: IOHIDDevice
        init(_ target: IOHIDDevice) throws {
            let opened = IOHIDDeviceOpen(target, IOOptionBits(kIOHIDOptionsTypeNone))
            guard opened == kIOReturnSuccess else { throw Failure.open(opened) }
            device = target
        }
        deinit { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        func write(_ palette: LenovoStripPalette) throws {
            let bytes = palette.featureReport
            let sent = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(LenovoStripPalette.reportID), bytes, bytes.count)
            guard sent == kIOReturnSuccess else { throw Failure.write(sent) }
        }
    }

    private func openHandle(for displayID: CGDirectDisplayID) throws -> Handle {
        try Handle(device(for: displayID))
    }

    private func device(for displayID: CGDirectDisplayID) throws -> IOHIDDevice {
        // The controller's serial is independent of the video EDID. Require a unique
        // model on both connections and resolve them afresh for every explicit write.
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { throw Failure.displayUnavailable }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count) + 1)
        let capacity = UInt32(displays.count)
        guard CGGetOnlineDisplayList(capacity, &displays, &count) == .success,
              count < capacity else { throw Failure.ambiguous }
        let matches = displays.prefix(Int(count)).filter(ExternalDisplayDDC.isLenovoY34wz)
        guard matches.contains(displayID) else { throw Failure.displayUnavailable }
        guard matches.count == 1 else { throw Failure.ambiguous }

        let query = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
        query[kIOPropertyMatchKey] = [kIOHIDVendorIDKey: 0x17EF, kIOHIDProductIDKey: 0x10AC,
                                      kIOHIDTransportKey: "USB", kIOHIDMaxFeatureReportSizeKey: LenovoStripPalette.reportLength] as [String: Any]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, query, &iterator) == KERN_SUCCESS else {
            throw Failure.usbUnavailable
        }
        defer { IOObjectRelease(iterator) }
        var target: IOHIDDevice?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard target == nil else { throw Failure.ambiguous }
            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service),
                  hasLightingFeature(device) else { throw Failure.usbUnavailable }
            target = device
        }
        guard let target else { throw Failure.usbUnavailable }
        return target
    }

    private func hasLightingFeature(_ device: IOHIDDevice) -> Bool {
        let query = [kIOHIDElementTypeKey: Int(kIOHIDElementTypeFeature.rawValue),
                     kIOHIDElementReportIDKey: Int(LenovoStripPalette.reportID)]
        let elements = IOHIDDeviceCopyMatchingElements(device, query as CFDictionary, 0) as? [IOHIDElement] ?? []
        return elements.contains {
            IOHIDElementGetUsagePage($0) == 0xFF00 && IOHIDElementGetUsage($0) == 1
                && IOHIDElementGetReportCount($0) == UInt32(LenovoStripPalette.reportLength - 1)
        }
    }
}
#endif
