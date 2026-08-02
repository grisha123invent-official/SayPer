import Foundation

extension Settings {
    /// Прошёл ли человек первый запуск: ключ `onboarding.completed`.
    ///
    /// Ставится и когда мастер дошёл до конца, и когда его закрыли на середине.
    /// Второй раз лезть с приветствием нельзя: тот, кто закрыл окно, сказал
    /// этим «не надо», а всё, что мастер выдаёт, доступно и из настроек.
    var onboardingCompleted: Bool {
        get { flag("onboarding.completed") }
        set { set(newValue, forKey: "onboarding.completed") }
    }
}
