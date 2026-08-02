import Foundation

/// Сведения о самой сборке.
///
/// Нужны в диагностике: без номера версии любая жалоба превращается
/// в гадание, какая у человека сборка и починено ли там уже то, о чём он пишет.
enum AppInfo {
    /// Показывается человеку: `1.0-beta.1`.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Счётчик сборок — растёт с каждым выпуском.
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    static var versionLine: String { "\(version) (сборка \(build))" }
}
