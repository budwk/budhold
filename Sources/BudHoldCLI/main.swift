import Foundation
import BudHoldCore

func printBanner() {
    let os = SystemInfoService.shared.osInfo
    print("================================================================")
    print(" 🛡️  BudHold — macOS 防休眠与合盖远程保活工具")
    print(" 🖥️  当前系统版本: \(os.productName) \(os.productVersion) (Build \(os.buildVersion))")
    print(" ⚙️  硬件与架构  : \(os.cpuBrand) (\(os.hardwareModel)) · \(os.architecture)")
    print("================================================================")
}

func printStatus(forceIncludeRustDesk: Bool = false) {
    printBanner()
    let mgr = PowerKeepAliveManager.shared
    let power = SystemInfoService.shared.fetchPowerAndLidStatus()
    let sudoersInstalled = mgr.isPasswordlessSudoInstalled
    let showRustDesk = forceIncludeRustDesk || mgr.rustDeskMonitoringEnabled

    print("\n[电源与休眠状态]")
    print("  • 合盖不休眠锁 (SleepDisabled) : \(power.isKernelSleepDisabled ? "✅ 已开启 (合盖不进入睡眠)" : "⚪ 未开启 (合盖将按系统默认睡眠)")")
    print("  • 当前笔记本盒盖状态           : \(power.isClamshellClosed ? "📕 已合盖 (Clamshell Closed)" : "📖 开盖状态 (Lid Open)")")
    print("  • 显示器帧缓冲状态             : \(power.isDisplayAsleep ? "💤 已休眠 (Display Asleep)" : "🟢 活跃渲染中 (Framebuffer Awake)")")
    print("  • 当前屏幕物理背光亮度         : \(Int(round(power.displayBrightness * 100)))%\(power.displayBrightness == 0 ? " (物理熄屏防窥挂机中)" : "")")
    print("  • 供电状态与电量               : \(power.isACPower ? "⚡ 外接电源 (AC Power)" : "🔋 电池供电") · \(power.batteryPercentage)%\(power.isCharging ? " (充电中)" : "")")
    print("  • 本机网络 IP 地址             : \(power.localIPs.isEmpty ? "无网络连接" : power.localIPs.joined(separator: " | "))")
    print("  • pmset 免密切换权限           : \(sudoersInstalled ? "✅ 已配置 (/etc/sudoers.d/budhold)" : "⚪ 未配置 (切换时弹窗授权，可执行 budhold install-sudoers)")")

    if showRustDesk {
        let rd = RustDeskMonitor.shared.fetchStatus(enabled: true)
        print("\n[RustDesk 远程监控状态 (按需启用)]")
        print("  • 监控配置状态                 : \(mgr.rustDeskMonitoringEnabled ? "✅ 已持久开启" : "🔍 临时查询 (--rustdesk)")")
        print("  • 安装状态与版本               : \(rd.isInstalled ? "✅ 已安装 (v\(rd.version))" : "❌ 未检测到 /Applications/RustDesk.app")")
        print("  • 本机 RustDesk ID             : \(rd.deviceID)")
        print("  • RustDesk --server 进程       : \(rd.isServerRunning ? "🟢 运行中" : "🔴 未运行")")
        print("  • RustDesk service 守护进程    : \(rd.isServiceRunning ? "🟢 运行中" : "⚪ 未运行")")
        print("  • 当前活跃远控连接数           : \(rd.activeConnectionCount)\(rd.activePeerEndpoints.isEmpty ? "" : " (\(rd.activePeerEndpoints.joined(separator: ", ")))")")
    } else {
        print("\n[RustDesk 远程监控状态 (可选按需项)]")
        print("  • 当前状态                     : ⚪ 未启用 (可通过 `budhold rustdesk on` 或 `budhold status --rustdesk` 按需启用)")
    }

    print("\n[综合评估]")
    if power.isKernelSleepDisabled {
        print("  🚀 当前处于【合盖+关屏不休眠】状态：即使 MacBook 合盖或关闭显示器，系统与图形渲染均保持活跃！")
    } else {
        print("  💡 提示：执行 `budhold on` 或在 BudHold.app 中点击一键开启，即可激活合盖+关屏不休眠模式。")
    }
    print("================================================================\n")
}

func printHelp() {
    printBanner()
    print("""

    用法: budhold <命令> [选项]

    可用命令:
      status [--rustdesk]       查看当前 macOS 版本、合盖防休眠状态（可选附带 --rustdesk 查看 RustDesk 状态）
      on [--daemon] [--rustdesk]开启「合盖+关屏不休眠」模式（--daemon 持续驻留守护，--rustdesk 同时启用 RustDesk 守护）
      off                       关闭所有防休眠并恢复 macOS 系统默认睡眠设置
      rustdesk <on|off|status>  按需启用/禁用 RustDesk 监控与进程守护，或单独查看其状态
      blackout <on|off>         开启/关闭「物理熄屏挂机」(仅关闭屏幕背光至 0%，保持显卡渲染供远控)
      wake                      立即唤醒显示器渲染管线（若已启用 RustDesk 监控则同时确保其运行）
      install-sudoers           配置 pmset 免密权限 (/etc/sudoers.d/budhold)，后续切换合盖不休眠无需输入密码
      remove-sudoers            移除 pmset 免密权限配置
      version                   输出当前 macOS 版本号与工具版本信息
      help                      显示此帮助信息
    """)
}

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first?.lowercased() ?? "status"
let hasRustDeskFlag = args.contains("--rustdesk") || args.contains("-r")

