import Foundation
import IOKit
import IOKit.pwr_mgt
import CoreGraphics

public enum KeepAwakeDuration: Int, CaseIterable, Identifiable, Sendable {
    case infinite = 0
    case oneHour = 3600
    case twoHours = 7200
    case fourHours = 14400
    case eightHours = 28800
    case twentyFourHours = 86400

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .infinite: return L10n.tr("始终保持（不限时）", "Indefinitely (Always On)")
        case .oneHour: return L10n.tr("1 小时", "1 Hour")
        case .twoHours: return L10n.tr("2 小时", "2 Hours")
        case .fourHours: return L10n.tr("4 小时", "4 Hours")
        case .eightHours: return L10n.tr("8 小时", "8 Hours")
        case .twentyFourHours: return L10n.tr("24 小时", "24 Hours")
        }
    }
}

public struct LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let message: String
    public let isWarning: Bool

    public var formattedTime: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: timestamp)
    }
}

public final class PowerKeepAliveManager {
    public static let shared = PowerKeepAliveManager()

    private var systemSleepAssertionID: IOPMAssertionID = 0
    private var displaySleepAssertionID: IOPMAssertionID = 0
    private var hasSystemAssertion: Bool = false
    private var hasDisplayAssertion: Bool = false
    private var caffeinateProcess: Process?

    public private(set) var isIdleKeepAwakeActive: Bool = false
    public private(set) var isClamshellKeepAwakeActive: Bool = false
    public var keepDisplayRendererAwake: Bool = true

    public var lowBatteryAutoRestoreEnabled: Bool = true
    public var lowBatteryThreshold: Int = 20
    public var restoreSleepOnAppQuit: Bool = false

    public private(set) var expirationDate: Date?
    public private(set) var logs: [LogEntry] = []

    public var onStateChanged: (() -> Void)?

    private let sudoersFilePath = "/etc/sudoers.d/budhold"

    private init() {
        syncInitialKernelState()
    }

    public func syncInitialKernelState() {
        let (_, sleepDisabled) = SystemInfoService.readIOPMRootDomainState()
        isClamshellKeepAwakeActive = sleepDisabled
    }

    public func appendLog(_ message: String, isWarning: Bool = false) {
        let entry = LogEntry(timestamp: Date(), message: message, isWarning: isWarning)
        DispatchQueue.main.async {
            self.logs.insert(entry, at: 0)
            if self.logs.count > 100 {
                self.logs.removeLast(self.logs.count - 100)
            }
            self.onStateChanged?()
        }
    }

    // MARK: - 一键开启「合盖+关屏不休眠」全天候模式

    @discardableResult
    public func enableFullRemoteReadyMode(duration: KeepAwakeDuration = .infinite) -> (success: Bool, message: String) {
        // 1. 开启 IOKit 系统与显示器防休眠断言 + caffeinate 守护
        let idleOk = enableIdleKeepAwake(preventDisplaySleep: true, duration: duration)

        // 2. 唤醒显示器帧缓冲，确保当前屏幕未黑屏休眠
        DisplayBrightnessController.shared.wakeDisplayFramebuffer()

        // 3. 开启内核级合盖不休眠 (pmset -a disablesleep 1 tcpkeepalive 1 womp 1)
        let (clamshellOk, errMsg) = setKernelClamshellSleepDisabled(true)

        if idleOk && clamshellOk {
            let msg = L10n.tr(
                "已开启「合盖+关屏不休眠」全天候模式，电脑合盖或关屏均保持运行",
                "Full Keep-Awake enabled: Mac will stay awake with lid closed or display off"
            )
            appendLog(msg)
            return (true, msg)
        } else if idleOk && !clamshellOk {
            let msg = L10n.tr(
                "已开启防空闲/关屏睡眠，但「合盖不休眠」需要管理员授权：\(errMsg)",
                "Idle sleep prevented, but Clamshell Keep-Awake requires admin privilege: \(errMsg)"
            )
            appendLog(msg, isWarning: true)
            return (false, msg)
        } else {
            let msg = L10n.tr("开启防休眠失败：\(errMsg)", "Failed to enable Keep-Awake: \(errMsg)")
            appendLog(msg, isWarning: true)
            return (false, msg)
        }
    }

