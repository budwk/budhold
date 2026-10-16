import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en = "en"

    public var id: String { rawValue }

    /// 判断当前实际生效的语言是否为中文
    public var resolvedIsChinese: Bool {
        switch self {
        case .zhHans:
            return true
        case .en:
            return false
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("zh")
        }
    }

    public func displayName(in currentLang: AppLanguage = L10n.shared.language) -> String {
        let isZh = currentLang.resolvedIsChinese
        switch self {
        case .system:
            return isZh ? "跟随系统 (Auto)" : "System Default"
        case .zhHans:
            return "简体中文"
        case .en:
            return "English"
        }
    }
}

public final class L10n {
    public static let shared = L10n()

    private static let kLanguagePreferenceKey = "budhold.appLanguage"

    public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.kLanguagePreferenceKey)
        }
    }

    public var isChinese: Bool {
        language.resolvedIsChinese
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.kLanguagePreferenceKey),
           let lang = AppLanguage(rawValue: saved) {
            self.language = lang
        } else {
            self.language = .system
        }
    }

    public static func tr(_ zh: String, _ en: String) -> String {
        shared.isChinese ? zh : en
    }
}
