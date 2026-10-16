import Foundation
import IOKit
import IOKit.ps
import CoreGraphics

public struct MacOSVersionInfo: Sendable, Equatable {
    public let productName: String
    public let productVersion: String
    public let buildVersion: String
    public let architecture: String
    public let cpuBrand: String
    public let hardwareModel: String
    public let hostName: String

    public var fullDisplayString: String {
        "\(productName) \(productVersion) (\(buildVersion)) · \(cpuBrand)"
    }

    public var versionBadgeString: String {
        "\(productName) \(productVersion) (Build \(buildVersion))"
    }
}

public struct PowerAndLidStatus: Sendable, Equatable {
    public let isClamshellClosed: Bool      // AppleClamshellState (是否合盖)
    public let isKernelSleepDisabled: Bool  // SleepDisabled / pmset disablesleep (是否内核级禁止合盖睡眠)
    public let isDisplayAsleep: Bool        // CGDisplayIsAsleep (显示器渲染是否休眠)
    public let isACPower: Bool              // 是否连接外接电源
    public let batteryPercentage: Int       // 电池电量百分比 (0-100)
    public let isCharging: Bool             // 是否正在充电
    public let displayBrightness: Float     // 当前主屏幕背光亮度 (0.0 - 1.0)
}

public final class SystemInfoService {
    public static let shared = SystemInfoService()

    public private(set) lazy var osInfo: MacOSVersionInfo = Self.fetchMacOSVersionInfo()

    private init() {}

    public static func fetchMacOSVersionInfo() -> MacOSVersionInfo {
        let productName = runCommand("/usr/bin/sw_vers", args: ["-productName"]) ?? "macOS"
        let productVersion: String
        if let ver = runCommand("/usr/bin/sw_vers", args: ["-productVersion"]), !ver.isEmpty {
            productVersion = ver
        } else {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            productVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        }
        let buildVersion = runCommand("/usr/bin/sw_vers", args: ["-buildVersion"]) ?? "Unknown"

        #if arch(arm64)
        let arch = "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        let arch = "x86_64 (Intel)"
        #else
        let arch = "unknown"
        #endif

        let cpuBrand = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        let hwModel = sysctlString("hw.model") ?? "Mac"
        let hostName = ProcessInfo.processInfo.hostName

        return MacOSVersionInfo(
            productName: productName,
            productVersion: productVersion,
            buildVersion: buildVersion,
            architecture: arch,
            cpuBrand: cpuBrand,
            hardwareModel: hwModel,
            hostName: hostName
        )
    }

    public func fetchPowerAndLidStatus() -> PowerAndLidStatus {
        let (clamshell, sleepDisabled) = Self.readIOPMRootDomainState()
        let displayAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        let (isAC, pct, charging) = Self.readPowerSourceState()
        let brightness = DisplayBrightnessController.shared.getBrightness() ?? 1.0

        return PowerAndLidStatus(
            isClamshellClosed: clamshell,
            isKernelSleepDisabled: sleepDisabled,
            isDisplayAsleep: displayAsleep,
            isACPower: isAC,
            batteryPercentage: pct,
            isCharging: charging,
            displayBrightness: brightness
        )
    }

    public static func readIOPMRootDomainState() -> (isClamshellClosed: Bool, isKernelSleepDisabled: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else {
            return (false, false)
        }
        defer { IOObjectRelease(service) }

        var clamshellClosed = false
        if let cfProp = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
            if let num = cfProp as? NSNumber {
                clamshellClosed = num.boolValue
            }
        }

        var sleepDisabled = false
        if let cfProp = IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
            if let num = cfProp as? NSNumber {
                sleepDisabled = num.boolValue
            }
        }

        return (clamshellClosed, sleepDisabled)
    }

    public static func readPowerSourceState() -> (isACPower: Bool, percentage: Int, isCharging: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return (true, 100, false)
        }

        var isAC = true
        if let powerType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? {
            isAC = (powerType == kIOPSACPowerValue)
        }

        var percentage = 100
        var isCharging = false

        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                if let cur = desc[kIOPSCurrentCapacityKey as String] as? Int,
                   let max = desc[kIOPSMaxCapacityKey as String] as? Int, max > 0 {
                    percentage = Int(round(Double(cur) / Double(max) * 100.0))
                }
                if let charging = desc[kIOPSIsChargingKey as String] as? Bool {
                    isCharging = charging
                }
            }
        }

        return (isAC, percentage, isCharging)
    }

    public static func sysctlString(_ name: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func runCommand(_ executable: String, args: [String], timeout: TimeInterval = 5.0) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
