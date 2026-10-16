import Foundation

/// 管理 macOS 开机自启动 (~/Library/LaunchAgents/com.budwk.app.budhold.plist)
public final class LaunchAgentManager {
    public static let shared = LaunchAgentManager()

    public let label = "com.budwk.app.budhold"

    public var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private init() {}

    public var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool, appExecutablePath: String? = nil) -> Bool {
        if enabled {
            let execPath = appExecutablePath ?? resolveDefaultExecutablePath()
            let plistDict: [String: Any] = [
                "Label": label,
                "ProgramArguments": [execPath, "--auto-enable"],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive"
            ]
            do {
                let dir = plistURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
                try data.write(to: plistURL, options: .atomic)
                return true
            } catch {
                return false
            }
        } else {
            guard FileManager.default.fileExists(atPath: plistURL.path) else { return true }
            do {
                try FileManager.default.removeItem(at: plistURL)
                return true
            } catch {
                return false
            }
        }
    }

    private func resolveDefaultExecutablePath() -> String {
        let installedAppBinary = "/Applications/BudHold.app/Contents/MacOS/BudHoldApp"
        if FileManager.default.fileExists(atPath: installedAppBinary) {
            return installedAppBinary
        }
        return Bundle.main.executablePath ?? installedAppBinary
    }
}
