// SPDX-License-Identifier: MPL-2.0
import CoreAudio
import Foundation

/// A read-only snapshot of the macOS default output, not a DAW's selected device.
public struct AudioOutputSnapshot: Sendable {
    public let name: String
    public let sampleRate: Double?
    public let bufferFrames: UInt32?
    /// Physical PCM stream depths; nil if any stream cannot be read or is non-PCM.
    public let bitDepths: [UInt32]?

    public static func read() -> Self? { read(using: SystemAudioOutputReader()) }

    static func read(using reader: some AudioOutputReading) -> Self? {
        guard let id = reader.defaultOutput(), id != kAudioObjectUnknown,
              reader.isAlive(id) == true else { return nil }
        let name = reader.name(id).flatMap { DisplaySanitiser.sanitise($0) } ?? "Unnamed audio device"
        let rate = reader.sampleRate(id).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let frames = reader.bufferFrames(id).flatMap { $0 > 0 ? $0 : nil }
        let rawDepths = reader.bitDepths(id)
        let depths = rawDepths.flatMap { values -> [UInt32]? in
            guard !values.isEmpty, values.allSatisfy({ $0 > 0 && $0 <= 64 }) else { return nil }
            return Array(Set(values)).sorted()
        }
        // Discard a snapshot taken across a default-device switch or disconnection.
        guard reader.defaultOutput() == id, reader.isAlive(id) == true else { return nil }
        return Self(name: name, sampleRate: rate, bufferFrames: frames, bitDepths: depths)
    }
}

protocol AudioOutputReading {
    func defaultOutput() -> AudioObjectID?
    func isAlive(_ id: AudioObjectID) -> Bool?
    func name(_ id: AudioObjectID) -> String?
    func sampleRate(_ id: AudioObjectID) -> Double?
    func bufferFrames(_ id: AudioObjectID) -> UInt32?
    func bitDepths(_ id: AudioObjectID) -> [UInt32]?
}

private struct SystemAudioOutputReader: AudioOutputReading {
    func defaultOutput() -> AudioObjectID? {
        HardwareScanner.integerProperty(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
    }
    func isAlive(_ id: AudioObjectID) -> Bool? {
        HardwareScanner.integerProperty(id, kAudioDevicePropertyDeviceIsAlive).map { $0 != 0 }
    }
    func name(_ id: AudioObjectID) -> String? { HardwareScanner.stringProperty(id, kAudioObjectPropertyName) }
    func sampleRate(_ id: AudioObjectID) -> Double? { HardwareScanner.sampleRate(id) }
    func bufferFrames(_ id: AudioObjectID) -> UInt32? { HardwareScanner.integerProperty(id, kAudioDevicePropertyBufferFrameSize) }
    func bitDepths(_ id: AudioObjectID) -> [UInt32]? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        let stride = UInt32(MemoryLayout<AudioStreamID>.size)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size > 0, size <= 256 * stride, size % stride == 0 else { return nil }
        var streams = [AudioStreamID](repeating: 0, count: Int(size / stride))
        let capacity = size
        let status = streams.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr, size > 0, size <= capacity, size % stride == 0 else { return nil }
        var depths: [UInt32] = []
        for stream in streams.prefix(Int(size / stride)) {
            var format = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var formatAddress = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyPhysicalFormat,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(stream, &formatAddress, 0, nil, &formatSize, &format) == noErr,
                  formatSize == MemoryLayout<AudioStreamBasicDescription>.size,
                  format.mFormatID == kAudioFormatLinearPCM else { return nil }
            depths.append(format.mBitsPerChannel)
        }
        return depths
    }
}
