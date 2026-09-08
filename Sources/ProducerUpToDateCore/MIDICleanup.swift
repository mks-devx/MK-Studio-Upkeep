// SPDX-License-Identifier: MPL-2.0
import CoreMIDI
import Foundation

/// Removes saved entries for MIDI devices that are not connected, through Core MIDI's own
/// setup API. No file is touched and no password is needed. Connected devices and the
/// entries macOS provides itself are refused; reconnecting a removed device recreates it.
public enum MIDICleanup {
    public enum Refusal: String, Error, LocalizedError {
        case connected = "This device is connected right now. Unplug it first; removing a live device breaks apps using it."
        case system = "This entry is part of macOS and cannot be removed."
        case vanished = "This entry is no longer in the MIDI setup. Scan again."
        case failed = "macOS refused to remove the entry."
        public var errorDescription: String? { rawValue }
    }

    public static let consequence = "macOS forgets this device. If you plug it in again it reappears with default settings; any custom name or port setup you made in Audio MIDI Setup is lost. Driver software is not removed."

    public static func protection(_ device: MIDIHardwareRecord) -> RemovalProtection {
        if device.isSystemVirtual { return .doNotDelete("Part of macOS: a virtual MIDI connection between apps or over the network. It cannot be removed.") }
        if device.offline != true { return .doNotDelete("Connected right now. Unplug it first; removing a live device breaks apps that use it.") }
        return .caution(consequence)
    }

    public static func isRemovable(_ device: MIDIHardwareRecord) -> Bool {
        if case .caution = protection(device) { return true }
        return false
    }

    /// Re-reads the live setup before acting: the entry must still exist, match by name and
    /// still be offline. Driver-owned and user-created (external) devices use different calls.
    public static func remove(_ device: MIDIHardwareRecord) throws {
        guard isRemovable(device) else { throw device.isSystemVirtual ? Refusal.system : Refusal.connected }
        func name(_ ref: MIDIObjectRef) -> String? {
            var value: Unmanaged<CFString>?
            guard MIDIObjectGetStringProperty(ref, kMIDIPropertyName, &value) == noErr else { return nil }
            return value?.takeRetainedValue() as String?
        }
        func offline(_ ref: MIDIObjectRef) -> Bool? {
            var value: Int32 = 0
            return MIDIObjectGetIntegerProperty(ref, kMIDIPropertyOffline, &value) == noErr ? value != 0 : nil
        }
        for index in 0..<MIDIGetNumberOfDevices() {
            let ref = MIDIGetDevice(index)
            guard ref == device.id, name(ref) == device.name else { continue }
            guard offline(ref) == true else { throw Refusal.connected }
            guard MIDISetupRemoveDevice(ref) == noErr else { throw Refusal.failed }
            return
        }
        for index in 0..<MIDIGetNumberOfExternalDevices() {
            let ref = MIDIGetExternalDevice(index)
            guard ref == device.id, name(ref) == device.name else { continue }
            guard MIDISetupRemoveExternalDevice(ref) == noErr else { throw Refusal.failed }
            return
        }
        throw Refusal.vanished
    }
}
