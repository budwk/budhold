import SwiftUI
import BudHoldCore

public struct DashboardView: View {
    @ObservedObject var vm: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    public init(vm: AppViewModel) {
        self.vm = vm
    }

    // MARK: - 自适应主题配色
    private var isDark: Bool {
        colorScheme == .dark
    }

    private var windowBackground: Color {
        isDark
            ? Color(nsColor: .windowBackgroundColor)
            : Color(red: 0.955, green: 0.96, blue: 0.97)
    }

    private var cardBackground: Color {
        isDark
            ? Color.white.opacity(0.055)
            : Color.white
    }

    private var cardBorder: Color {
        isDark
            ? Color.white.opacity(0.09)
            : Color.black.opacity(0.07)
    }

    private var subtleFill: Color {
        isDark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.045)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerSection
                heroControlCard
                telemetryGrid
                settingsCard
                logSection
            }
            .padding(20)
        }
        .frame(
            minWidth: vm.selectedLanguage.resolvedIsChinese ? 720 : 840,
            idealWidth: vm.selectedLanguage.resolvedIsChinese ? 760 : 880,
            minHeight: 580,
            idealHeight: 640
        )
        .background(windowBackground)
        .overlay(alignment: .bottom) {
            if let toast = vm.statusToast {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                    Text(toast)
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(isDark ? 0.88 : 0.8))
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                )
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.statusToast)
    }

    // MARK: - 1. 顶部概览栏
    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: vm.isFullRemoteModeActive
                                ? [Color.green.opacity(0.25), Color.mint.opacity(0.15)]
                                : [Color.accentColor.opacity(0.22), Color.blue.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: vm.isFullRemoteModeActive ? "bolt.shield.fill" : "moon.zzz.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(vm.isFullRemoteModeActive ? .green : .accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("BudHold")
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(vm.tr("防休眠与合盖保活", "Clamshell & Sleep Guard"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("\(vm.osInfo.productName) \(vm.osInfo.productVersion)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(subtleFill))
                        .foregroundColor(.secondary)
                }

                Text("\(vm.osInfo.cpuBrand) (\(vm.osInfo.hardwareModel)) · \(vm.osInfo.architecture)")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            languageMenu

            statusPill
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button(action: {
                    vm.setLanguage(lang)
                }) {
                    HStack {
                        Text(lang.displayName(in: vm.selectedLanguage))
                        if vm.selectedLanguage == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 11.5))
                Text(vm.selectedLanguage.displayName(in: vm.selectedLanguage))
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(subtleFill)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var statusPill: some View {
        let isFull = vm.isFullRemoteModeActive
        let isPartial = vm.isIdleKeepAwakeActive || vm.isClamshellKeepAwakeActive
        let tint: Color = isFull ? .green : (isPartial ? .orange : .secondary)
        let label = isFull
            ? vm.tr("合盖不休眠 · 运行中", "Clamshell Awake · Active")
            : (isPartial ? vm.tr("防休眠 · 部分激活", "Keep-Awake · Partial") : vm.tr("系统默认休眠", "Default Sleep"))

        return HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isFull || isPartial ? tint : .secondary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(tint.opacity(isDark ? 0.16 : 0.12))
        )
    }

    // MARK: - 2. 核心总控卡片
    private var heroControlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(vm.isFullRemoteModeActive
                        ? vm.tr("全天候合盖与关屏保活已开启", "Full Clamshell & Display Keep-Awake Active")
                        : vm.tr("一键开启「合盖 + 关屏」不休眠模式", "One-Click Clamshell & Display Keep-Awake")
                    )
                    .font(.system(size: 15.5, weight: .bold))
                    Text(vm.tr(
                        "同时锁定内核休眠与显示渲染管线，确保 MacBook 合上盖子或关闭屏幕后，系统与桌面渲染持续运行。",
                        "Locks kernel sleep and keeps the GPU display pipeline active so your Mac stays running even with the lid closed or screen off."
                    ))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button(action: {
                    vm.toggleFullRemoteMode()
                }) {
                    HStack(spacing: 7) {
                        Image(systemName: vm.isFullRemoteModeActive ? "stop.fill" : "power")
                            .font(.system(size: 13, weight: .bold))
                        Text(vm.isFullRemoteModeActive ? vm.tr("关闭保活", "Disable") : vm.tr("一键开启", "Enable Now"))
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(vm.isFullRemoteModeActive ? Color.red.opacity(0.9) : Color.green)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()
                .opacity(0.6)

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(vm.tr("保活时长", "Duration"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Picker("", selection: $vm.selectedDuration) {
                        ForEach(KeepAwakeDuration.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 165)
                    .controlSize(.small)
                }

                Spacer()

                Button(action: {
                    vm.toggleBlackoutMode()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: vm.isBlackoutModeActive ? "sun.max.fill" : "moon.stars.fill")
                            .foregroundColor(vm.isBlackoutModeActive ? .orange : .secondary)
                        Text(vm.isBlackoutModeActive
                            ? vm.tr("恢复屏幕亮度 (Esc)", "Restore Brightness (Esc)")
                            : vm.tr("物理熄屏挂机 (背光 0%)", "Display Blackout (0%)")
                        )
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(vm.isBlackoutModeActive ? Color.orange.opacity(0.18) : subtleFill)
                    )
                }
                .buttonStyle(.plain)

                Button(action: {
                    vm.refreshAll()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text(vm.tr("刷新", "Refresh"))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(subtleFill)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    vm.isFullRemoteModeActive
                        ? (isDark ? Color.green.opacity(0.08) : Color.green.opacity(0.05))
                        : cardBackground
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    vm.isFullRemoteModeActive ? Color.green.opacity(0.35) : cardBorder,
                    lineWidth: 1
                )
        )
    }

    // MARK: - 3. 2x2 状态与控制矩阵
    private var telemetryGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                telemetryCard(
                    icon: "lock.laptopcomputer",
                    title: vm.tr("合盖休眠锁 (pmset)", "Clamshell Lock (pmset)"),
                    value: vm.isClamshellKeepAwakeActive
                        ? vm.tr("已锁定 · 合盖不休眠", "Locked · Awake on Lid Close")
                        : vm.tr("未锁定 · 合盖默认睡眠", "Unlocked · Default Lid Sleep"),
                    subtitle: vm.tr("内核级阻止合盖触发系统休眠", "Prevents kernel sleep when lid is closed"),
                    isActive: vm.isClamshellKeepAwakeActive,
                    actionTitle: vm.isClamshellKeepAwakeActive ? vm.tr("关闭", "Disable") : vm.tr("开启", "Enable"),
                    action: { vm.toggleClamshellKeepAwake() }
                )

                telemetryCard(
                    icon: "display",
                    title: vm.tr("空闲与显示渲染保活", "Idle & Display Assertion"),
                    value: vm.isIdleKeepAwakeActive
                        ? vm.tr("已激活 · 渲染常亮", "Active · Renderer Awake")
                        : vm.tr("未激活 · 默认空闲睡眠", "Inactive · Default Idle Sleep"),
                    subtitle: vm.tr("IOKit 断言与 Caffeinate 守护", "IOKit assertions & Caffeinate guard"),
                    isActive: vm.isIdleKeepAwakeActive,
                    actionTitle: vm.isIdleKeepAwakeActive ? vm.tr("释放", "Release") : vm.tr("激活", "Activate"),
                    action: { vm.toggleIdleKeepAwake() }
                )
            }

            HStack(spacing: 10) {
                telemetryCard(
                    icon: vm.powerStatus.isClamshellClosed ? "macbook.gen2" : "macbook",
                    title: vm.tr("盒盖与屏幕状态", "Lid & Display State"),
                    value: vm.powerStatus.isClamshellClosed
                        ? vm.tr("已合盖运行", "Lid Closed")
                        : vm.tr("开盖使用中", "Lid Open"),
                    subtitle: vm.tr(
                        "背光 \(Int(round(vm.powerStatus.displayBrightness * 100)))% · 显示管线\(vm.powerStatus.isDisplayAsleep ? "休眠" : "活跃")",
                        "Backlight \(Int(round(vm.powerStatus.displayBrightness * 100)))% · Display \(vm.powerStatus.isDisplayAsleep ? "Asleep" : "Awake")"
                    ),
                    isActive: !vm.powerStatus.isDisplayAsleep,
                    actionTitle: nil,
                    action: nil
                )

                telemetryCard(
                    icon: vm.powerStatus.isACPower ? "bolt.batteryblock.fill" : "battery.100",
                    title: vm.tr("电源与电池状态", "Power & Battery"),
                    value: vm.tr(
                        "\(vm.powerStatus.isACPower ? "外接电源" : "电池供电") · \(vm.powerStatus.batteryPercentage)%",
                        "\(vm.powerStatus.isACPower ? "AC Power" : "Battery") · \(vm.powerStatus.batteryPercentage)%"
                    ),
                    subtitle: vm.lowBatteryAutoRestoreEnabled
                        ? vm.tr("电量 ≤ \(vm.lowBatteryThreshold)% 自动恢复休眠", "Auto-restore sleep at ≤ \(vm.lowBatteryThreshold)%")
                        : vm.tr("低电量保护未启用", "Low battery protection off"),
                    isActive: vm.powerStatus.isACPower || vm.powerStatus.batteryPercentage > vm.lowBatteryThreshold,
                    actionTitle: nil,
                    action: nil
                )
            }
        }
    }

    private func telemetryCard(
        icon: String,
        title: String,
        value: String,
        subtitle: String,
        isActive: Bool,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? Color.green.opacity(isDark ? 0.18 : 0.12) : subtleFill)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isActive ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isActive ? Color.red.opacity(0.14) : Color.accentColor.opacity(0.15))
                        )
                        .foregroundColor(isActive ? .red : .accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    // MARK: - 4. 偏好设置与安全保护
    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(vm.tr("偏好与安全策略", "Preferences & Safety"), systemImage: "slider.horizontal.3")
                    .font(.system(size: 13.5, weight: .bold))

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: vm.isPasswordlessSudoInstalled ? "checkmark.seal.fill" : "key.fill")
                        .font(.system(size: 11.5))
                        .foregroundColor(vm.isPasswordlessSudoInstalled ? .green : .orange)
                    Text(vm.isPasswordlessSudoInstalled
                        ? vm.tr("已配置 pmset 免密切换", "Passwordless pmset ready")
                        : vm.tr("未配置免密权限", "Password required for pmset")
                    )
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    Button(action: { vm.togglePasswordlessSudo() }) {
                        Text(vm.isPasswordlessSudoInstalled
                            ? vm.tr("移除免密", "Remove Rule")
                            : vm.tr("配置免密切换", "Setup Passwordless")
                        )
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor.opacity(0.15))
                        )
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .opacity(0.6)

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle(
                        vm.tr("保持显示帧缓冲活跃（防合盖/关屏后画面黑屏）", "Keep display framebuffer awake (prevent black screen)"),
                        isOn: $vm.keepDisplayRendererAwake
                    )
                    .font(.system(size: 12))
                    Toggle(
                        vm.tr("低电量保护（电池 ≤ \(vm.lowBatteryThreshold)% 时自动恢复合盖休眠）", "Low battery guard (restore lid sleep at ≤ \(vm.lowBatteryThreshold)%)"),
                        isOn: $vm.lowBatteryAutoRestoreEnabled
                    )
                    .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 9) {
                    Toggle(
                        vm.tr("开机自动启动并激活防休眠", "Launch at login and auto-enable"),
                        isOn: Binding(
                            get: { vm.isLaunchAtLoginEnabled },
                            set: { _ in vm.toggleLaunchAtLogin() }
                        )
                    )
                    .font(.system(size: 12))
                    Toggle(
                        vm.tr("彻底退出应用时自动恢复系统默认休眠", "Restore default sleep when quitting app"),
                        isOn: $vm.restoreSleepOnAppQuit
                    )
                    .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    // MARK: - 5. 实时运行日志
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(vm.tr("运行日志", "Activity Log"), systemImage: "terminal")
                    .font(.system(size: 12.5, weight: .bold))
                Spacer()
                Text(vm.tr("\(vm.logs.count) 条记录", "\(vm.logs.count) entries"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(vm.logs) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.formattedTime)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(entry.message)
                                .font(.system(size: 11.5))
                                .foregroundColor(entry.isWarning ? .orange : .primary.opacity(0.88))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(subtleFill)
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }
}
