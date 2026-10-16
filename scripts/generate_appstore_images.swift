#!/usr/bin/env swift
import AppKit
import CoreGraphics

struct PromoSpec {
    let sourcePath: String
    let isChinese: Bool
    let badgeText: String
    let titleText: String
    let subtitleText: String
    let pills: [String]
    let outputPrefix: String
}

let specs: [PromoSpec] = [
    PromoSpec(
        sourcePath: "cc1.png",
        isChinese: true,
        badgeText: "BudHold · 原生 macOS 防休眠与合盖保活工具",
        titleText: "MacBook 合盖与关屏全天候保活",
        subtitleText: "内核级休眠锁 · 显示渲染常亮防黑屏 · 物理熄屏挂机 (背光 0%) · 低电量安全保护",
        pills: ["💻 合盖不休眠", "🌑 物理熄屏挂机", "🔋 低电量自动保护", "🔒 100% 纯本地运行"],
        outputPrefix: "cc1_zh"
    ),
    PromoSpec(
        sourcePath: "cc2.png",
        isChinese: false,
        badgeText: "BudHold · Native macOS Clamshell & Sleep Guard",
        titleText: "Keep Your Mac Awake with Lid Closed",
        subtitleText: "Kernel Clamshell Lock · GPU Framebuffer Guard · 0% Display Blackout · Low-Battery Safety",
        pills: ["💻 Clamshell Awake", "🌑 0% Display Blackout", "🔋 Low-Battery Guard", "🔒 100% Offline & Local"],
        outputPrefix: "cc2_en"
    )
]

let targetSizes: [(width: Int, height: Int, label: String)] = [
    (2880, 1800, "2880x1800"),
    (2560, 1600, "2560x1600"),
    (1440, 900,  "1440x900"),
    (1280, 800,  "1280x800"),
    (1920, 1080, "1920x1080_preview")
]

