#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "🔨 [1/4] 正在编译 Release 版本 (BudHoldApp & budhold CLI)..."
swift build -c release

BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/BudHold.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "🎨 [2/4] 正在生成 macOS 应用图标 (AppIcon.icns)..."
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift -target arm64-apple-macosx13.0 -e '
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outDir = "'"$ICONSET_DIR"'"

for size in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = CGFloat(size) * 0.08
    let bgRect = rect.insetBy(dx: inset, dy: inset)
    let radius = CGFloat(size) * 0.22
    let path = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.14, blue: 0.28, alpha: 1.0),
        NSColor(calibratedRed: 0.08, green: 0.45, blue: 0.36, alpha: 1.0)
    ])!
    gradient.draw(in: path, angle: -45)

    if let symbol = NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.48, weight: .bold)
            .applying(.init(paletteColors: [.white]))
        if let configured = symbol.withSymbolConfiguration(config) {
            let symSize = configured.size
            let drawRect = NSRect(
                x: (CGFloat(size) - symSize.width) / 2.0,
                y: (CGFloat(size) - symSize.height) / 2.0,
                width: symSize.width,
                height: symSize.height
            )
            configured.draw(in: drawRect)
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size)x\(size).png"))
    }
}
'

cp "$ICONSET_DIR/icon_32x32.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_32x32@2x.png"
cp "$ICONSET_DIR/icon_256x256.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICONSET_DIR/icon_512x512.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICONSET_DIR/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
rm -f "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_1024x1024.png"

iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR"

echo "📦 [3/4] 正在组装 BudHold.app 应用包..."
cp "$BUILD_DIR/BudHoldApp" "$APP_BUNDLE/Contents/MacOS/BudHoldApp"
cp "$BUILD_DIR/budhold" "$APP_BUNDLE/Contents/MacOS/budhold"
cp "$BUILD_DIR/budhold" "$DIST_DIR/budhold"
chmod +x "$APP_BUNDLE/Contents/MacOS/BudHoldApp" "$APP_BUNDLE/Contents/MacOS/budhold" "$DIST_DIR/budhold"

MACOS_VER="$(sw_vers -productVersion)"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string>
        <string>en</string>
    </array>
    <key>CFBundleDisplayName</key>
    <string>BudHold</string>
    <key>CFBundleExecutable</key>
    <string>BudHoldApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.budwk.app.budhold</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>BudHold</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>BudHold — Compatible with macOS 13.0 ~ 26.x ~ 27.x</string>
</dict>
</plist>
EOF

echo "🔏 [4/4] 正在进行本地代码签名..."
codesign --force --deep --sign - "$APP_BUNDLE"

# 同步安装一份到 /Applications/BudHold.app 方便直接从启动台/聚焦搜索启动
if [ -w "/Applications" ]; then
    rm -rf "/Applications/BudHold.app"
    cp -R "$APP_BUNDLE" "/Applications/BudHold.app"
    echo "✅ 已同步安装至 /Applications/BudHold.app"
fi

echo "🎉 打包完成！"
echo "   • 图形界面应用: $APP_BUNDLE (及 /Applications/BudHold.app)"
echo "   • 命令行工具  : $DIST_DIR/budhold"
