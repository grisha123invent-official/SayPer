import AppKit
import SwiftUI

/// Модель окна настроек: пишет значения сразу в Settings/Keychain.
final class SettingsModel: ObservableObject {
    /// Открытый раздел. Меню статус-бара умеет открывать окно сразу на нужном.
    @Published var section: SettingsSection = .general

    @Published var apiKey: String {
        didSet { Keychain.writeAPIKey(apiKey) }
    }
    @Published var hotkey: HotkeyBinding {
        didSet {
            guard hotkey != oldValue else { return }
            Settings.shared.hotkey = hotkey
            onHotkeyChange?()
        }
    }
    @Published var model: TranscriptionModel {
        didSet { Settings.shared.model = model }
    }
    @Published var language: String {
        didSet { Settings.shared.language = language }
    }
    @Published var insertMode: InsertMode {
        didSet { Settings.shared.insertMode = insertMode }
    }
    @Published var playSounds: Bool {
        didSet { Settings.shared.playSounds = playSounds }
    }
    @Published var showIndicator: Bool {
        didSet { Settings.shared.showIndicator = showIndicator }
    }
    @Published var vocabulary: String {
        didSet { Settings.shared.vocabulary = vocabulary }
    }
    @Published var cleanup: Bool {
        didSet { Settings.shared.cleanup = cleanup }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncing else { return }
            launchError = LaunchAtLogin.set(launchAtLogin)
        }
    }
    @Published var launchError: String?

    @Published var accessibilityGranted: Bool = HotkeyMonitor.isTrusted

    /// Меняется, когда акцент или тему поменяли не из «Кастомизации» —
    /// например кнопкой помощника. Сама карточка тогда не участвует,
    /// а перерисовать окно надо: акцент читается на месте отрисовки.
    @Published private(set) var appearanceStamp = 0

    func appearanceChanged() { appearanceStamp += 1 }

    struct KeyCheck {
        let isOK: Bool
        let message: String
    }
    @Published var keyCheckResult: KeyCheck?
    @Published var isCheckingKey = false

    var onHotkeyChange: (() -> Void)?

    /// Чтобы обновление состояния из системы не запускало didSet повторно.
    private var isSyncing = false

    init() {
        let settings = Settings.shared
        apiKey = settings.apiKey ?? ""
        hotkey = settings.hotkey
        model = settings.model
        language = settings.language
        insertMode = settings.insertMode
        playSounds = settings.playSounds
        showIndicator = settings.showIndicator
        vocabulary = settings.vocabulary
        cleanup = settings.cleanup
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// Запасной путь на случай, если ⌘V в поле почему-то не сработал.
    func pasteAPIKey() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            keyCheckResult = KeyCheck(isOK: false, message: "В буфере нет текста")
            return
        }
        apiKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
        keyCheckResult = nil
    }

    @MainActor
    func checkAPIKey() async {
        isCheckingKey = true
        keyCheckResult = nil
        defer { isCheckingKey = false }

        if let error = await Transcriber.validateKey(apiKey) {
            keyCheckResult = KeyCheck(isOK: false, message: error)
        } else {
            keyCheckResult = KeyCheck(isOK: true, message: "Ключ рабочий")
        }
    }

    func refreshPermissions() {
        accessibilityGranted = HotkeyMonitor.isTrusted

        isSyncing = true
        launchAtLogin = LaunchAtLogin.isEnabled
        isSyncing = false
    }
}
