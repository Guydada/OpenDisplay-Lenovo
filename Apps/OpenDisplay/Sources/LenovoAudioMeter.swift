#if os(macOS) && !PUBLIC_API_ONLY
import Accelerate
import CoreAudio
import Foundation
import os

/// A private, unmuted Core Audio process tap. Only a recent RMS measurement crosses
/// the audio callback. The aggregate is private and never becomes an output device.
final class LenovoAudioMeter: @unchecked Sendable {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private let sample = OSAllocatedUnfairLock(initialState: (rms: Float.zero, at: UInt64.zero))

    static func open() async throws -> @Sendable () -> Double? {
        guard #available(macOS 14.2, *) else { throw Failure(message: "System audio lighting requires macOS 14.2 or later.") }
        return try await Task.detached {
            let meter = LenovoAudioMeter()
            try meter.start()
            return { @Sendable in meter.level }
        }.value
    }

    static func rms(_ samples: UnsafePointer<Float>, count: Int) -> Float {
        var result: Float = 0
        vDSP_rmsqv(samples, 1, &result, vDSP_Length(count))
        return result
    }

    static func normalized(rms: Float) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        return min(1, max(0, (20 * log10(Double(rms)) + 58) / 52))
    }

    private var level: Double? {
        let value = sample.withLock { $0 }
        guard value.at > 0, DispatchTime.now().uptimeNanoseconds - value.at < 1_000_000_000 else { return nil }
        return Self.normalized(rms: value.rms)
    }

    @available(macOS 14.2, *)
    private func start() throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "OpenDisplay strip audio meter"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        func check(_ status: OSStatus) throws {
            guard status == noErr else {
                throw Failure(message: "System audio capture failed (\(status)). Check OpenDisplay’s System Audio Recording permission in Privacy & Security.")
            }
        }
        try check(AudioHardwareCreateProcessTap(description, &tap))
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout.size(ofValue: format))
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else { throw Failure(message: "The system audio tap has an unsupported sample format.") }

        let config: [String: Any] = [
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceNameKey: "OpenDisplay strip audio meter",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                kAudioSubTapDriftCompensationKey: true] as [String: Any]]
        ]
        try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate))
        let storage = sample
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, _, _ in
            // The tap is mono Float32. Compute directly in Core Audio's borrowed buffer.
            let buffer = input.pointee.mBuffers
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0, let data = buffer.mData else { return }
            let measurement = Self.rms(data.assumingMemoryBound(to: Float.self), count: count)
            let sample = (measurement, DispatchTime.now().uptimeNanoseconds)
            storage.withLock { $0 = sample }
        })
        try check(AudioDeviceStart(aggregate, proc))
    }

    deinit {
        if let proc {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
        }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        if #available(macOS 14.2, *), tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
    }
}
#endif
