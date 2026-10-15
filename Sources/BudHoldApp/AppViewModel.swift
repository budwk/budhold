import Foundation
import AppKit
import Combine
import BudHoldCore

@MainActor
public final class AppViewModel: ObservableObject {
    public static let shared = AppViewModel()

    @Published public var osInfo: MacOSVersionInfo
    @Published public var powerStatus: PowerAndLidStatus
    @Published public var rustDeskStatus: RustDeskStatus

    @Published public var isIdleKeepAwakeActive: Bool = false
    @Published public var isClamshellKeepAwakeActive: Bool = false
    @Published public var isBlackoutModeActive: Bool = false
    @Published public var isPasswordlessSudoInstalled: Bool = false
    @Published public var isLaunchAtLoginEnabled: Bool = false

    @Published public var selectedDuration: KeepAwakeDuration = .infinite
    @Published public var keepDisplayRendererAwake: Bool = true {
        didSet { PowerKeepAliveManager.shared.keepDisplayRendererAwake = keepDisplayRendererAwake }
    }
    @Published public var rustDeskWatchdogEnabled: Bool = true {
        didSet { PowerKeepAliveManager.shared.rustDeskWatchdogEnabled = rustDeskWatchdogEnabled }
    }
    @Published public var lowBatteryAutoRestoreEnabled: Bool = true {
        didSet { PowerKeepAliveManager.shared.lowBatteryAutoRestoreEnabled = lowBatteryAutoRestoreEnabled }
    }
    @Published public var lowBatteryThreshold: Int = 20 {
        didSet { PowerKeepAliveManager.shared.lowBatteryThreshold = lowBatteryThreshold }
    }
    @Published public var restoreSleepOnAppQuit: Bool = false {
        didSet { PowerKeepAliveManager.shared.restoreSleepOnAppQuit = restoreSleepOnAppQuit }
    }

    @Published public var logs: [LogEntry] = []
    @Published public var statusToast: String?

    private var timer: Timer?
    public var onStatusBarNeedsUpdate: (() -> Void)?

    public var isFullRemoteModeActive: Bool {
        isIdleKeepAwakeActive && isClamshellKeepAwakeActive
    }

    private init() {
        self.osInfo = SystemInfoService.shared.osInfo
        self.powerStatus = SystemInfoService.shared.fetchPowerAndLidStatus()
        self.rustDeskStatus = RustDeskMonitor.shared.fetchStatus()

        let mgr = PowerKeepAliveManager.shared
        self.isIdleKeepAwakeActive = mgr.isIdleKeepAwakeActive
        self.isClamshellKeepAwakeActive = powerStatus.isKernelSleepDisabled
        self.isBlackoutModeActive = DisplayBrightnessController.shared.isBlackoutModeActive
        self.isPasswordlessSudoInstalled = mgr.isPasswordlessSudoInstalled
        self.isLaunchAtLoginEnabled = LaunchAgentManager.shared.isEnabled
        self.logs = mgr.logs

        mgr.onStateChanged = { [weak self] in
            Task { @MainActor in
                self?.syncFromManager()
            }
        }

        mgr.appendLog("BudHold 已启动 — 检测到系统版本 \(osInfo.productName) \(osInfo.productVersion) (Build \(osInfo.buildVersion))")

        startPeriodicMonitoring()
    }

