import SwiftUI
import AppKit
import BudHoldCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var localKeyMonitor: Any?

    /// 标记是否由顶部菜单栏图标点击触发的「真退出」
    private var isTrueQuitRequested: Bool = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let vm = AppViewModel.shared

        // 监听系统关机/注销事件，避免阻止 macOS 正常重启或关机
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isTrueQuitRequested = true
            }
        }

        setupApplicationMainMenu()
        setupStatusBarItem()
        setupEscapeKeyRestoreBrightness()
        openDashboardWindow()

        vm.onStatusBarNeedsUpdate = { [weak self] in
            self?.setupApplicationMainMenu()
            self?.updateStatusBarAppearance()
        }
        vm.onLanguageChanged = { [weak self] in
            self?.adjustWindowWidthForCurrentLanguage(animated: true)
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

    /// 拦截底部 Dock 菜单「退出」或 ⌘Q：仅隐藏窗口与 Dock 图标并转入后台状态栏常驻，只有点击顶部状态栏「退出 BudHold」才真正退出
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTrueQuitRequested {
            return .terminateNow
        }

        mainWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        PowerKeepAliveManager.shared.appendLog(L10n.tr(
            "已隐藏主窗口与底部图标，BudHold 仍在顶部菜单栏后台运行",
            "Window and Dock icon hidden. BudHold is running in the menu bar"
        ))
        return .terminateCancel
    }

    /// 点击窗口左上角红色关闭按钮时：隐藏窗口并移除底部 Dock 图标，仅保留顶部状态栏图标
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if DisplayBrightnessController.shared.isBlackoutModeActive {
            _ = DisplayBrightnessController.shared.disableBlackoutMode()
        }
        if PowerKeepAliveManager.shared.restoreSleepOnAppQuit {
            _ = PowerKeepAliveManager.shared.disableAllKeepAwake()
        }
    }

    // MARK: - 构建纯净的应用主菜单
    private func setupApplicationMainMenu() {
        let mainMenu = NSMenu()

        // 1. 应用菜单
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let showWindowItem = NSMenuItem(
            title: L10n.tr("显示 BudHold 主控制台", "Show BudHold Dashboard"),
            action: #selector(openDashboardWindow),
            keyEquivalent: "o"
        )
        showWindowItem.target = self
        appMenu.addItem(showWindowItem)

        appMenu.addItem(.separator())

        let hideToBarItem = NSMenuItem(
            title: L10n.tr("关闭窗口并隐藏底部图标", "Close Window & Hide Dock Icon"),
            action: #selector(hideWindowAndDockIcon),
            keyEquivalent: "w"
        )
        hideToBarItem.target = self
        appMenu.addItem(hideToBarItem)

        // ⌘Q 走 NSApp.terminate，会被 applicationShouldTerminate 拦截为转入后台
        let dockQuitItem = NSMenuItem(
            title: L10n.tr("转入后台运行", "Hide to Menu Bar"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(dockQuitItem)

        // 2. 编辑菜单（确保复制粘贴快捷键正常）
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L10n.tr("编辑", "Edit"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: L10n.tr("拷贝", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.tr("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.tr("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
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
            statusPrefix = vm.tr("合盖不休眠", "Clamshell Awake")
        } else if vm.isIdleKeepAwakeActive || vm.isClamshellKeepAwakeActive {
            symbolName = "cup.and.saucer.fill"
            statusPrefix = vm.tr("防休眠", "Awake")
        } else {
            symbolName = "moon.zzz"
            statusPrefix = ""
        }

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "BudHold")
        if statusPrefix.isEmpty {
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.imagePosition = .imageLeading
            button.title = " \(statusPrefix)"
        }

        let menu = NSMenu()

        let lidStateText = vm.powerStatus.isClamshellClosed ? vm.tr("已合盖", "Closed") : vm.tr("开盖", "Open")
        let powerSourceText = vm.powerStatus.isACPower ? vm.tr("外接电源", "AC") : vm.tr("电池", "Battery")
        let lidHeader = NSMenuItem(
            title: vm.tr(
                "💻 盒盖: \(lidStateText)  |  电源: \(powerSourceText) \(vm.powerStatus.batteryPercentage)%",
                "💻 Lid: \(lidStateText)  |  Power: \(powerSourceText) \(vm.powerStatus.batteryPercentage)%"
            ),
            action: nil,
            keyEquivalent: ""
        )
        lidHeader.isEnabled = false
        menu.addItem(lidHeader)

        menu.addItem(.separator())

        let fullToggleItem = NSMenuItem(
            title: vm.isFullRemoteModeActive
                ? vm.tr("✅ 已开启：合盖+关屏不休眠（点击关闭）", "✅ Active: Clamshell & Display Awake (Click to Stop)")
                : vm.tr("🚀 一键开启：合盖+关屏不休眠", "🚀 Enable Clamshell & Display Keep-Awake"),
            action: #selector(toggleFullModeFromMenu),
            keyEquivalent: "k"
        )
        fullToggleItem.target = self
        menu.addItem(fullToggleItem)

        let clamshellItem = NSMenuItem(
            title: vm.isClamshellKeepAwakeActive
                ? vm.tr("🔒 合盖不休眠锁: 已启用", "🔒 Clamshell Sleep Lock: Enabled")
                : vm.tr("🔓 合盖不休眠锁: 未启用", "🔓 Clamshell Sleep Lock: Disabled"),
            action: #selector(toggleClamshellFromMenu),
            keyEquivalent: ""
        )
        clamshellItem.target = self
        menu.addItem(clamshellItem)

        let idleItem = NSMenuItem(
            title: vm.isIdleKeepAwakeActive
                ? vm.tr("🟢 防空闲与关屏渲染: 已激活", "🟢 Idle & Display Awake: Active")
                : vm.tr("⚪ 防空闲与关屏渲染: 未激活", "⚪ Idle & Display Awake: Inactive"),
            action: #selector(toggleIdleFromMenu),
            keyEquivalent: ""
        )
        idleItem.target = self
        menu.addItem(idleItem)

        let blackoutItem = NSMenuItem(
            title: vm.isBlackoutModeActive
                ? vm.tr("☀️ 恢复屏幕背光亮度", "☀️ Restore Screen Brightness")
                : vm.tr("🌑 物理熄屏挂机（背光 0%）", "🌑 Display Blackout (Backlight 0%)"),
            action: #selector(toggleBlackoutFromMenu),
            keyEquivalent: "b"
        )
        blackoutItem.target = self
        menu.addItem(blackoutItem)

        // 快速设置保活时长子菜单
        let durationParentItem = NSMenuItem(
            title: vm.tr("⏱️ 保活时长: \(vm.selectedDuration.title)", "⏱️ Duration: \(vm.selectedDuration.title)"),
            action: nil,
            keyEquivalent: ""
        )
        let durationSubmenu = NSMenu(title: vm.tr("保活时长", "Duration"))
        for duration in KeepAwakeDuration.allCases {
            let item = NSMenuItem(
                title: duration.title,
                action: #selector(selectDurationFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = duration.rawValue
            item.state = (vm.selectedDuration == duration) ? .on : .off
            durationSubmenu.addItem(item)
        }
        durationParentItem.submenu = durationSubmenu
        menu.addItem(durationParentItem)

        menu.addItem(.separator())

        let openDashboardItem = NSMenuItem(
            title: vm.tr("打开主控制台...", "Open Dashboard..."),
            action: #selector(openDashboardWindow),
            keyEquivalent: ""
        )
        openDashboardItem.target = self
        menu.addItem(openDashboardItem)

        menu.addItem(.separator())

        // 仅顶部菜单栏的此按钮才会触发真退出（不绑定 ⌘Q 防止误按退出）
        let quitItem = NSMenuItem(
            title: vm.tr("退出 BudHold", "Quit BudHold"),
            action: #selector(quitAppFromStatusBar),
            keyEquivalent: ""
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

    @objc private func selectDurationFromMenu(_ sender: NSMenuItem) {
        if let duration = KeepAwakeDuration(rawValue: sender.tag) {
            AppViewModel.shared.setDuration(duration)
        }
    }

    @objc private func hideWindowAndDockIcon() {
        mainWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func openDashboardWindow() {
        // 打开主控制台时恢复普通应用策略，显示在窗口与底部程序坞中
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        if let window = mainWindow {
            adjustWindowWidthForCurrentLanguage(animated: false)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = DashboardView(vm: AppViewModel.shared)
        let hostingController = NSHostingController(rootView: contentView)

        let initialWidth: CGFloat = L10n.shared.isChinese ? 760 : 880
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BudHold"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.mainWindow = window
    }

    private func adjustWindowWidthForCurrentLanguage(animated: Bool) {
        guard let window = mainWindow else { return }
        let targetWidth: CGFloat = L10n.shared.isChinese ? 760 : 880
        var frame = window.frame
        let delta = targetWidth - frame.size.width
        guard abs(delta) > 1 else { return }
        frame.origin.x -= delta / 2.0
        frame.size.width = targetWidth
        window.setFrame(frame, display: true, animate: animated)
    }

    @objc private func quitAppFromStatusBar() {
        isTrueQuitRequested = true
        NSApp.terminate(nil)
    }
}
