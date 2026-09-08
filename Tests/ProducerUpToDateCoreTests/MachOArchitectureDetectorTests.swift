// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class MachOArchitectureDetectorTests: XCTestCase {
    func testSlicedDataAndContradictoryCPUWidth() {
        var data = Data([0])
        data.appendLittleEndian(0xFEED_FACF)
        data.appendLittleEndian(0x0100_0007)
        data.append(Data(repeating: 0, count: 24))
        XCTAssertEqual(MachOArchitectureDetector.architectures(in: data.dropFirst()), [.x86_64])
        var invalid = Data()
        invalid.appendLittleEndian(0xFEED_FACE)
        invalid.appendLittleEndian(0x0100_000C)
        invalid.append(Data(repeating: 0, count: 24))
        XCTAssertEqual(MachOArchitectureDetector.architectures(in: invalid), [])
    }

    func testThinIntelAndARMHeadersInBothByteOrders() {
        for (cpu, expected, is64) in [(UInt32(0x0100_0007), BinaryArchitecture.x86_64, true),
                                      (0x0100_000C, .arm64, true), (7, .i386, false)] {
            for little in [true, false] {
                var data = Data()
                let magic: UInt32 = is64 ? 0xFEED_FACF : 0xFEED_FACE
                if little { data.appendLittleEndian(magic); data.appendLittleEndian(cpu) }
                else { data.appendBigEndian(magic); data.appendBigEndian(cpu) }
                data.append(Data(repeating: 0, count: is64 ? 24 : 20))
                XCTAssertEqual(MachOArchitectureDetector.architectures(in: data), [expected])
                for length in 0..<data.count {
                    XCTAssertEqual(MachOArchitectureDetector.architectures(in: data.prefix(length)), [])
                }
            }
        }
    }

    func testFat32And64HeadersInBothByteOrders() {
        for is64 in [true, false] {
            for little in [true, false] {
                var data = Data()
                let append: (inout Data, UInt32) -> Void = { bytes, value in
                    if little { bytes.appendLittleEndian(value) } else { bytes.appendBigEndian(value) }
                }
                append(&data, is64 ? 0xCAFE_BABF : 0xCAFE_BABE)
                append(&data, 2)
                for cpu: UInt32 in [0x0100_0007, 0x0100_000C] {
                    append(&data, cpu)
                    data.append(Data(repeating: 0, count: is64 ? 28 : 16))
                }
                XCTAssertEqual(Set(MachOArchitectureDetector.architectures(in: data)), [.arm64, .x86_64])
                XCTAssertEqual(MachOArchitectureDetector.architectures(in: data.dropLast()), [])
            }
        }
    }

    func testDetectsThinARM64MachO() {
        var data = Data()
        data.append(contentsOf: [0xCF, 0xFA, 0xED, 0xFE])
        data.appendLittleEndian(UInt32(0x0100_000C))
        data.append(Data(repeating: 0, count: 24))

        XCTAssertEqual(
            MachOArchitectureDetector.architectures(in: data),
            [.arm64]
        )
    }

    func testDetectsUniversalARM64AndIntelMachO() {
        var data = Data()
        data.appendBigEndian(UInt32(0xCAFE_BABE))
        data.appendBigEndian(UInt32(2))

        data.appendBigEndian(UInt32(0x0100_000C))
        data.append(Data(repeating: 0, count: 16))

        data.appendBigEndian(UInt32(0x0100_0007))
        data.append(Data(repeating: 0, count: 16))

        XCTAssertEqual(
            Set(MachOArchitectureDetector.architectures(in: data)),
            Set([.arm64, .x86_64])
        )
    }

    func testRejectsNonMachOData() {
        XCTAssertEqual(
            MachOArchitectureDetector.architectures(
                in: Data("not a binary".utf8)
            ),
            []
        )
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }
}
