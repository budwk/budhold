#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "================================================================"
echo " 🍎 BudHold — Mac App Store 构建、打包与上传脚本"
echo "    Bundle ID: com.budwk.app.budhold"
echo "================================================================"

# 可选环境变量配置（支持自动签名与上传）：
#   DEVELOPMENT_TEAM          - Apple Developer Team ID (如: ABCDE12345)
#   APP_STORE_CONNECT_API_KEY - App Store Connect API Key ID (可选，用于 altool / notarytool 上传)
#   APP_STORE_CONNECT_ISSUER  - App Store Connect Issuer ID (可选)
#   APPLE_ID                  - Apple ID 邮箱 (可选，配合 APP_SPECIFIC_PASSWORD 上传)
#   APP_SPECIFIC_PASSWORD     - 应用专用密码 (可选)

ARCHIVE_PATH="$PROJECT_DIR/build/BudHold.xcarchive"
EXPORT_DIR="$PROJECT_DIR/build/appstore_export"
EXPORT_OPTIONS_PLIST="$PROJECT_DIR/build/ExportOptions.plist"

# 1. 若安装了 xcodegen，则可自动同步生成最新的 BudHold.xcodeproj
if command -v xcodegen >/dev/null 2>&1; then
    echo "🔧 [1/4] 正在通过 XcodeGen 更新 BudHold.xcodeproj..."
    xcodegen generate
else
    echo "ℹ️  [1/4] 使用现有的 BudHold.xcodeproj..."
fi

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$PROJECT_DIR/build"

TEAM_ARG=()
if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
    TEAM_ARG=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
    echo "   使用开发者 Team ID: $DEVELOPMENT_TEAM"
fi

echo "🔨 [2/4] 正在执行 Xcode Archive (Release / Universal Binary)..."
xcodebuild archive \
    -project "$PROJECT_DIR/BudHold.xcodeproj" \
    -scheme "BudHold" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    PRODUCT_BUNDLE_IDENTIFIER="com.budwk.app.budhold" \
    "${TEAM_ARG[@]}"

echo "✅ Archive 构建成功: $ARCHIVE_PATH"

# 2. 生成 ExportOptions.plist 并导出 Mac App Store 安装包 (.pkg)
cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
$(if [ -n "${DEVELOPMENT_TEAM:-}" ]; then echo "    <key>teamID</key><string>${DEVELOPMENT_TEAM}</string>"; fi)
</dict>
</plist>
EOF

echo "📦 [3/4] 正在导出 Mac App Store 提交包 (.pkg)..."
if xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
    -allowProvisioningUpdates; then
    echo "✅ 导出成功: $EXPORT_DIR/BudHold.pkg"
else
    echo "⚠️  自动导出 .pkg 需要本机 Xcode 登录含『3rd Party Mac Developer Installer』证书的 Apple 开发者账号。"
    echo "   您也可以直接打开 Xcode Organizer 窗口进行可视化提交："
    echo "   open \"$ARCHIVE_PATH\""
    exit 0
fi

PKG_FILE="$EXPORT_DIR/BudHold.pkg"

# 3. 上传至 App Store Connect（如提供了凭据）
echo "🚀 [4/4] 检查 App Store Connect 上传配置..."
if [ -n "${APP_STORE_CONNECT_API_KEY:-}" ] && [ -n "${APP_STORE_CONNECT_ISSUER:-}" ]; then
    echo "   正在通过 API Key 上传至 App Store Connect..."
    xcrun altool --upload-app \
        -f "$PKG_FILE" \
        -t macos \
        --apiKey "$APP_STORE_CONNECT_API_KEY" \
        --apiIssuer "$APP_STORE_CONNECT_ISSUER"
    echo "🎉 上传完成！"
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
    echo "   正在通过 Apple ID 上传至 App Store Connect..."
    xcrun altool --upload-app \
        -f "$PKG_FILE" \
        -t macos \
        -u "$APPLE_ID" \
        -p "$APP_SPECIFIC_PASSWORD"
    echo "🎉 上传完成！"
else
    echo "💡 已生成待上传安装包: $PKG_FILE"
    echo "   方式 A（推荐 GUI）：执行 'open \"$ARCHIVE_PATH\"' 在 Xcode Organizer 中点击 Distribute App 一键上传。"
    echo "   方式 B（命令行）：设置环境变量后重新执行本脚本，或直接运行："
    echo "   xcrun altool --upload-app -f \"$PKG_FILE\" -t macos -u \"您的AppleID\" -p \"应用专用密码\""
fi
