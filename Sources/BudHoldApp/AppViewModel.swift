import Foundation
import AppKit
import Combine
import BudHoldCore

@MainActor
public final class AppViewModel: ObservableObject {
    public static let shared = AppViewModel()

    private static let kHasShownBlackoutGuideKey = "budhold.hasShownBlackoutGuide"

    @Published public var osInfo: MacOSVersionInfo
    @Published public var powerStatus: PowerAndLidStatus

    @Published public var isIdleKeepAwakeActive: Bool = false
    @Published public var isClamshellKeepAwakeActive: Bool = false
    @Published public var isBlackoutModeActive: Bool = false
    @Published public var isPasswordlessSudoInstalled: Bool = false
    @Published public var isLaunchAtLoginEnabled: Bool = false

    @Published public var selectedLanguage: AppLanguage = L10n.shared.language {
        didSet {
            guard selectedLanguage != oldValue else { return }
            L10n.shared.language = selectedLanguage
            onLanguageChanged?()
            onStatusBarNeedsUpdate?()
        }
    }

    @Published public var selectedDuration: KeepAwakeDuration = .infinite {
        didSet {
            guard selectedDuration != oldValue else { return }
            PowerKeepAliveManager.shared.updateDuration(selectedDuration)
            onStatusBarNeedsUpdate?()
        }
    }
    @Published public var keepDisplayRendererAwake: Bool = true {
        didSet { PowerKeepAliveManager.shared.keepDisplayRendererAwake = keepDisplayRendererAwake }
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
    public var onLanguageChanged: (() -> Void)?

    public var isFullRemoteModeActive: Bool {
        isIdleKeepAwakeActive && isClamshellKeepAwakeActive
    }

    public func tr(_ zh: String, _ en: String) -> String {
        selectedLanguage.resolvedIsChinese ? zh : en
    }

    private init() {
        let mgr = PowerKeepAliveManager.shared

        self.osInfo = SystemInfoService.shared.osInfo
        self.powerStatus = SystemInfoService.shared.fetchPowerAndLidStatus()

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

        mgr.appendLog(L10n.tr(
            "BudHold 已启动 — 检测到系统版本 \(osInfo.productName) \(osInfo.productVersion) (Build \(osInfo.buildVersion))",
            "BudHold started — Detected \(osInfo.productName) \(osInfo.productVersion) (Build \(osInfo.buildVersion))"
        ))

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

    public func setLanguage(_ language: AppLanguage) {
        selectedLanguage = language
        showToast(tr("语言已切换为：\(language.displayName(in: language))", "Language switched to: \(language.displayName(in: language))"))
    }

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
            showToast(tr("已关闭空闲与关屏防休眠断言", "Disabled idle & display keep-awake assertions"))
        } else {
            _ = PowerKeepAliveManager.shared.enableIdleKeepAwake(preventDisplaySleep: true, duration: selectedDuration)
            showToast(tr("已开启空闲与关屏防休眠断言", "Enabled idle & display keep-awake assertions"))
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
            showToast(target
                ? tr("已开启合盖不休眠模式", "Clamshell Keep-Awake enabled")
                : tr("已恢复系统默认合盖睡眠", "Restored default lid sleep")
            )
        } else {
            showToast(tr("设置合盖模式失败：\(err)", "Failed to set clamshell mode: \(err)"))
        }
        refreshAll()
    }

    public func toggleBlackoutMode() {
        if isBlackoutModeActive || powerStatus.displayBrightness < 0.02 {
            let ok = DisplayBrightnessController.shared.disableBlackoutMode()
            PowerKeepAliveManager.shared.appendLog(ok
                ? tr("已退出物理熄屏挂机模式，恢复屏幕背光", "Exited Display Blackout mode, brightness restored")
                : tr("恢复屏幕背光失败", "Failed to restore display brightness")
            )
            showToast(tr("已恢复屏幕背光亮度", "Display brightness restored"))
            refreshAll()
        } else {
            if !UserDefaults.standard.bool(forKey: Self.kHasShownBlackoutGuideKey) {
                guard confirmFirstTimeBlackoutGuide() else {
                    return
                }
            }
            if !isIdleKeepAwakeActive {
                _ = PowerKeepAliveManager.shared.enableIdleKeepAwake(preventDisplaySleep: true, duration: selectedDuration)
            }
            let ok = DisplayBrightnessController.shared.enableBlackoutMode()
            PowerKeepAliveManager.shared.appendLog(ok
                ? tr("已开启物理熄屏挂机模式（背光 0%，GPU 渲染保持活跃）", "Display Blackout enabled (Backlight 0%, GPU framebuffer active)")
                : tr("调节屏幕背光失败", "Failed to set display brightness")
            )
            showToast(tr("已开启物理熄屏模式（按 Esc 键或再次点击即可恢复屏幕亮度）", "Blackout active (Press Esc or click again to restore brightness)"))
            refreshAll()
        }
    }

    private func confirmFirstTimeBlackoutGuide() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = tr(
            "即将开启「物理熄屏挂机 (背光 0%)」",
            "About to Enable Display Blackout (Backlight 0%)"
        )
        alert.informativeText = tr(
            """
            开启后屏幕背光将完全关闭（呈现黑屏状态），系统与图形渲染仍在正常保活运行，并非软件卡死或故障。

            💡 随时恢复屏幕亮度的操作方式：
            1. 按下键盘左上角的【Esc】键
            2. 按下键盘上的【屏幕亮度增加键 (F2)】
            3. 使用快捷键【⌘B】或再次点击原按钮
            """,
            """
            The screen backlight will be turned down to 0% (pure black screen) while the system and GPU display renderer remain fully active. This is not a crash or freeze.

            💡 How to restore screen brightness anytime:
            1. Press the [Esc] key on your keyboard
            2. Press the [Brightness Up (F2)] key
            3. Press [⌘B] or click the button again
            """
        )
        alert.addButton(withTitle: tr("开启物理熄屏", "Enable Blackout"))
        alert.addButton(withTitle: tr("取消", "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = tr("我已了解恢复方式，下次不再提醒", "I understand how to restore brightness, don't show again")
        alert.suppressionButton?.state = .on

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(true, forKey: Self.kHasShownBlackoutGuideKey)
            }
            return true
        }
        return false
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

    public func setDuration(_ duration: KeepAwakeDuration) {
        selectedDuration = duration
        showToast(tr("保活时长已设为：\(duration.title)", "Duration set to: \(duration.title)"))
    }

    public func toggleLaunchAtLogin() {
        let target = !isLaunchAtLoginEnabled
        if LaunchAgentManager.shared.setEnabled(target) {
            isLaunchAtLoginEnabled = target
            PowerKeepAliveManager.shared.appendLog(target
                ? tr("已开启开机自启动 (LaunchAgent)", "Enabled Launch at Login (LaunchAgent)")
                : tr("已关闭开机自启动", "Disabled Launch at Login")
            )
            showToast(target
                ? tr("已开启开机自动启动", "Launch at Login enabled")
                : tr("已关闭开机自动启动", "Launch at Login disabled")
            )
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
