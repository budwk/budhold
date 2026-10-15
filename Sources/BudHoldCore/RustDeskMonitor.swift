import Foundation
import AppKit

public struct RustDeskStatus: Sendable, Equatable {
    public let isMonitoringEnabled: Bool
    public let isInstalled: Bool
    public let appPath: String
    public let version: String
    public let deviceID: String
    public let isServerRunning: Bool
    public let isServiceRunning: Bool
    public let activeConnectionCount: Int
    public let activePeerEndpoints: [String]

    public var isReadyForRemote: Bool {
        isMonitoringEnabled && isInstalled && isServerRunning
    }

    public static let disabledPlaceholder = RustDeskStatus(
        isMonitoringEnabled: false,
        isInstalled: false,
        appPath: "/Applications/RustDesk.app",
        version: "-",
        deviceID: "-",
        isServerRunning: false,
        isServiceRunning: false,
        activeConnectionCount: 0,
        activePeerEndpoints: []
    )
}

public final class RustDeskMonitor {
    public static let shared = RustDeskMonitor()

    public let appPath = "/Applications/RustDesk.app"
    public let binaryPath = "/Applications/RustDesk.app/Contents/MacOS/RustDesk"

    private var cachedDeviceID: String?
    private var lastIDFetchTime: Date?

    private init() {}

    public func fetchStatus(enabled: Bool = true) -> RustDeskStatus {
        guard enabled else {
            return .disabledPlaceholder
        }

        let isInstalled = FileManager.default.fileExists(atPath: appPath)
        guard isInstalled else {
            return RustDeskStatus(
                isMonitoringEnabled: true,
                isInstalled: false,
                appPath: appPath,
                version: "未安装",
                deviceID: "-",
                isServerRunning: false,
                isServiceRunning: false,
                activeConnectionCount: 0,
                activePeerEndpoints: []
            )
        }

        let version = readVersion()
        let deviceID = readDeviceID()
        let (serverRunning, serviceRunning) = checkProcesses()
        let peers = checkActiveConnections()

        return RustDeskStatus(
            isMonitoringEnabled: true,
            isInstalled: true,
            appPath: appPath,
            version: version,
            deviceID: deviceID,
            isServerRunning: serverRunning,
            isServiceRunning: serviceRunning,
            activeConnectionCount: peers.count,
            activePeerEndpoints: peers
        )
    }

    private func readVersion() -> String {
        let plistPath = "\(appPath)/Contents/Info.plist"
        if let dict = NSDictionary(contentsOfFile: plistPath),
           let ver = dict["CFBundleShortVersionString"] as? String {
            return ver
        }
        return "未知"
    }

    public func readDeviceID(forceRefresh: Bool = false) -> String {
        if !forceRefresh,
           let cached = cachedDeviceID,
           let last = lastIDFetchTime,
           Date().timeIntervalSince(last) < 60 {
            return cached
        }

        if let out = SystemInfoService.runCommand(binaryPath, args: ["--get-id"]),
           !out.isEmpty {
            let cleanID = out.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? out
            cachedDeviceID = cleanID
            lastIDFetchTime = Date()
            return cleanID
        }
        return cachedDeviceID ?? "未知"
    }

    private func checkProcesses() -> (serverRunning: Bool, serviceRunning: Bool) {
        guard let output = SystemInfoService.runCommand("/bin/ps", args: ["-ax", "-o", "command"]) else {
            return (false, false)
        }
        var serverRunning = false
        var serviceRunning = false
        for line in output.components(separatedBy: .newlines) {
            if line.contains("RustDesk.app/Contents/MacOS/RustDesk") {
                serverRunning = true
            }
            if line.contains("RustDesk.app/Contents/MacOS/service") {
                serviceRunning = true
            }
        }
        return (serverRunning, serviceRunning)
    }

    private func checkActiveConnections() -> [String] {
        guard let output = SystemInfoService.runCommand("/usr/sbin/lsof", args: ["-nP", "-iTCP", "-sTCP:ESTABLISHED", "-a", "-c", "RustDesk"]) else {
            return []
        }
        var endpoints: [String] = []
        for line in output.components(separatedBy: .newlines).dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if let nameCol = parts.first(where: { $0.contains("->") }) {
                let conn = String(nameCol)
                // 过滤本机回环连接
                if !conn.contains("127.0.0.1") && !conn.contains("[::1]") {
                    endpoints.append(conn)
                }
            }
        }
        return endpoints
    }

    /// 启动或拉起 RustDesk 客户端与后台服务
    @discardableResult
    public func launchRustDesk() -> Bool {
        guard FileManager.default.fileExists(atPath: appPath) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appPath]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
