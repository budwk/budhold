# BudHold — macOS 防休眠与合盖远程保活工具

**BudHold** 是一款基于 Swift + IOKit + SwiftUI 编写的原生 macOS 电源保活与远程值守工具。  
它能够实时检测当前 macOS 系统版本与硬件信息，阻止电脑进入睡眠——**即使 MacBook 合上盖子（无外接显示器）或显示器被关闭**，系统、网络与桌面图形帧缓冲也保持 100% 活跃，让 **RustDesk**、VNC、屏幕共享或 SSH 可随时远程连接且不会遇到黑屏或断联。

此外，BudHold 内置了**按需启用（非必须项）**的 RustDesk 状态监控与进程守护模块，不强制依赖 RustDesk，兼顾通用防休眠与远程控制场景。

### 🖥️ 系统与架构兼容性
- **支持系统版本**：全面兼容 **macOS 26.x (Tahoe)**、**macOS 27.x** 以及 **macOS 13 (Ventura) / 14 (Sonoma) / 15 (Sequoia)**（二进制最低部署目标 `minos 13.0`）。
- **支持芯片架构**：Universal Binary 通用二进制，原生支持 **Apple Silicon (`arm64`: M1 / M2 / M3 / M4)** 与 **Intel (`x86_64`)**。
- **多驱动背光兼容**：屏幕物理熄屏挂机内置 `DisplayServices` → `CoreDisplay` → `IODisplayParameters` 三级自动回退，无缝适配 macOS 26.x / 27.x 与旧版本。

---

## ✨ 核心特性

1. **实时获取当前 macOS 版本与硬件状态**
   - 自动通过 `sw_vers`、`sysctl` 与 `IOKit` 获取当前系统版本（如 `macOS 27.0.1 (Build 26A434)`）、芯片型号（如 `Apple M4`）、合盖传感器状态（`AppleClamshellState`）、内核休眠锁（`SleepDisabled`）、供电与电池百分比以及本机局域网/虚拟网 IP。
2. **三层防休眠架构（合盖 + 关屏均不睡眠）**
   - **第一层（IOKit 断言 + `caffeinate`）**：同时持有 `PreventUserIdleSystemSleep` 与 `PreventUserIdleDisplaySleep` 断言，阻止系统空闲睡眠。
   - **第二层（内核级合盖不休眠 `pmset disablesleep`）**：配置 `pmset -a disablesleep 1 tcpkeepalive 1 womp 1`，阻止 MacBook 合盖时触发硬件休眠。
   - **第三层（显示帧缓冲保活 `IOPMAssertionDeclareUserActivity`）**：当检测到显示器休眠或合盖时，周期性唤醒 GPU 帧缓冲渲染管线，解决 macOS 关屏/合盖后远控软件抓屏黑屏或画面卡死的问题。
3. **物理熄屏挂机模式（背光 0% 防窥省电）**
   - 在开盖状态下，支持通过 `DisplayServices` 将屏幕物理背光直接降至 `0%`（屏幕全黑），但 GPU 图形渲染保持活跃，远程控制画面依然清晰流畅；本地按下 `Esc` 键或点击按钮即可恢复原本亮度。
4. **RustDesk 监控与守护（非必须项 · 按需启用）**
   - **默认关闭**：不对系统产生多余的进程扫描开销，未安装 RustDesk 也可完整使用所有防休眠与合盖保活功能。
   - **按需开启**：可在图形界面或通过 CLI（`budhold rustdesk on` / `--rustdesk`）一键开启，开启后支持显示并复制本机 RustDesk ID、监控 `RustDesk --server` 与 `service` 状态、统计活跃远控连接，并在进程意外退出时自动拉起。
5. **免密切换与电池防闷烧安全保护**
   - **一键配置免密切换**：支持配置 `/etc/sudoers.d/budhold`，首次授权后，日常开关「合盖不休眠」无需每次弹窗输入密码。
   - **低电量自动恢复休眠**：当使用电池供电且电量低于设定阈值（默认 `20%`）时，自动解除合盖不休眠锁，防止将笔记本装入背包后过热或亏电。
   - **支持定时模式与开机自启**：支持不限时、1/2/4/8/24 小时定时保活，以及 `LaunchAgent` 开机自启动。

---

## 📦 编译与安装

项目使用 Swift Package Manager 构建，同时生成桌面/状态栏应用 `BudHold.app` 与命令行工具 `budhold`。

```bash
# 一键编译 Release 版本、生成应用图标、签名并打包至 dist/BudHold.app 及 /Applications/BudHold.app
./scripts/bundle_app.sh
```

打包完成后会生成：
- **图形界面与状态栏应用**：`/Applications/BudHold.app`（及 `./dist/BudHold.app`）
- **命令行工具**：`./dist/budhold`（也可复制软链到 `/usr/local/bin/budhold`）

---

## 🖥️ 使用指南

### 1. 图形界面与顶部菜单栏 (`BudHold.app`)

启动应用：
```bash
open /Applications/BudHold.app
```