switch command {
case "status":
    printStatus(forceIncludeRustDesk: hasRustDeskFlag)

case "version", "-v", "--version":
    let os = SystemInfoService.shared.osInfo
    print("BudHold v1.0.0")
    print("当前操作系统: \(os.productName) \(os.productVersion) (Build \(os.buildVersion))")
    print("硬件架构: \(os.cpuBrand) (\(os.hardwareModel)) - \(os.architecture)")

case "on", "enable", "start":
    printBanner()
    if hasRustDeskFlag {
        PowerKeepAliveManager.shared.rustDeskMonitoringEnabled = true
    }
    let (ok, msg) = PowerKeepAliveManager.shared.enableFullRemoteReadyMode()
    print(ok ? "✅ \(msg)" : "⚠️ \(msg)")
    if args.contains("--daemon") || args.contains("-d") {
        print("🔄 正在持续驻留守护 (RustDesk 监控: \(PowerKeepAliveManager.shared.rustDeskMonitoringEnabled ? "已启用" : "未启用"))，按 Ctrl+C 退出并自动恢复系统休眠...")
        signal(SIGINT) { _ in
            print("\n正在退出守护并恢复默认休眠设置...")
            _ = PowerKeepAliveManager.shared.disableAllKeepAwake()
            exit(0)
        }
        signal(SIGTERM) { _ in
            _ = PowerKeepAliveManager.shared.disableAllKeepAwake()
            exit(0)
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            PowerKeepAliveManager.shared.performPeriodicTick()
        }
        RunLoop.current.add(timer, forMode: .default)
        RunLoop.current.run()
    } else {
        _ = SystemInfoService.runCommand("/bin/sh", args: ["-c", "nohup /usr/bin/caffeinate -d -i -m -s -u >/dev/null 2>&1 &"])
        print("💡 已在后台启动 caffeinate 保活进程，并激活内核合盖不休眠 (SleepDisabled = Yes)。")
    }

case "off", "disable", "stop":
    printBanner()
    let (ok, msg) = PowerKeepAliveManager.shared.disableAllKeepAwake()
    _ = SystemInfoService.runCommand("/usr/bin/killall", args: ["caffeinate"])
    print(ok ? "✅ \(msg)" : "⚠️ \(msg)")

case "rustdesk":
    let sub = args.dropFirst().first?.lowercased() ?? "status"
    switch sub {
    case "on", "enable", "1":
        PowerKeepAliveManager.shared.rustDeskMonitoringEnabled = true
        print("✅ 已启用 RustDesk 监控与自动守护（按需模式）")
        printStatus(forceIncludeRustDesk: true)
    case "off", "disable", "0":
        PowerKeepAliveManager.shared.rustDeskMonitoringEnabled = false
        print("⚪ 已关闭 RustDesk 监控与守护")
    default:
        printStatus(forceIncludeRustDesk: true)
    }

case "blackout", "dim":
    let sub = args.dropFirst().first?.lowercased() ?? "on"
    if sub == "on" || sub == "1" {
        let ok = DisplayBrightnessController.shared.enableBlackoutMode()
        print(ok ? "🌑 已开启物理熄屏挂机模式（屏幕背光 0%，GPU 渲染保持活跃，远程桌面画面正常）" : "❌ 调节背光失败")
    } else {
        let ok = DisplayBrightnessController.shared.disableBlackoutMode()
        print(ok ? "☀️ 已恢复屏幕背光亮度" : "❌ 恢复背光失败")
    }

case "wake":
    let woke = DisplayBrightnessController.shared.wakeDisplayFramebuffer()
    if PowerKeepAliveManager.shared.rustDeskMonitoringEnabled || hasRustDeskFlag {
        let rd = RustDeskMonitor.shared.fetchStatus(enabled: true)
        if rd.isInstalled && !rd.isServerRunning {
            RustDeskMonitor.shared.launchRustDesk()
        }
    }
    print(woke ? "✅ 已唤醒显示器渲染缓冲区" : "⚠️ 唤醒显示器返回异常")

case "install-sudoers":
    printBanner()
    print("🔐 正在申请管理员权限以配置 /etc/sudoers.d/budhold 免密规则...")
    let (ok, msg) = PowerKeepAliveManager.shared.installPasswordlessSudoers()
    print(ok ? "✅ \(msg)" : "❌ \(msg)")

case "remove-sudoers":
    let (ok, msg) = PowerKeepAliveManager.shared.removePasswordlessSudoers()
    print(ok ? "✅ \(msg)" : "❌ \(msg)")

case "help", "-h", "--help":
    printHelp()

default:
    print("未知命令: \(command)\n")
    printHelp()
    exit(1)
}
