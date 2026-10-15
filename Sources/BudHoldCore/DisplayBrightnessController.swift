import Foundation
import CoreGraphics
import IOKit
import IOKit.pwr_mgt

/// 控制屏幕背光亮度与唤醒显示器渲染缓冲区（支持「关屏/黑屏挂机但保持 RustDesk 画面正常渲染」）
public final class DisplayBrightnessController {
    public static let shared = DisplayBrightnessController()

    private typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var getBrightnessSym: GetBrightnessFunc?
    private var setBrightnessSym: SetBrightnessFunc?

    /// 记录进入「熄屏挂机模式」前的屏幕亮度，以便恢复
    public private(set) var savedBrightnessBeforeBlackout: Float?
    public private(set) var isBlackoutModeActive: Bool = false

    private init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            if let symGet = dlsym(handle, "DisplayServicesGetBrightness") {
                getBrightnessSym = unsafeBitCast(symGet, to: GetBrightnessFunc.self)
            }
            if let symSet = dlsym(handle, "DisplayServicesSetBrightness") {
                setBrightnessSym = unsafeBitCast(symSet, to: SetBrightnessFunc.self)
            }
        }
    }

    /// 获取当前主显示器背光亮度 (0.0 ~ 1.0)
    public func getBrightness() -> Float? {
        guard let getBrightness = getBrightnessSym else { return nil }
        var brightness: Float = -1.0
        let res = getBrightness(CGMainDisplayID(), &brightness)
        guard res == 0, brightness >= 0 else { return nil }
        return brightness
    }

    /// 设置主显示器背光亮度 (0.0 ~ 1.0)
    @discardableResult
    public func setBrightness(_ value: Float) -> Bool {
        guard let setBrightness = setBrightnessSym else { return false }
        let clamped = max(0.0, min(1.0, value))
        return setBrightness(CGMainDisplayID(), clamped) == 0
    }

    /// 开启「物理熄屏挂机」：将物理屏幕背光调至 0（完全黑屏），同时保持 GPU 渲染缓冲区唤醒，确保 RustDesk 远控不黑屏
    public func enableBlackoutMode() -> Bool {
        if let current = getBrightness(), current > 0.05 {
            savedBrightnessBeforeBlackout = current
        } else if savedBrightnessBeforeBlackout == nil {
            savedBrightnessBeforeBlackout = 0.75
        }
        wakeDisplayFramebuffer()
        let ok = setBrightness(0.0)
        if ok {
            isBlackoutModeActive = true
        }
        return ok
    }

    /// 关闭「物理熄屏挂机」：恢复原本的屏幕背光亮度
    public func disableBlackoutMode() -> Bool {
        wakeDisplayFramebuffer()
        let target = savedBrightnessBeforeBlackout ?? 0.75
        let ok = setBrightness(max(0.25, target))
        isBlackoutModeActive = false
        return ok
    }

    /// 唤醒显示器渲染管线（当显示器处于 CGDisplayIsAsleep 状态时，通过 IOKit 声明用户活动唤醒帧缓冲，避免 RustDesk 抓屏黑屏）
    @discardableResult
    public func wakeDisplayFramebuffer() -> Bool {
        var assertionID: IOPMAssertionID = 0
        let ret = IOPMAssertionDeclareUserActivity(
            "BudHold Keep Display Framebuffer Awake for RustDesk" as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )
        return ret == kIOReturnSuccess
    }
}
