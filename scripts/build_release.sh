#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="1.0.1"
RELEASE_DIR="$PROJECT_DIR/release"
DIST_DIR="$PROJECT_DIR/dist"

echo "================================================================"
echo " 📦 BudHold v${VERSION} GitHub Release 安装包构建脚本"
echo "================================================================"

# 1. 编译通用二进制 (Universal Binary: arm64 + x86_64) 并生成 BudHold.app
echo "🔨 [1/5] 正在生成基础应用包与编译 Universal Binary (arm64 + x86_64, 兼容 macOS 13.0 ~ 26.x ~ 27.x)..."
"$PROJECT_DIR/scripts/bundle_app.sh" >/dev/null
swift build -c release --arch arm64 --arch x86_64 -Xlinker -w

UNIVERSAL_BUILD_DIR="$PROJECT_DIR/.build/apple/Products/Release"
if [ ! -f "$UNIVERSAL_BUILD_DIR/BudHoldApp" ]; then
    UNIVERSAL_BUILD_DIR="$PROJECT_DIR/.build/release"
fi

# 用 Universal 二进制替换并重新签名
cp "$UNIVERSAL_BUILD_DIR/BudHoldApp" "$DIST_DIR/BudHold.app/Contents/MacOS/BudHoldApp"
cp "$UNIVERSAL_BUILD_DIR/budhold" "$DIST_DIR/BudHold.app/Contents/MacOS/budhold"
cp "$UNIVERSAL_BUILD_DIR/budhold" "$DIST_DIR/budhold"
chmod +x "$DIST_DIR/BudHold.app/Contents/MacOS/BudHoldApp" "$DIST_DIR/BudHold.app/Contents/MacOS/budhold" "$DIST_DIR/budhold"
codesign --force --deep --sign - "$DIST_DIR/BudHold.app"
codesign --force --sign - "$DIST_DIR/budhold"

if [ -w "/Applications" ]; then
    rm -rf "/Applications/BudHold.app"
    cp -R "$DIST_DIR/BudHold.app" "/Applications/BudHold.app"
fi

echo "   架构信息: $(lipo -info "$DIST_DIR/BudHold.app/Contents/MacOS/BudHoldApp")"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# 2. 生成 .dmg 磁盘映像安装包 (带 Applications 拖拽快捷方式)
echo "💿 [2/5] 正在制作 DMG 磁盘映像安装包 (BudHold-v${VERSION}-macOS-universal.dmg)..."
DMG_STAGING="$RELEASE_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

cp -R "$DIST_DIR/BudHold.app" "$DMG_STAGING/BudHold.app"
ln -s /Applications "$DMG_STAGING/Applications"
cp "$PROJECT_DIR/README.md" "$DMG_STAGING/README.md"

DMG_PATH="$RELEASE_DIR/BudHold-v${VERSION}-macOS-universal.dmg"
hdiutil create \
    -volname "BudHold v${VERSION}" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$DMG_STAGING"

# 3. 生成 .pkg 标准安装程序包 (自动安装 /Applications/BudHold.app 与 /usr/local/bin/budhold)
echo "📦 [3/5] 正在制作 PKG 标准安装程序 (BudHold-v${VERSION}-macOS-universal.pkg)..."
PKG_ROOT="$RELEASE_DIR/pkg_root"
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"
mkdir -p "$PKG_ROOT/usr/local/bin"

cp -R "$DIST_DIR/BudHold.app" "$PKG_ROOT/Applications/BudHold.app"
cp "$DIST_DIR/budhold" "$PKG_ROOT/usr/local/bin/budhold"
chmod +x "$PKG_ROOT/usr/local/bin/budhold"

PKG_PATH="$RELEASE_DIR/BudHold-v${VERSION}-macOS-universal.pkg"
pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "com.budwk.app.budhold.pkg" \
    --version "$VERSION" \
    --install-location "/" \
    "$PKG_PATH" >/dev/null

rm -rf "$PKG_ROOT"