let outDir = "appstore_images"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func renderPromoImage(spec: PromoSpec, width: Int, height: Int, outputPath: String) {
    guard let srcImage = NSImage(contentsOfFile: spec.sourcePath) else {
        print("Failed to load \(spec.sourcePath)")
        return
    }

    var srcRect = NSRect(origin: .zero, size: srcImage.size)
    guard let cgSrc = srcImage.cgImage(forProposedRect: &srcRect, context: nil, hints: nil) else {
        return
    }
    let srcPixelW = CGFloat(cgSrc.width)
    let srcPixelH = CGFloat(cgSrc.height)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let W = CGFloat(width)
    let H = CGFloat(height)
    let scale = H / 1800.0

    // 1. 绘制深邃科技感渐变背景 (无透明通道，完全不透明，符合 App Store 规范)
    let fullRect = NSRect(x: 0, y: 0, width: W, height: H)
    let bgGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.045, green: 0.065, blue: 0.115, alpha: 1.0),
        NSColor(calibratedRed: 0.06,  green: 0.11,  blue: 0.17,  alpha: 1.0),
        NSColor(calibratedRed: 0.035, green: 0.05,  blue: 0.09,  alpha: 1.0)
    ])!
    bgGradient.draw(in: fullRect, angle: -55)

    // 顶部与底部装饰性柔光光晕
    let glowColors = [
        NSColor(calibratedRed: 0.06, green: 0.72, blue: 0.50, alpha: 0.20).cgColor,
        NSColor(calibratedRed: 0.06, green: 0.72, blue: 0.50, alpha: 0.0).cgColor
    ] as CFArray
    if let radial = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0.0, 1.0]) {
        cg.drawRadialGradient(
            radial,
            startCenter: CGPoint(x: W * 0.5, y: H * 0.86),
            startRadius: 10,
            endCenter: CGPoint(x: W * 0.5, y: H * 0.82),
            endRadius: W * 0.48,
            options: []
        )
    }

    let blueGlowColors = [
        NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.92, alpha: 0.16).cgColor,
        NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.92, alpha: 0.0).cgColor
    ] as CFArray
    if let radialBlue = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: blueGlowColors, locations: [0.0, 1.0]) {
        cg.drawRadialGradient(
            radialBlue,
            startCenter: CGPoint(x: W * 0.5, y: H * 0.35),
            startRadius: 10,
            endCenter: CGPoint(x: W * 0.5, y: H * 0.35),
            endRadius: W * 0.52,
            options: []
        )
    }

    // 2. 顶部宣传文案排版
    let topMargin = 72.0 * scale

    // 2.1 顶部胶囊标签 (Badge)
    let badgeFont = NSFont.systemFont(ofSize: 22.0 * scale, weight: .semibold)
    let badgeAttrs: [NSAttributedString.Key: Any] = [
        .font: badgeFont,
        .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.92, blue: 0.72, alpha: 1.0)
    ]
    let badgeStr = NSAttributedString(string: spec.badgeText, attributes: badgeAttrs)
    let badgeSize = badgeStr.size()
    let badgePadX = 24.0 * scale
    let badgePadY = 9.0 * scale
    let badgeW = badgeSize.width + badgePadX * 2
    let badgeH = badgeSize.height + badgePadY * 2
    let badgeY = H - topMargin - badgeH
    let badgeRect = NSRect(x: (W - badgeW) / 2.0, y: badgeY, width: badgeW, height: badgeH)

    let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2.0, yRadius: badgeH / 2.0)
    NSColor(calibratedRed: 0.06, green: 0.72, blue: 0.50, alpha: 0.16).setFill()
    badgePath.fill()
    NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.65, alpha: 0.38).setStroke()
    badgePath.lineWidth = 1.5 * scale
    badgePath.stroke()

    badgeStr.draw(at: NSPoint(x: badgeRect.minX + badgePadX, y: badgeRect.minY + badgePadY))

    // 2.2 主标题 (Headline)
    let titleFont = NSFont.systemFont(ofSize: 58.0 * scale, weight: .bold)
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor.white
    ]
    let titleStr = NSAttributedString(string: spec.titleText, attributes: titleAttrs)
    let titleSize = titleStr.size()
    let titleY = badgeY - 22.0 * scale - titleSize.height
    titleStr.draw(at: NSPoint(x: (W - titleSize.width) / 2.0, y: titleY))

    // 2.3 副标题 (Subtitle)
    let subFont = NSFont.systemFont(ofSize: 25.0 * scale, weight: .medium)
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: subFont,
        .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1.0)
    ]
    let subStr = NSAttributedString(string: spec.subtitleText, attributes: subAttrs)
    let subSize = subStr.size()
    let subY = titleY - 16.0 * scale - subSize.height
    subStr.draw(at: NSPoint(x: (W - subSize.width) / 2.0, y: subY))

    // 3. 底部卖点标签栏 (Feature Pills)
    let pillFont = NSFont.systemFont(ofSize: 20.0 * scale, weight: .medium)
    let pillAttrs: [NSAttributedString.Key: Any] = [
        .font: pillFont,
        .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1.0)
    ]
    let pillPadX = 20.0 * scale
    let pillPadY = 8.0 * scale
    let pillSpacing = 18.0 * scale

    var pillSizes: [NSSize] = []
    var totalPillsW: CGFloat = 0
    for p in spec.pills {
        let s = NSAttributedString(string: p, attributes: pillAttrs).size()
        let boxSize = NSSize(width: s.width + pillPadX * 2, height: s.height + pillPadY * 2)
        pillSizes.append(boxSize)
        totalPillsW += boxSize.width
    }
    totalPillsW += CGFloat(max(0, spec.pills.count - 1)) * pillSpacing

    let bottomMargin = 48.0 * scale
    let pillH = pillSizes.first?.height ?? (40.0 * scale)
    let pillY = bottomMargin
    var curX = (W - totalPillsW) / 2.0

    for (idx, p) in spec.pills.enumerated() {
        let box = pillSizes[idx]
        let r = NSRect(x: curX, y: pillY, width: box.width, height: box.height)
        let path = NSBezierPath(roundedRect: r, xRadius: 12.0 * scale, yRadius: 12.0 * scale)
        NSColor(calibratedWhite: 1.0, alpha: 0.07).setFill()
        path.fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.14).setStroke()
        path.lineWidth = 1.0 * scale
        path.stroke()

        let s = NSAttributedString(string: p, attributes: pillAttrs)
        s.draw(at: NSPoint(x: r.minX + pillPadX, y: r.minY + pillPadY))
        curX += box.width + pillSpacing
    }

    // 4. 中央应用截图展示区域（带立体投影与精致边框）
    let availTop = subY - 34.0 * scale
    let availBottom = pillY + pillH + 34.0 * scale
    let availH = availTop - availBottom
    let availW = W * 0.86

    let imgScale = min(availW / srcPixelW, availH / srcPixelH)
    let drawW = round(srcPixelW * imgScale)
    let drawH = round(srcPixelH * imgScale)
    let drawX = round((W - drawW) / 2.0)
    let drawY = round(availBottom + (availH - drawH) / 2.0)
    let imgRect = NSRect(x: drawX, y: drawY, width: drawW, height: drawH)

    let cornerRadius = 18.0 * scale

    // 外层阴影发光框
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -18.0 * scale)
    shadow.shadowBlurRadius = 45.0 * scale
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.68)
    shadow.set()

    let shadowBgPath = NSBezierPath(roundedRect: imgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor(calibratedRed: 0.1, green: 0.11, blue: 0.14, alpha: 1.0).setFill()
    shadowBgPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 裁剪圆角并绘制高清截图
    NSGraphicsContext.saveGraphicsState()
    let clipPath = NSBezierPath(roundedRect: imgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    clipPath.addClip()
    ctx.imageInterpolation = .high
    cg.draw(cgSrc, in: imgRect)
    NSGraphicsContext.restoreGraphicsState()

    // 高光细边框
    let borderPath = NSBezierPath(roundedRect: imgRect.insetBy(dx: -0.5, dy: -0.5), xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
    borderPath.lineWidth = 1.5 * scale
    borderPath.stroke()

    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Generated: \(outputPath) (\(width)x\(height))")
    }
}

for spec in specs {
    for size in targetSizes {
        let outFile = "\(outDir)/\(spec.outputPrefix)_\(size.label).png"
        renderPromoImage(spec: spec, width: size.width, height: size.height, outputPath: outFile)
    }
}

// 同时将 2880x1800 主宣传图覆盖到根目录的 cc1.png 与 cc2.png，方便直接使用
try? FileManager.default.removeItem(atPath: "cc1.png")
try? FileManager.default.copyItem(atPath: "\(outDir)/cc1_zh_2880x1800.png", toPath: "cc1.png")

try? FileManager.default.removeItem(atPath: "cc2.png")
try? FileManager.default.copyItem(atPath: "\(outDir)/cc2_en_2880x1800.png", toPath: "cc2.png")
print("Updated root cc1.png and cc2.png to 2880x1800 App Store screenshots.")
