// SPDX-License-Identifier: BUSL-1.1
import Darwin
import Foundation

/// Local VM accounting. An estimate, not a replica of Activity Monitor's private accounting.
public struct MemorySnapshot: Sendable {
    public let total: UInt64
    public let used: UInt64?
    public let compressed: UInt64?
    public let swap: UInt64?
    public let pressure: String

    public static func estimatedUsed(total: UInt64, pageSize: UInt64, active: UInt64,
                                     inactive: UInt64, wired: UInt64, compressor: UInt64,
                                     purgeable: UInt64, external: UInt64) -> UInt64? {
        var pages: UInt64 = 0
        for value in [active, inactive, wired, compressor] {
            let sum = pages.addingReportingOverflow(value)
            guard !sum.overflow else { return nil }
            pages = sum.partialValue
        }
        let reclaimable = purgeable.addingReportingOverflow(external)
        guard !reclaimable.overflow, pages >= reclaimable.partialValue else { return nil }
        let bytes = (pages - reclaimable.partialValue).multipliedReportingOverflow(by: pageSize)
        guard !bytes.overflow, pageSize > 0 else { return nil }
        return min(total, bytes.partialValue)
    }

    public static func read() -> MemorySnapshot {
        let total = ProcessInfo.processInfo.physicalMemory
        var vm = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        let hasVM = result == KERN_SUCCESS && host_page_size(host, &pageSize) == KERN_SUCCESS
        var pressure: Int32 = 0
        var pressureSize = MemoryLayout.size(ofValue: pressure)
        let hasPressure = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0
        let pressureText: String
        switch hasPressure ? pressure : 0 {
        case 1: pressureText = "Normal"
        case 2: pressureText = "Elevated"
        case 4: pressureText = "Critical"
        default: pressureText = "Unavailable"
        }
        var swap = xsw_usage()
        var swapSize = MemoryLayout.size(ofValue: swap)
        let hasSwap = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        return MemorySnapshot(total: total,
            used: hasVM ? estimatedUsed(total: total, pageSize: UInt64(pageSize),
                active: UInt64(vm.active_count), inactive: UInt64(vm.inactive_count),
                wired: UInt64(vm.wire_count), compressor: UInt64(vm.compressor_page_count),
                purgeable: UInt64(vm.purgeable_count), external: UInt64(vm.external_page_count)) : nil,
            compressed: hasVM ? UInt64(vm.compressor_page_count) * UInt64(pageSize) : nil,
            swap: hasSwap ? swap.xsu_used : nil, pressure: pressureText)
    }
}