    public func startPeriodicMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            PowerKeepAliveManager.shared.performPeriodicTick()
            Task { @MainActor in
                self?.refreshAll()
            }
        }
    }

    public func refreshAll() {
        powerStatus = SystemInfoService.shared.fetchPowerAndLidStatus()
        rustDeskStatus = RustDeskMonitor.shared.fetchStatus()
        syncFromManager()
    }

    private func syncFromManager() {
        let mgr = PowerKeepAliveManager.shared
        isIdleKeepAwakeActive = mgr.isIdleKeepAwakeActive
        isClamshellKeepAwakeActive = powerStatus.isKernelSleepDisabled
        isBlackoutModeActive = DisplayBrightnessController.shared.isBlackoutModeActive
        isPasswordlessSudoInstalled = mgr.isPasswordlessSudoInstalled
        isLaunchAtLoginEnabled = LaunchAgentManager.shared.isEnabled
        logs = mgr.logs
        onStatusBarNeedsUpdate?()
    }

    // MARK: - 用户操作

    public func toggleFullRemoteMode() {
        if isFullRemoteModeActive {
            let (_, msg) = PowerKeepAliveManager.shared.disableAllKeepAwake()
            showToast(msg)
        } else {
            let (_, msg) = PowerKeepAliveManager.shared.enableFullRemoteReadyMode(duration: selectedDuration)
            showToast(msg)
        }
        refreshAll()
    }

    public func enableFullRemoteMode() {
        let (_, msg) = PowerKeepAliveManager.shared.enableFullRemoteReadyMode(duration: selectedDuration)
        showToast(msg)
        refreshAll()
    }

    public func disableAllMode() {
        let (_, msg) = PowerKeepAliveManager.shared.disableAllKeepAwake()
        showToast(msg)
        refreshAll()
    }

    public func toggleIdleKeepAwake() {
        if isIdleKeepAwakeActive {
            PowerKeepAliveManager.shared.disableIdleKeepAwake()
            showToast("已关闭空闲与关屏防休眠断言")
        } else {
            _ = PowerKeepAliveManager.shared.enableIdleKeepAwake(preventDisplaySleep: true, duration: selectedDuration)
            showToast("已开启空闲与关屏防休眠断言")
        }
        refreshAll()
    }

    public func toggleClamshellKeepAwake() {
        let target = !isClamshellKeepAwakeActive
        let (ok, err) = PowerKeepAliveManager.shared.setKernelClamshellSleepDisabled(target)
        if ok {
            if target && !isIdleKeepAwakeActive {
                _ = PowerKeepAliveManager.shared.enableIdleKeepAwake(preventDisplaySleep: true, duration: selectedDuration)
            }
            showToast(target ? "已开启合盖不休眠模式" : "已恢复系统默认合盖睡眠")
        } else {
            showToast("设置合盖模式失败：\(err)")
        }
        refreshAll()
    }

    public func toggleBlackoutMode() {
        if isBlackoutModeActive || powerStatus.displayBrightness < 0.02 {
            let ok = DisplayBrightnessController.shared.disableBlackoutMode()
            PowerKeepAliveManager.shared.appendLog(ok ? "已退出物理熄屏挂机模式，恢复屏幕背光" : "恢复屏幕背光失败")
            showToast("已恢复屏幕背光亮度")
        } else {
            if !isIdleKeepAwakeActive {
                _ = PowerKeepAliveManager.shared.enableIdleKeepAwake(preventDisplaySleep: true, duration: selectedDuration)
            }
            let ok = DisplayBrightnessController.shared.enableBlackoutMode()
            PowerKeepAliveManager.shared.appendLog(ok ? "已开启物理熄屏挂机模式（背光 0%，GPU 渲染保持活跃供 RustDesk 使用）" : "调节屏幕背光失败")
            showToast("已开启物理熄屏模式（按 Esc 键或再次点击即可恢复屏幕亮度）")
        }
        refreshAll()
    }

    public func togglePasswordlessSudo() {
        if isPasswordlessSudoInstalled {
            let (_, msg) = PowerKeepAliveManager.shared.removePasswordlessSudoers()
            showToast(msg)
        } else {
            let (_, msg) = PowerKeepAliveManager.shared.installPasswordlessSudoers()
            showToast(msg)
        }
        refreshAll()
    }

    public func toggleLaunchAtLogin() {
        let target = !isLaunchAtLoginEnabled
        if LaunchAgentManager.shared.setEnabled(target) {
            isLaunchAtLoginEnabled = target
            PowerKeepAliveManager.shared.appendLog(target ? "已开启开机自启动 (LaunchAgent)" : "已关闭开机自启动")
            showToast(target ? "已开启开机自动启动" : "已关闭开机自动启动")
        }
    }

    public func copyRustDeskID() {
        let id = rustDeskStatus.deviceID
        guard !id.isEmpty, id != "-" else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
        showToast("已复制 RustDesk ID: \(id)")
    }

    public func launchRustDesk() {
        if RustDeskMonitor.shared.launchRustDesk() {
            PowerKeepAliveManager.shared.appendLog("已启动/打开 RustDesk 客户端")
            showToast("已打开 RustDesk")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.refreshAll()
            }
        }
    }

    public func showToast(_ text: String) {
        statusToast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            if self?.statusToast == text {
                self?.statusToast = nil
            }
        }
    }
}
