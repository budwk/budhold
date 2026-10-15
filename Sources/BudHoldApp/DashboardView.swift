import SwiftUI
import BudHoldCore

public struct DashboardView: View {
    @ObservedObject var vm: AppViewModel

    public init(vm: AppViewModel) {
        self.vm = vm
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerBanner
                heroControlCard
                telemetryGrid
                rustDeskCard
                settingsAndSafetyCard
                logSection
            }
            .padding(20)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 680, idealHeight: 760)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            if let toast = vm.statusToast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.statusToast)
    }

    // MARK: - 1. 顶部系统版本与状态栏
    private var headerBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(vm.isFullRemoteModeActive ? Color.green.opacity(0.18) : Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: vm.isFullRemoteModeActive ? "bolt.shield.fill" : "laptopcomputer.and.iphone")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(vm.isFullRemoteModeActive ? .green : .blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("BudHold 防休眠与合盖保活工具")
                        .font(.system(size: 19, weight: .bold))
                    Text(vm.osInfo.versionBadgeString)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundColor(.accentColor)
                }
                Text("硬件平台：\(vm.osInfo.cpuBrand) (\(vm.osInfo.hardwareModel)) · \(vm.osInfo.architecture) · 主机：\(vm.osInfo.hostName)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            statusPill
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(vm.isFullRemoteModeActive ? Color.green : (vm.isIdleKeepAwakeActive ? Color.orange : Color.gray))
                .frame(width: 9, height: 9)
            Text(vm.isFullRemoteModeActive ? "合盖+关屏不休眠 · 运行中" : (vm.isIdleKeepAwakeActive ? "仅防空闲/关屏睡眠" : "系统默认睡眠模式"))
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(vm.isFullRemoteModeActive ? Color.green.opacity(0.14) : (vm.isIdleKeepAwakeActive ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.12)))
        )
    }

    // MARK: - 2. 核心一键开启总控卡片
    private var heroControlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.isFullRemoteModeActive ? "已开启全天候保活模式（合盖 & 关屏均不休眠）" : "一键开启「MacBook 合盖 + 显示器关闭」不休眠模式")
                        .font(.system(size: 16, weight: .bold))
                    Text("同时激活 IOKit 电源/显示渲染断言与内核级 SleepDisabled 锁，确保 MacBook 合上盖子或屏幕关闭后，网络与桌面图形渲染持续工作，支持 RustDesk / SSH / 屏幕共享等随时远程连接。")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: {
                    vm.toggleFullRemoteMode()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: vm.isFullRemoteModeActive ? "stop.circle.fill" : "power.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text(vm.isFullRemoteModeActive ? "关闭并恢复默认睡眠" : "一键开启合盖不休眠")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(vm.isFullRemoteModeActive ? Color.red : Color.green)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .foregroundColor(.secondary)
                    Text("持续时长：")
                        .font(.system(size: 12.5, weight: .medium))
                    Picker("", selection: $vm.selectedDuration) {
                        ForEach(KeepAwakeDuration.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                Spacer()

                Button(action: {
                    vm.toggleBlackoutMode()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: vm.isBlackoutModeActive ? "sun.max.fill" : "moon.stars.fill")
                        Text(vm.isBlackoutModeActive ? "恢复屏幕背光亮度" : "物理熄屏挂机 (背光0% · 远控正常)")
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(vm.isBlackoutModeActive ? Color.orange.opacity(0.2) : Color.primary.opacity(0.07))
                    )
                }
                .buttonStyle(.plain)

                Button(action: {
                    vm.refreshAll()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("刷新状态")
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(vm.isFullRemoteModeActive ? Color.green.opacity(0.07) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(vm.isFullRemoteModeActive ? Color.green.opacity(0.35) : Color.primary.opacity(0.1), lineWidth: 1.2)
        )
    }

    // MARK: - 3. 四维硬件与防休眠状态卡片
    private var telemetryGrid: some View {
        HStack(spacing: 12) {
            telemetryCard(
                icon: "lock.laptopcomputer",
                title: "合盖不休眠 (pmset)",
                value: vm.isClamshellKeepAwakeActive ? "已开启 (SleepDisabled)" : "未开启 (合盖将休眠)",
                subtitle: "内核级阻止 MacBook 合盖睡眠",
                isActive: vm.isClamshellKeepAwakeActive,
                actionTitle: vm.isClamshellKeepAwakeActive ? "关闭合盖锁" : "开启合盖锁",
                action: { vm.toggleClamshellKeepAwake() }
            )

            telemetryCard(
                icon: "display",
                title: "防空闲与关屏渲染",
                value: vm.isIdleKeepAwakeActive ? "已激活 (IOKit+Caffeinate)" : "未激活",
                subtitle: "保持桌面帧缓冲防止远控黑屏",
                isActive: vm.isIdleKeepAwakeActive,
                actionTitle: vm.isIdleKeepAwakeActive ? "释放断言" : "激活断言",
                action: { vm.toggleIdleKeepAwake() }
            )

            telemetryCard(
                icon: vm.powerStatus.isClamshellClosed ? "macbook.gen2" : "macbook",
                title: "盒盖与屏幕状态",
                value: vm.powerStatus.isClamshellClosed ? "已合盖 (Clamshell)" : "开盖使用中",
                subtitle: "屏幕背光: \(Int(round(vm.powerStatus.displayBrightness * 100)))% · 渲染: \(vm.powerStatus.isDisplayAsleep ? "休眠" : "活跃")",
                isActive: !vm.powerStatus.isDisplayAsleep,
                actionTitle: nil,
                action: nil
            )

            telemetryCard(
                icon: vm.powerStatus.isACPower ? "bolt.batteryblock.fill" : "battery.100",
                title: "电源与电池电量",
                value: "\(vm.powerStatus.isACPower ? "外接电源" : "电池供电") · \(vm.powerStatus.batteryPercentage)%",
                subtitle: vm.lowBatteryAutoRestoreEnabled ? "安全保护: ≤\(vm.lowBatteryThreshold)% 自动恢复睡眠" : "低电量保护已关闭",
                isActive: vm.powerStatus.isACPower || vm.powerStatus.batteryPercentage > vm.lowBatteryThreshold,
                actionTitle: nil,
                action: nil
            )
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isActive ? .green : .secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            Text(value)
                .font(.system(size: 13.5, weight: .bold))
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)

            if let actionTitle = actionTitle, let action = action {
                Spacer(minLength: 2)
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 4. 网络信息与按需可选的 RustDesk 监控卡片
    private var rustDeskCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(vm.rustDeskMonitoringEnabled ? (vm.rustDeskStatus.isReadyForRemote ? .green : .orange) : .secondary)
                Text("网络与 RustDesk 远程辅助（可选按需启用）")
                    .font(.system(size: 14.5, weight: .bold))

                Spacer()

                Toggle("启用 RustDesk 监控与守护", isOn: $vm.rustDeskMonitoringEnabled)
                    .toggleStyle(.switch)
                    .font(.system(size: 12, weight: .medium))
            }

            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("本机局域网 / 虚拟网 IP：")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(vm.powerStatus.localIPs.isEmpty ? "未连接网络" : vm.powerStatus.localIPs.joined(separator: "  |  "))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }

            if vm.rustDeskMonitoringEnabled {
                Divider()

                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本机 RustDesk ID")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Text(vm.rustDeskStatus.deviceID)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                            Button(action: { vm.copyRustDeskID() }) {
                                Label("复制", systemImage: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("客户端版本与进程")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                        Text("v\(vm.rustDeskStatus.version) · Server: \(vm.rustDeskStatus.isServerRunning ? "在线" : "离线") · Service: \(vm.rustDeskStatus.isServiceRunning ? "在线" : "离线")")
                            .font(.system(size: 12.5, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前活跃远程会话")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                        Text(vm.rustDeskStatus.activeConnectionCount > 0 ? "🟢 \(vm.rustDeskStatus.activeConnectionCount) 个活跃连接" : "⚪ 当前空闲（等待远控连接）")
                            .font(.system(size: 12.5, weight: .medium))
                    }

                    Spacer()

                    Button(action: {
                        vm.launchRustDesk()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.app")
                            Text(vm.rustDeskStatus.isServerRunning ? "打开 RustDesk" : "启动 RustDesk")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor.opacity(0.15))
                        )
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                Toggle("RustDesk 进程自动拉起守护（检测到 RustDesk 意外退出时自动重新启动）", isOn: $vm.rustDeskWatchdogEnabled)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 5. 免密配置与安全守护面板
    private var settingsAndSafetyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自动化与安全保护策略")
                .font(.system(size: 14, weight: .bold))

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("保持显示帧缓冲渲染活跃（防止合盖或关屏后远程桌面画面黑屏）", isOn: $vm.keepDisplayRendererAwake)
                        .font(.system(size: 12.5))
                    Toggle("低电量防闷烧保护（电池供电且电量 ≤ \(vm.lowBatteryThreshold)% 时自动恢复合盖休眠）", isOn: $vm.lowBatteryAutoRestoreEnabled)
                        .font(.system(size: 12.5))
                    Toggle("开机自动启动 BudHold 并激活防休眠", isOn: Binding(
                        get: { vm.isLaunchAtLoginEnabled },
                        set: { _ in vm.toggleLaunchAtLogin() }
                    ))
                    .font(.system(size: 12.5))
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("退出 BudHold 时自动恢复系统默认休眠设置", isOn: $vm.restoreSleepOnAppQuit)
                        .font(.system(size: 12.5))

                    HStack(spacing: 8) {
                        Image(systemName: vm.isPasswordlessSudoInstalled ? "checkmark.seal.fill" : "key.fill")
                            .foregroundColor(vm.isPasswordlessSudoInstalled ? .green : .orange)
                        Text(vm.isPasswordlessSudoInstalled ? "已配置 pmset 免密切换权限" : "切换合盖模式需输入管理员密码")
                            .font(.system(size: 12))
                        Button(action: { vm.togglePasswordlessSudo() }) {
                            Text(vm.isPasswordlessSudoInstalled ? "移除免密" : "一键配置免密切换")
                                .font(.system(size: 11.5, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 6. 实时运行日志面板
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("实时运行日志")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("共 \(vm.logs.count) 条记录")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(vm.logs) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text("[\(entry.formattedTime)]")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(entry.message)
                                .font(.system(size: 11.5))
                                .foregroundColor(entry.isWarning ? .orange : .primary)
                        }
                    }
                }
                .padding(8)
            }
            .frame(height: 110)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.04))
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
