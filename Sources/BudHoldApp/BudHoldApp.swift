import SwiftUI
import AppKit
import BudHoldCore

@main
struct BudHoldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let vm = AppViewModel.shared

        if CommandLine.arguments.contains("--rustdesk") {
            vm.rustDeskMonitoringEnabled = true
        }

        setupStatusBarItem()
        setupEscapeKeyRestoreBrightness()
        openDashboardWindow()

        vm.onStatusBarNeedsUpdate = { [weak self] in
            self?.updateStatusBarAppearance()
        }

        // 如果带有 --auto-enable 参数启动，则自动激活全天候防休眠模式
        if CommandLine.arguments.contains("--auto-enable") {
            vm.enableFullRemoteMode()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openDashboardWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if DisplayBrightnessController.shared.isBlackoutModeActive {
            _ = DisplayBrightnessController.shared.disableBlackoutMode()
        }
        if PowerKeepAliveManager.shared.restoreSleepOnAppQuit {
            _ = PowerKeepAliveManager.shared.disableAllKeepAwake()
        }
    }

    // MARK: - 顶部菜单栏图标与快捷菜单
    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBarAppearance()
    }

    private func updateStatusBarAppearance() {
        guard let button = statusItem?.button else { return }
        let vm = AppViewModel.shared

        let symbolName: String
        let statusPrefix: String
        if vm.isFullRemoteModeActive {
            symbolName = "bolt.shield.fill"
            statusPrefix = "合盖不休眠"
        } else if vm.isIdleKeepAwakeActive {
            symbolName = "cup.and.saucer.fill"
            statusPrefix = "防休眠"
        } else {
            symbolName = "moon.zzz"
            statusPrefix = "BudHold"
        }

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "BudHold")
        button.imagePosition = .imageLeading
        button.title = " \(statusPrefix)"

        let menu = NSMenu()

        let osHeader = NSMenuItem(
            title: "🖥️ 系统版本: \(vm.osInfo.productName) \(vm.osInfo.productVersion) (Build \(vm.osInfo.buildVersion))",
            action: nil,
            keyEquivalent: ""
        )
        osHeader.isEnabled = false
        menu.addItem(osHeader)

        let lidHeader = NSMenuItem(
            title: "💻 盒盖状态: \(vm.powerStatus.isClamshellClosed ? "已合盖" : "开盖") | 电源: \(vm.powerStatus.isACPower ? "外接电源" : "电池") \(vm.powerStatus.batteryPercentage)%",
            action: nil,
            keyEquivalent: ""
        )
        lidHeader.isEnabled = false
        menu.addItem(lidHeader)

        if vm.rustDeskMonitoringEnabled {
            let rdHeader = NSMenuItem(
                title: "🔗 RustDesk ID: \(vm.rustDeskStatus.deviceID) (\(vm.rustDeskStatus.isServerRunning ? "在线" : "未运行"))",
                action: #selector(copyRustDeskIDFromMenu),
                keyEquivalent: ""
            )
            rdHeader.target = self
            menu.addItem(rdHeader)
        }

        menu.addItem(.separator())

        let fullToggleItem = NSMenuItem(
            title: vm.isFullRemoteModeActive ? "✅ 已开启：合盖+关屏不休眠（点击关闭）" : "🚀 一键开启：合盖+关屏不休眠",
            action: #selector(toggleFullModeFromMenu),
            keyEquivalent: "k"
        )
        fullToggleItem.target = self
        menu.addItem(fullToggleItem)

        let clamshellItem = NSMenuItem(
            title: vm.isClamshellKeepAwakeActive ? "🔒 合盖不休眠锁 (SleepDisabled): 已启用" : "🔓 合盖不休眠锁 (SleepDisabled): 未启用",
            action: #selector(toggleClamshellFromMenu),
            keyEquivalent: ""
        )
        clamshellItem.target = self
        menu.addItem(clamshellItem)

        let idleItem = NSMenuItem(
            title: vm.isIdleKeepAwakeActive ? "🟢 防空闲与关屏渲染断言: 已激活" : "⚪ 防空闲与关屏渲染断言: 未激活",
            action: #selector(toggleIdleFromMenu),
            keyEquivalent: ""
        )
        idleItem.target = self
        menu.addItem(idleItem)

        let blackoutItem = NSMenuItem(
            title: vm.isBlackoutModeActive ? "☀️ 恢复屏幕背光亮度" : "🌑 物理熄屏挂机（背光 0%，保持远控画面）",
            action: #selector(toggleBlackoutFromMenu),
            keyEquivalent: "b"
        )
        blackoutItem.target = self
        menu.addItem(blackoutItem)

        menu.addItem(.separator())

        let rdMonitorToggleItem = NSMenuItem(
            title: vm.rustDeskMonitoringEnabled ? "📡 RustDesk 监控（按需项）: 已启用" : "📡 RustDesk 监控（按需项）: 未启用",
            action: #selector(toggleRustDeskMonitorFromMenu),
            keyEquivalent: ""
        )
        rdMonitorToggleItem.target = self
        menu.addItem(rdMonitorToggleItem)

        if vm.rustDeskMonitoringEnabled {
            let openRustDeskItem = NSMenuItem(
                title: "打开 RustDesk 客户端",
                action: #selector(openRustDeskFromMenu),
                keyEquivalent: ""
            )
            openRustDeskItem.target = self
            menu.addItem(openRustDeskItem)
        }

        menu.addItem(.separator())

        let openDashboardItem = NSMenuItem(
            title: "打开 BudHold 主控制台...",
            action: #selector(openDashboardWindow),
            keyEquivalent: "o"
        )
        openDashboardItem.target = self
        menu.addItem(openDashboardItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 BudHold",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - 键盘快捷键监听（当处于物理熄屏模式时，按 Esc 键可立即恢复屏幕背光）
    private func setupEscapeKeyRestoreBrightness() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 && DisplayBrightnessController.shared.isBlackoutModeActive {
                Task { @MainActor in
                    AppViewModel.shared.toggleBlackoutMode()
                }
            }
            return event
        }
    }

    // MARK: - 菜单栏动作
    @objc private func toggleFullModeFromMenu() {
        AppViewModel.shared.toggleFullRemoteMode()
    }

    @objc private func toggleClamshellFromMenu() {
        AppViewModel.shared.toggleClamshellKeepAwake()
    }

    @objc private func toggleIdleFromMenu() {
        AppViewModel.shared.toggleIdleKeepAwake()
    }

    @objc private func toggleBlackoutFromMenu() {
        AppViewModel.shared.toggleBlackoutMode()
    }

    @objc private func toggleRustDeskMonitorFromMenu() {
        AppViewModel.shared.rustDeskMonitoringEnabled.toggle()
    }

    @objc private func copyRustDeskIDFromMenu() {
        AppViewModel.shared.copyRustDeskID()
    }

    @objc private func openRustDeskFromMenu() {
        AppViewModel.shared.launchRustDesk()
    }

    @objc private func openDashboardWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = DashboardView(vm: AppViewModel.shared)
        let hostingController = NSHostingController(rootView: contentView)

        let os = SystemInfoService.shared.osInfo
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BudHold — macOS 防休眠与合盖保活工具 (\(os.productName) \(os.productVersion))"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.mainWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