    /// 一键关闭所有防休眠并恢复 macOS 默认睡眠机制
    @discardableResult
    public func disableAllKeepAwake() -> (success: Bool, message: String) {
        disableIdleKeepAwake()
        if DisplayBrightnessController.shared.isBlackoutModeActive {
            _ = DisplayBrightnessController.shared.disableBlackoutMode()
        }
        let (_, sleepDisabled) = SystemInfoService.readIOPMRootDomainState()
        if sleepDisabled {
            let (ok, err) = setKernelClamshellSleepDisabled(false)
            if !ok {
                let msg = L10n.tr(
                    "已释放 IOKit 防睡眠锁，但恢复合盖睡眠失败：\(err)",
                    "IOKit assertions released, but failed to restore lid sleep: \(err)"
                )
                appendLog(msg, isWarning: true)
                return (false, msg)
            }
        } else {
            isClamshellKeepAwakeActive = false
        }
        let msg = L10n.tr(
            "已关闭防休眠保护，系统已恢复默认合盖与空闲睡眠策略",
            "Keep-Awake disabled. Default system and lid sleep restored"
        )
        appendLog(msg)
        return (true, msg)
    }

    // MARK: - 第一层：IOKit 防空闲睡眠 & 防显示器休眠 + caffeinate

    @discardableResult
    public func enableIdleKeepAwake(preventDisplaySleep: Bool = true, duration: KeepAwakeDuration = .infinite) -> Bool {
        releaseIOKitAssertions()
        stopCaffeinateProcess()

        let reason = "BudHold Clamshell & Display Keep-Awake" as CFString

        let sysRet = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemSleepAssertionID
        )
        hasSystemAssertion = (sysRet == kIOReturnSuccess)