- **主控制台面板**：
  - 点击右上角 **「一键开启合盖不休眠」** 即可激活「合盖 + 关屏不休眠」模式。
  - 点击 **「物理熄屏挂机 (背光0% · 远控正常)」** 可在开盖时黑屏运行（按 `Esc` 键恢复亮度）。
  - 在 **「网络与 RustDesk 远程辅助（可选按需启用）」** 卡片中，可随时按需打开或关闭 **「启用 RustDesk 监控与守护」** 开关。
  - 在 **「自动化与安全保护策略」** 中，可点击 **「一键配置免密切换」** 免除后续切换合盖模式时的密码弹窗。
- **顶部状态栏菜单与后台常驻机制**：
  - 常驻屏幕右上角菜单栏，支持快捷键 `⌘K` 一键切换合盖不休眠、`⌘B` 切换物理熄屏挂机，以及按需开关 RustDesk 监控。
  - **防误退设计**：点击窗口左上角关闭按钮、或在底部程序坞（Dock）右键点击「退出」/ 按 `⌘Q` 时，**不会退出软件**，而是自动隐藏窗口与底部图标并转入顶部状态栏后台运行；只有点击屏幕右上角顶部菜单栏图标中的 **「退出 BudHold（彻底退出）」** 才会真正退出程序。

---

### 2. 命令行工具 (`budhold`)

#### 查看当前系统版本与防休眠状态
```bash
# 默认查看系统版本、合盖锁、显示器帧缓冲、电源与网络状态（默认不扫描 RustDesk）
./dist/budhold status

# 临时附带查询 RustDesk 状态
./dist/budhold status --rustdesk
```

#### 开启与关闭「合盖 + 关屏不休眠」
```bash
# 一键开启「合盖+关屏不休眠」模式
./dist/budhold on

# 开启并在前台持续驻留守护（支持 Ctrl+C 退出时自动恢复系统默认休眠）
./dist/budhold on --daemon

# 开启防休眠并同时按需启用 RustDesk 进程守护
./dist/budhold on --daemon --rustdesk

# 关闭所有防休眠，恢复 macOS 默认合盖与空闲睡眠策略
./dist/budhold off
```

#### 按需启用 / 关闭 RustDesk 监控（非必须项）
```bash
# 持久开启 RustDesk 监控与守护
./dist/budhold rustdesk on

# 关闭 RustDesk 监控与守护
./dist/budhold rustdesk off

# 单独查看 RustDesk 状态
./dist/budhold rustdesk status
```

#### 物理熄屏挂机（背光 0%，远程画面正常）
```bash
# 将物理屏幕背光调至 0%（黑屏），同时保持 GPU 渲染活跃
./dist/budhold blackout on

# 恢复屏幕背光亮度
./dist/budhold blackout off
```

#### 配置 / 移除 `pmset` 免密切换权限
```bash
# 配置 /etc/sudoers.d/budhold 免密规则（仅允许免密执行 /usr/bin/pmset）
./dist/budhold install-sudoers

# 移除免密规则
./dist/budhold remove-sudoers
```

---

## 📂 项目目录结构

```text
budhold/
├── Package.swift                                    # Swift Package 工程定义
├── README.md                                        # 项目说明文档
├── scripts/
│   └── bundle_app.sh                                # 一键编译、图标生成、签名与打包脚本
└── Sources/
    ├── BudHoldCore/                                 # 核心库
    │   ├── SystemInfoService.swift                  # macOS 版本号、硬件、合盖状态、电源与 IP 检测
    │   ├── PowerKeepAliveManager.swift              # 三层防休眠引擎、pmset 免密管理与低电量保护
    │   ├── DisplayBrightnessController.swift        # 物理背光控制与显示帧缓冲唤醒
    │   ├── RustDeskMonitor.swift                    # 按需可选的 RustDesk 状态监控与进程自愈
    │   └── LaunchAgentManager.swift                 # LaunchAgent 开机自启管理
    ├── BudHoldApp/                                  # 原生桌面与状态栏 GUI 应用
    │   ├── BudHoldApp.swift                         # 应用入口与状态栏菜单控制
    │   ├── AppViewModel.swift                       # 状态绑定与交互逻辑
    │   └── DashboardView.swift                      # SwiftUI 主控制台界面
    └── BudHoldCLI/                                  # 命令行工具
        └── main.swift                               # budhold CLI 命令解析与输出
```

---

## ⚠️ 安全注意事项

- **散热与电池安全**：当开启「合盖不休眠」(`SleepDisabled = Yes`) 后，MacBook 即使合上盖子也不会进入睡眠。**请勿在开启合盖不休眠且未关机的情况下将笔记本放入密闭内胆包或双肩包中**，以免在包内持续运行导致积热。建议保持开启「低电量防闷烧保护」（默认电量 ≤ 20% 自动恢复合盖休眠）。
- **紧急恢复默认睡眠**：如果任何时候希望手动通过系统终端恢复默认合盖睡眠，只需执行 `./dist/budhold off` 或 `sudo pmset -a disablesleep 0`。