# 4. 生成 .zip 绿色便携版 & CLI 独立压缩包
echo "🗜️  [4/5] 正在制作 ZIP 便携包与 CLI 独立包..."
ZIP_APP_PATH="$RELEASE_DIR/BudHold-v${VERSION}-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$DIST_DIR/BudHold.app" "$ZIP_APP_PATH"

TAR_CLI_PATH="$RELEASE_DIR/budhold-cli-v${VERSION}-macOS-universal.tar.gz"
tar -czf "$TAR_CLI_PATH" -C "$DIST_DIR" budhold -C "$PROJECT_DIR" README.md

# 5. 生成 SHA256 校验和与 GitHub Release 发布说明模板
echo "🔐 [5/5] 正在计算 SHA256 校验和并生成 RELEASE_NOTES.md..."
cd "$RELEASE_DIR"
shasum -a 256 \
    "BudHold-v${VERSION}-macOS-universal.dmg" \
    "BudHold-v${VERSION}-macOS-universal.pkg" \
    "BudHold-v${VERSION}-macOS-universal.zip" \
    "budhold-cli-v${VERSION}-macOS-universal.tar.gz" \
    > SHA256SUMS.txt

cat > "$RELEASE_DIR/RELEASE_NOTES.md" <<EOF
## BudHold v${VERSION} — macOS 防休眠与合盖远程保活工具

支持 **Apple Silicon (M1/M2/M3/M4)** 与 **Intel (x86_64)** 双架构通用包 (Universal Binary)，全面兼容 **macOS 26.x (Tahoe)**、**macOS 27.x** 以及 **macOS 13 / 14 / 15**。

### ✨ 功能亮点
- **MacBook 合盖 + 关屏不休眠**：结合 \`IOKit\` 电源断言与内核级 \`SleepDisabled\` 锁，即使拔掉外接显示器并合上盖子，网络与图形渲染依旧保持 100% 运行。
- **远程桌面防黑屏**：周期性唤醒显示器帧缓冲 (\`IOPMAssertionDeclareUserActivity\`)，解决合盖或关屏后远程桌面（VNC / 屏幕共享等）画面黑屏问题。
- **物理熄屏挂机模式**：支持在开盖时将屏幕背光降为 \`0%\`（纯黑屏防窥省电），同时保持 GPU 渲染活跃，按 \`Esc\` 键即可恢复亮度。
- **免密切换与电池防闷烧保护**：支持一键配置 \`pmset\` 免密切换，以及电池供电低电量（≤20%）自动恢复合盖睡眠。

### 📥 下载与安装说明
| 文件名 | 适用人群与说明 |
| :--- | :--- |
| **\`BudHold-v${VERSION}-macOS-universal.dmg\`** | **推荐**：图形化拖拽安装包（拖入 \`Applications\` 即可使用） |
| **\`BudHold-v${VERSION}-macOS-universal.pkg\`** | 标准向导安装包（自动安装 \`/Applications/BudHold.app\` 与 \`/usr/local/bin/budhold\` CLI） |
| **\`BudHold-v${VERSION}-macOS-universal.zip\`** | 免安装便携压缩包（解压即用） |
| **\`budhold-cli-v${VERSION}-macOS-universal.tar.gz\`** | 纯命令行工具 \`budhold\` 独立包（适合 SSH / 终端用户） |

> 💡 **首次打开提示**：由于未挂载付费 Apple Developer ID 证书，首次打开若提示「无法验证开发者」，可在终端执行以下命令移除隔离属性后直接打开：
> \`\`\`bash
> sudo xattr -rd com.apple.quarantine /Applications/BudHold.app
> \`\`\`

### 🔐 SHA-256 校验和
\`\`\`text
$(cat "$RELEASE_DIR/SHA256SUMS.txt")
\`\`\`
EOF

echo ""
echo "✅ 所有 GitHub Release 产物已生成至: $RELEASE_DIR"
ls -lh "$RELEASE_DIR"
