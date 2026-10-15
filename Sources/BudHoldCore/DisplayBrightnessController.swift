import Foundation
import CoreGraphics
import IOKit
import IOKit.pwr_mgt

/// 控制屏幕背光亮度与唤醒显示器渲染缓冲区（兼容 macOS 13 ~ 26.x ~ 27.x，支持 DisplayServices / CoreDisplay / IOKit 三重回退）
public final class DisplayBrightnessController {
    public static let shared = DisplayBrightnessController()

    private typealias DSGetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private typealias CDGetBrightnessFunc = @convention(c) (CGDirectDisplayID) -> Double
    private typealias CDSetBrightnessFunc = @convention(c) (CGDirectDisplayID, Double) -> Void

    private var dsGetBrightness: DSGetBrightnessFunc?
    private var dsSetBrightness: DSSetBrightnessFunc?
    private var cdGetBrightness: CDGetBrightnessFunc?
    private var cdSetBrightness: CDSetBrightnessFunc?

    /// 记录进入「熄屏挂机模式」前的屏幕亮度，以便恢复
    public private(set) var savedBrightnessBeforeBlackout: Float?
    public private(set) var isBlackoutModeActive: Bool = false

    private init() {
        // 1. 优先加载 DisplayServices.framework (macOS 14 / 15 / 26.x / 27.x 主流接口)
        if let dsHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            if let symGet = dlsym(dsHandle, "DisplayServicesGetBrightness") {
                dsGetBrightness = unsafeBitCast(symGet, to: DSGetBrightnessFunc.self)
            }
            if let symSet = dlsym(dsHandle, "DisplayServicesSetBrightness") {
                dsSetBrightness = unsafeBitCast(symSet, to: DSSetBrightnessFunc.self)
            }
        }

        // 2. 备选加载 CoreDisplay.framework (部分 macOS 13 ~ 26.x 机型兼容接口)
        if let cdHandle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) {
            if let symGet = dlsym(cdHandle, "CoreDisplay_Display_GetUserBrightness") {
                cdGetBrightness = unsafeBitCast(symGet, to: CDGetBrightnessFunc.self)
            }
            if let symSet = dlsym(cdHandle, "CoreDisplay_Display_SetUserBrightness") {
                cdSetBrightness = unsafeBitCast(symSet, to: CDSetBrightnessFunc.self)
            }
        }
    }

    /// 获取当前主显示器背光亮度 (0.0 ~ 1.0)
    public func getBrightness() -> Float? {
        let displayID = CGMainDisplayID()

        // 方式 1: DisplayServices
        if let getFn = dsGetBrightness {
            var brightness: Float = -1.0
            let res = getFn(displayID, &brightness)
            if res == 0 && brightness >= 0.0 && brightness <= 1.0 {
                return brightness
            }
        }

        // 方式 2: CoreDisplay
        if let cdGetFn = cdGetBrightness {
            let val = Float(cdGetFn(displayID))
            if val >= 0.0 && val <= 1.0 {
                return val
            }
        }

        // 方式 3: IODisplayGetFloatParameter (Intel / 传统 IOKit 驱动回退)
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess {
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var brightness: Float = -1.0
                let err = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
                IOObjectRelease(service)
                if err == kIOReturnSuccess && brightness >= 0.0 && brightness <= 1.0 {
                    return brightness
                }
                service = IOIteratorNext(iterator)
            }
        }

        return nil
    }

    /// 设置主显示器背光亮度 (0.0 ~ 1.0)
    @discardableResult
    public func setBrightness(_ value: Float) -> Bool {
        let clamped = max(0.0, min(1.0, value))
        let displayID = CGMainDisplayID()

        // 方式 1: DisplayServices
        if let setFn = dsSetBrightness {
            if setFn(displayID, clamped) == 0 {
                return true
            }
        }

        // 方式 2: CoreDisplay
        if let cdSetFn = cdSetBrightness {
            cdSetFn(displayID, Double(clamped))
            return true
        }

        // 方式 3: IODisplaySetFloatParameter
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess {
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            var success = false
            while service != 0 {
                let err = IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, clamped)
                IOObjectRelease(service)
                if err == kIOReturnSuccess {
                    success = true
                }
                service = IOIteratorNext(iterator)
            }
            if success { return true }
        }

        return false
    }

    /// 开启「物理熄屏挂机」：将物理屏幕背光调至 0（完全黑屏），同时保持 GPU 渲染缓冲区唤醒，确保远程桌面不黑屏
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

    /// 唤醒显示器渲染管线（当显示器处于 CGDisplayIsAsleep 状态时，通过 IOKit 声明用户活动唤醒帧缓冲，避免远程控制抓屏黑屏）
    @discardableResult
    public func wakeDisplayFramebuffer() -> Bool {
        var assertionID: IOPMAssertionID = 0
        let ret = IOPMAssertionDeclareUserActivity(
            "BudHold Keep Display Framebuffer Awake" as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )
        return ret == kIOReturnSuccess
    }
}
