// SPDX-License-Identifier: BUSL-1.1
import CoreAudio
import CoreMIDI
import Foundation

public struct AudioHardwareRecord: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let name: String
    public let manufacturer: String
    public let transport: String
    public var sampleRate: Double? = nil
    public var bufferFrames: UInt32? = nil
}

public struct MIDIHardwareRecord: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let name: String
    public let manufacturer: String
    public let offline: Bool?
}

public struct DriverRecord: Identifiable, Hashable, Sendable {
    public let path: URL
    public let name: String
    public let bundleIdentifier: String?
    public let version: String?
    public let kind: String
    /// Signer and copyright read from the bundle itself; nil when not yet read.
    public let provenance: BundleProvenance?
    public var id: String { path.path }
    public init(path: URL, name: String, bundleIdentifier: String?, version: String?, kind: String, provenance: BundleProvenance? = nil) {
        self.path = path; self.name = name; self.bundleIdentifier = bundleIdentifier; self.version = version; self.kind = kind; self.provenance = provenance
    }
}

public struct HardwareScanReport: Sendable {
    public let devices: [AudioHardwareRecord]
    public let drivers: [DriverRecord]
    public let midiDevices: [MIDIHardwareRecord]
    public let warnings: [String]
}

/// Enumerates Core Audio device properties only. No audio stream, serial number,
/// firmware probe, driver loading, privileged command or hardware state change.
public enum HardwareScanner {
    public static func scan(driverRoots: [URL] = standardDriverRoots) throws -> HardwareScanReport {
        try Task.checkCancellation()
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var warnings: [String] = []
        var devices: [AudioHardwareRecord] = []
        let system = AudioObjectID(kAudioObjectSystemObject)
        if AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
           size <= 65_536 {
            var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            let status = ids.isEmpty ? noErr : ids.withUnsafeMutableBytes { bytes in
                AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!)
            }
            if status == noErr {
                for id in ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size) {
                    try Task.checkCancellation()
                    var record = AudioHardwareRecord(id: id,
                        name: stringProperty(id, kAudioObjectPropertyName) ?? "Unknown device",
                        manufacturer: stringProperty(id, kAudioObjectPropertyManufacturer) ?? "Unknown manufacturer",
                        transport: transportName(integerProperty(id, kAudioDevicePropertyTransportType)))
                    record.sampleRate = sampleRate(id)
                    record.bufferFrames = integerProperty(id, kAudioDevicePropertyBufferFrameSize).flatMap { $0 > 0 ? $0 : nil }
                    devices.append(record)
                }
            } else { warnings.append("Core Audio device enumeration failed (\(status)).") }
        } else { warnings.append("Core Audio devices could not be enumerated.") }
        let driverResult = try scanDrivers(roots: driverRoots)
        return HardwareScanReport(devices: devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            drivers: driverResult.records, midiDevices: try scanMIDIDevices(), warnings: warnings + driverResult.warnings)
    }

    public static var standardDriverRoots: [URL] {
        ["/Library/Audio/Plug-Ins/HAL", "/Library/Audio/MIDI Drivers", "/Library/Extensions", "/Library/SystemExtensions"].map { URL(fileURLWithPath: $0) }
        + [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Audio/MIDI Drivers")]
    }

    public static func scanDrivers(roots: [URL]) throws -> (records: [DriverRecord], warnings: [String]) {
        var records: [DriverRecord] = []
        var warnings: [String] = []
        var seen = Set<String>()
        for root in roots {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            var incomplete = false
            var depthLimited = false
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in incomplete = true; return true }) else {
                warnings.append("A driver location could not be read."); continue
            }
            var visited = 0
            for case let candidate as URL in enumerator {
                try Task.checkCancellation()
                visited += 1
                if visited > 100_000 { incomplete = true; break }
                let isDriverBundle = ["driver", "plugin", "kext", "systemextension"].contains(candidate.pathExtension.lowercased())
                // Inspect a bundle already found at the boundary without entering it.
                if enumerator.level > 6 && !isDriverBundle {
                    if (try? candidate.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        depthLimited = true
                    }
                    enumerator.skipDescendants()
                    continue
                }
                guard isDriverBundle else { continue }
                enumerator.skipDescendants()
                let values = try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true, seen.insert(candidate.standardizedFileURL.path).inserted else { continue }
                let info = candidate.appendingPathComponent("Contents/Info.plist")
                let properties: [String: Any]?
                if SafeFileAccess.contained(info, in: candidate), let data = SafeFileAccess.data(at: info) {
                    properties = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
                } else { properties = nil }
                guard let kind = audioDriverKind(path: candidate, properties: properties ?? [:]) else { continue }
                if properties == nil { warnings.append("Metadata unavailable for \(candidate.lastPathComponent).") }
                records.append(DriverRecord(path: candidate,
                    name: (properties?["CFBundleName"] as? String).flatMap { DisplaySanitiser.sanitise($0) } ?? DisplaySanitiser.sanitise(candidate.deletingPathExtension().lastPathComponent) ?? "Driver",
                    bundleIdentifier: (properties?["CFBundleIdentifier"] as? String).flatMap { DisplaySanitiser.sanitise($0) },
                    version: (properties?["CFBundleShortVersionString"] as? String).flatMap { DisplaySanitiser.sanitise($0, maximumLength: VersionComparator.maximumLength) },
                    kind: kind, provenance: BundleProvenance.read(at: candidate)))
            }
            if incomplete { warnings.append("Some driver folders could not be read; inventory is incomplete.") }
            if depthLimited { warnings.append("Some driver folders exceeded the search depth and were not searched; inventory is incomplete.") }
        }
        return (records.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, warnings)
    }

    /// No name/vendor substring guesses: unrelated USB, VPN and storage extensions stay out.
    static func audioDriverKind(path: URL, properties: [String: Any]) -> String? {
        let parent = path.deletingLastPathComponent().standardizedFileURL.pathComponents
        if path.pathExtension.lowercased() == "driver", Array(parent.suffix(3)) == ["Audio", "Plug-Ins", "HAL"] {
            return "Core Audio driver"
        }
        if ["plugin", "driver"].contains(path.pathExtension.lowercased()), Array(parent.suffix(2)) == ["Audio", "MIDI Drivers"] {
            return "MIDI driver"
        }
        guard ["kext", "systemextension"].contains(path.pathExtension.lowercased()) else { return nil }
        if let dependencies = properties["OSBundleLibraries"] as? [String: Any], dependencies["com.apple.iokit.IOAudioFamily"] != nil {
            return "Audio system driver · declares IOAudioFamily"
        }
        if let personalities = properties["IOKitPersonalities"] as? [String: [String: Any]],
           personalities.values.contains(where: { personality in
               ["IOProviderClass", "IOClass", "IOUserClass"].contains { field in
                   guard let value = personality[field] as? String else { return false }
                   return ["IOAudioDevice", "IOAudioEngine", "IOUserAudioDriver", "IOUserAudioDevice"].contains(value)
               }
           }) { return "Audio system driver · declared audio class" }
        if properties["CFBundleIdentifier"] as? String == "com.antelopeaudio.driver.AntelopeUnifiedDriver" {
            return "Audio system driver · reviewed identity"
        }
        return nil
    }

    private static func scanMIDIDevices() throws -> [MIDIHardwareRecord] {
        var devices: [MIDIHardwareRecord] = []
        for index in 0..<MIDIGetNumberOfDevices() {
            try Task.checkCancellation()
            let device = MIDIGetDevice(index)
            guard device != 0 else { continue }
            func string(_ key: CFString) -> String? {
                var value: Unmanaged<CFString>?
                guard MIDIObjectGetStringProperty(device, key, &value) == noErr else { return nil }
                return value?.takeRetainedValue() as String?
            }
            var offline: Int32 = 0
            let status = MIDIObjectGetIntegerProperty(device, kMIDIPropertyOffline, &offline)
            devices.append(.init(id: device, name: string(kMIDIPropertyName) ?? "Unnamed MIDI device",
                manufacturer: string(kMIDIPropertyManufacturer) ?? "Unknown manufacturer",
                offline: status == noErr ? offline != 0 : nil))
        }
        return devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    static func sampleRate(_ id: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              value.isFinite, value > 0 else { return nil }
        return value
    }
    static func integerProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
    private static func transportName(_ value: UInt32?) -> String {
        switch value {
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        case kAudioDeviceTransportTypeFireWire: return "FireWire"
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeVirtual: return "Virtual device"
        case kAudioDeviceTransportTypeAggregate: return "Aggregate device"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypePCI: return "PCI"
        case kAudioDeviceTransportTypeAVB: return "AVB network"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: return "Continuity (iPhone or iPad)"
        default: return "Other connection"
        }
    }
}

public struct DriverReleaseRecord: Codable, Sendable {
    public let bundleIdentifier: String
    public let latestVersion: String
    public let sourceURL: URL
    public let checkedOn: String
}

public enum DriverUpdateEvaluator {
    public static func evaluate(_ driver: DriverRecord, catalogue: [DriverReleaseRecord], now: Date = Date()) -> UpdateCheckState {
        let matches = catalogue.filter { $0.bundleIdentifier == driver.bundleIdentifier }
        guard matches.count == 1, let release = matches.first else { return .notChecked }
        guard EvidenceFreshness.isFresh(release.checkedOn, now: now), let version = driver.version else { return .unavailable }
        switch VersionComparator.compare(version, release.latestVersion) {
        case .older: return .updateAvailable
        case .equal: return .current
        case .newer, .incomparable: return .unavailable
        }
    }
}