        if preventDisplaySleep {
            let dispRet = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &displaySleepAssertionID
            )
            hasDisplayAssertion = (dispRet == kIOReturnSuccess)
        }

        startCaffeinateProcess(preventDisplaySleep: preventDisplaySleep, durationSeconds: duration.rawValue)

        if duration == .infinite {
            expirationDate = nil
        } else {
            expirationDate = Date().addingTimeInterval(TimeInterval(duration.rawValue))
        }

        isIdleKeepAwakeActive = hasSystemAssertion
        appendLog(L10n.tr(
            "IOKit 防休眠断言已激活 (系统防休眠: \(hasSystemAssertion ? "是" : "否"), 显示渲染保持: \(hasDisplayAssertion ? "是" : "否"))",
            "IOKit assertions active (System: \(hasSystemAssertion ? "Yes" : "No"), Display: \(hasDisplayAssertion ? "Yes" : "No"))"
        ))
        onStateChanged?()
        return hasSystemAssertion
    }

    public func disableIdleKeepAwake() {
        releaseIOKitAssertions()
        stopCaffeinateProcess()
        expirationDate = nil
        isIdleKeepAwakeActive = false
        appendLog(L10n.tr("IOKit 防空闲与防关屏休眠断言已释放", "IOKit idle & display sleep assertions released"))
        onStateChanged?()
    }

    public func updateDuration(_ duration: KeepAwakeDuration) {
        if duration == .infinite {
            expirationDate = nil
        } else if isIdleKeepAwakeActive || isClamshellKeepAwakeActive {
            expirationDate = Date().addingTimeInterval(TimeInterval(duration.rawValue))
        }
        if isIdleKeepAwakeActive {
            startCaffeinateProcess(preventDisplaySleep: hasDisplayAssertion, durationSeconds: duration.rawValue)
        }
        appendLog(L10n.tr("已更新保活时长设置：\(duration.title)", "Keep-Awake duration updated: \(duration.title)"))
        onStateChanged?()
    }

    private func releaseIOKitAssertions() {
        if hasSystemAssertion {
            IOPMAssertionRelease(systemSleepAssertionID)
            systemSleepAssertionID = 0
            hasSystemAssertion = false
        }
        if hasDisplayAssertion {
            IOPMAssertionRelease(displaySleepAssertionID)
            displaySleepAssertionID = 0
            hasDisplayAssertion = false
        }
    }

    private func startCaffeinateProcess(preventDisplaySleep: Bool, durationSeconds: Int) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        var args = ["-i", "-m", "-s", "-u"]
        if preventDisplaySleep {
            args.insert("-d", at: 0)
        }
        if durationSeconds > 0 {
            args.append(contentsOf: ["-t", "\(durationSeconds)"])
        }
        proc.arguments = args
        do {
            try proc.run()
            caffeinateProcess = proc
        } catch {
            caffeinateProcess = nil
        }
    }

    private func stopCaffeinateProcess() {
        if let proc = caffeinateProcess, proc.isRunning {
            proc.terminate()
        }
        caffeinateProcess = nil
    }

    // MARK: - 第二层：内核级合盖不休眠 (pmset disablesleep)

    public var isPasswordlessSudoInstalled: Bool {
        guard FileManager.default.fileExists(atPath: sudoersFilePath) else {
            return false
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", "/usr/bin/pmset", "-g"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 配置 /etc/sudoers.d/budhold 免密执行 pmset，使合盖不休眠开关无需每次输入密码
    public func installPasswordlessSudoers() -> (success: Bool, message: String) {
        let username = NSUserName()
        let rule = "\(username) ALL=(ALL) NOPASSWD: /usr/bin/pmset"
        let script = """
        echo '\(rule)' > /private/tmp/budhold_sudoers && \
        /usr/sbin/chown root:wheel /private/tmp/budhold_sudoers && \
        /bin/chmod 0440 /private/tmp/budhold_sudoers && \
        /usr/sbin/visudo -cf /private/tmp/budhold_sudoers && \
        /bin/mv /private/tmp/budhold_sudoers \(sudoersFilePath)
        """
        let (ok, err) = runWithPrivileges(script)
        if ok {
            appendLog(L10n.tr("已成功安装 pmset 免密授权规则 (\(sudoersFilePath))", "Installed passwordless sudo rule for pmset (\(sudoersFilePath))"))
            onStateChanged?()
            return (true, L10n.tr("免密授权配置成功，后续切换合盖不休眠将无需输入密码", "Passwordless sudo configured successfully"))
        } else {
            appendLog(L10n.tr("配置免密授权失败：\(err)", "Failed to configure passwordless sudo: \(err)"), isWarning: true)
            return (false, err)
        }
    }

    public func removePasswordlessSudoers() -> (success: Bool, message: String) {
        guard FileManager.default.fileExists(atPath: sudoersFilePath) else {
            return (true, L10n.tr("免密规则未安装", "Passwordless rule not installed"))
        }
        let (ok, err) = runWithPrivileges("/bin/rm -f \(sudoersFilePath)")
        if ok {
            appendLog(L10n.tr("已移除 pmset 免密授权规则", "Removed passwordless sudo rule for pmset"))
            onStateChanged?()
            return (true, L10n.tr("已移除免密授权规则", "Removed passwordless sudo rule"))
        } else {
            return (false, err)
        }
    }

    @discardableResult
    public func setKernelClamshellSleepDisabled(_ disabled: Bool) -> (success: Bool, errorMessage: String) {
        let cmd: String
        if disabled {
            // disablesleep 1: 阻止任何睡眠（含 MacBook 合盖）
            // tcpkeepalive 1: 保持网络连接不断开
            // womp 1: 开启网络唤醒支持
            cmd = "/usr/bin/pmset -a disablesleep 1 tcpkeepalive 1 womp 1"
        } else {
            cmd = "/usr/bin/pmset -a disablesleep 0"
        }

        // 优先尝试 sudo -n 免密执行
        if runSudoNoPassword(cmd) {
            let (_, actualDisabled) = SystemInfoService.readIOPMRootDomainState()
            isClamshellKeepAwakeActive = actualDisabled
            appendLog(disabled
                ? L10n.tr("已启用内核级合盖不休眠 (SleepDisabled = Yes)", "Kernel Clamshell Keep-Awake enabled (SleepDisabled = Yes)")
                : L10n.tr("已恢复系统默认合盖休眠 (SleepDisabled = No)", "Default lid sleep restored (SleepDisabled = No)")
            )
            onStateChanged?()
            return (true, "")
        }

        // 回退到 macOS 管理员权限授权弹窗
        let (ok, err) = runWithPrivileges(cmd)
        let (_, actualDisabled) = SystemInfoService.readIOPMRootDomainState()
        isClamshellKeepAwakeActive = actualDisabled
        if ok {
            appendLog(disabled
                ? L10n.tr("已通过管理员授权启用合盖不休眠 (SleepDisabled = Yes)", "Clamshell Keep-Awake enabled with admin authorization (SleepDisabled = Yes)")
                : L10n.tr("已恢复系统默认合盖休眠 (SleepDisabled = No)", "Default lid sleep restored (SleepDisabled = No)")
            )
        } else {
            appendLog(L10n.tr("执行 pmset 失败：\(err)", "pmset execution failed: \(err)"), isWarning: true)
        }
        onStateChanged?()
        return (ok, err)
    }

    private func runSudoNoPassword(_ command: String) -> Bool {
        let parts = command.split(separator: " ").map(String.init)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n"] + parts
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runWithPrivileges(_ shellCommand: String) -> (Bool, String) {
        // 如果当前进程本身就是 root (uid == 0)
        if getuid() == 0 {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = ["-c", shellCommand]
            let errPipe = Pipe()
            proc.standardOutput = Pipe()
            proc.standardError = errPipe
            do {
                try proc.run()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    return (true, "")
                }
                let errStr = String(data: errData, encoding: .utf8) ?? "未知错误"
                return (false, errStr)
            } catch {
                return (false, error.localizedDescription)
            }
        }

        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScriptSource = "do shell script \"\(escaped)\" with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", appleScriptSource]
        let errPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = errPipe
        do {
            try proc.run()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                return (true, "")
            } else {
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "用户取消或授权失败"
                return (false, errStr)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - 第三层：周期性守护巡检（合盖/关屏渲染保活、低电量安全恢复、定时到期检查）

    public func performPeriodicTick() {
        let status = SystemInfoService.shared.fetchPowerAndLidStatus()
        isClamshellKeepAwakeActive = status.isKernelSleepDisabled

        // 1. 检查定时是否到期
        if let exp = expirationDate, Date() >= exp {
            appendLog(L10n.tr("定时防休眠时间已到，正在自动恢复系统默认休眠设置", "Scheduled Keep-Awake duration ended. Restoring default sleep settings"), isWarning: true)
            expirationDate = nil
            _ = disableAllKeepAwake()
            return
        }

        // 2. 低电量安全保护：如果在用电池且电量 <= 阈值，自动关闭合盖不休眠防止背包过热/亏电
        if lowBatteryAutoRestoreEnabled && !status.isACPower && !status.isCharging && status.batteryPercentage <= lowBatteryThreshold {
            if status.isKernelSleepDisabled {
                appendLog(L10n.tr(
                    "⚠️ 检测到电池供电且电量低至 \(status.batteryPercentage)% (≤\(lowBatteryThreshold)%)，触发防闷烧安全保护，自动恢复合盖睡眠！",
                    "⚠️ Battery on \(status.batteryPercentage)% (≤\(lowBatteryThreshold)%). Safety protection triggered: restoring lid sleep!"
                ), isWarning: true)
                _ = setKernelClamshellSleepDisabled(false)
            }
        }

        // 3. 保持显示渲染管线活跃（即使显示器被关闭或 MacBook 合盖，也确保 WindowServer 不停止帧缓冲刷新，防止远控黑屏）
        if (isIdleKeepAwakeActive || isClamshellKeepAwakeActive) && keepDisplayRendererAwake {
            if status.isDisplayAsleep || status.isClamshellClosed {
                DisplayBrightnessController.shared.wakeDisplayFramebuffer()
            }
        }
    }
}
