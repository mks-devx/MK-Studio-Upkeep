// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum MachOArchitectureDetector {
    private enum Magic {
        static let mach32: UInt32 = 0xFEED_FACE
        static let mach32Swapped: UInt32 = 0xCEFA_EDFE
        static let mach64: UInt32 = 0xFEED_FACF
        static let mach64Swapped: UInt32 = 0xCFFA_EDFE
        static let fat32: UInt32 = 0xCAFE_BABE
        static let fat32Swapped: UInt32 = 0xBEBA_FECA
        static let fat64: UInt32 = 0xCAFE_BABF
        static let fat64Swapped: UInt32 = 0xBFBA_FECA
    }

    private enum CPU {
        static let i386: UInt32 = 7
        static let x86_64: UInt32 = 0x0100_0007
        static let arm: UInt32 = 12
        static let arm64: UInt32 = 0x0100_000C
    }

    public static func architectures(at url: URL) -> [BinaryArchitecture] {
        guard let data = SafeFileAccess.prefix(at: url, count: 4096), data.count >= 8 else { return [] }

        return architectures(in: data)
    }

    public static func architectures(in data: Data) -> [BinaryArchitecture] {
        guard let magic = data.uint32(at: 0, endian: .big) else {
            return []
        }

        switch magic {
        case Magic.fat32:
            return fatArchitectures(in: data, is64Bit: false, endian: .big)
        case Magic.fat32Swapped:
            return fatArchitectures(in: data, is64Bit: false, endian: .little)
        case Magic.fat64:
            return fatArchitectures(in: data, is64Bit: true, endian: .big)
        case Magic.fat64Swapped:
            return fatArchitectures(in: data, is64Bit: true, endian: .little)
        case Magic.mach32, Magic.mach64:
            guard data.count >= (magic == Magic.mach64 ? 32 : 28) else { return [] }
            return thinArchitecture(in: data, endian: .big, is64Bit: magic == Magic.mach64)
        case Magic.mach32Swapped, Magic.mach64Swapped:
            guard data.count >= (magic == Magic.mach64Swapped ? 32 : 28) else { return [] }
            return thinArchitecture(in: data, endian: .little, is64Bit: magic == Magic.mach64Swapped)
        default:
            return []
        }
    }

    private static func thinArchitecture(
        in data: Data,
        endian: Data.IntegerEndian,
        is64Bit: Bool
    ) -> [BinaryArchitecture] {
        guard let cpuType = data.uint32(at: 4, endian: endian) else {
            return []
        }

        // Reject contradictory CPU/header widths instead of trusting one field.
        if [CPU.arm64, CPU.x86_64].contains(cpuType), !is64Bit { return [] }
        if [CPU.arm, CPU.i386].contains(cpuType), is64Bit { return [] }

        return [architecture(for: cpuType)]
    }

    private static func fatArchitectures(
        in data: Data,
        is64Bit: Bool,
        endian: Data.IntegerEndian
    ) -> [BinaryArchitecture] {
        guard let count = data.uint32(at: 4, endian: endian) else {
            return []
        }

        let stride = is64Bit ? 32 : 20
        guard count > 0, count <= 64, data.count >= 8 + Int(count) * stride else { return [] }
        let safeCount = Int(count)
        var result: [BinaryArchitecture] = []

        for index in 0..<safeCount {
            let offset = 8 + (index * stride)
            guard let cpuType = data.uint32(at: offset, endian: endian) else {
                break
            }

            let architecture = architecture(for: cpuType)
            if !result.contains(architecture) {
                result.append(architecture)
            }
        }

        return result.sorted { $0.rawValue < $1.rawValue }
    }

    private static func architecture(for cpuType: UInt32) -> BinaryArchitecture {
        switch cpuType {
        case CPU.arm64:
            return .arm64
        case CPU.x86_64:
            return .x86_64
        case CPU.arm:
            return .arm
        case CPU.i386:
            return .i386
        default:
            return .unknown
        }
    }
}

private extension Data {
    enum IntegerEndian {
        case big
        case little
    }

    func uint32(at offset: Int, endian: IntegerEndian) -> UInt32? {
        guard offset >= 0, count >= offset + 4 else {
            return nil
        }

        let bytes = dropFirst(offset).prefix(4)
        switch endian {
        case .big:
            return bytes.reduce(UInt32.zero) { partial, byte in
                (partial << 8) | UInt32(byte)
            }
        case .little:
            return bytes.reversed().reduce(UInt32.zero) { partial, byte in
                (partial << 8) | UInt32(byte)
            }
        }
    }
}
