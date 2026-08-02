import AppKit
import AVFoundation
import SwiftUI

/// Шаги первого запуска. Порядок — по зависимостям: сначала то, без чего
/// приложение вообще не работает, ключ последним, потому что за ним человеку
/// надо уходить на сайт и возвращаться.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case microphone
    case keyboard
    case key
    case done

    var id: Int { rawValue }
}

/// Состояние мастера первого запуска.
///
/// Разрешения нельзя просто спросить один раз: человек уходит в системные
/// настройки, щёлкает там переключатель и возвращается — приложение обязано
/// увидеть это само, без кнопки «я включил». Поэтому опрос по таймеру, пока
/// окно открыто.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome

    @Published private(set) var micStatus: AVAuthorizationStatus =
        AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var accessibilityGranted = HotkeyMonitor.isTrusted
    @Published private(set) var inputMonitoringGranted = HotkeyMonitor.hasInputMonitoring

    @Published var apiKey: String = Settings.shared.apiKey ?? ""
    @Published private(set) var keyState: KeyState = .idle
    @Published var launchAtLogin = LaunchAtLogin.isEnabled {
        didSet {
            guard !isSyncing, launchAtLogin != oldValue else { return }
            launchError = LaunchAtLogin.set(launchAtLogin)
        }
    }
    @Published private(set) var launchError: String?

    /// Закрытие окна — тоже завершение: контроллер слушает этот колбэк.
    var onFinish: (() -> Void)?

    enum KeyState: Equatable {
        case idle
        case checking
        case ok
        case failed(String)
    }

    private var poll: Timer?
    private var isSyncing = false

    // MARK: - Опрос разрешений

    func startPolling() {
        refresh()
        poll?.invalidate()
        // Раз в секунду: человек возвращается из системных настроек и видит
        // зелёную галочку почти сразу, а нагрузки от трёх дешёвых проверок нет.
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    func refresh() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityGranted = HotkeyMonitor.isTrusted
        inputMonitoringGranted = HotkeyMonitor.hasInputMonitoring

        isSyncing = true
        launchAtLogin = LaunchAtLogin.isEnabled
        isSyncing = false
    }

    // MARK: - Микрофон

    var micGranted: Bool { micStatus == .authorized }

    /// Системный запрос показывается один раз за всю жизнь приложения. Если
    /// его уже отклонили, второй раз он не появится — остаётся отправить
    /// человека в системные настройки.
    func requestMicrophone() {
        guard micStatus == .notDetermined else {
            openPrivacyPane("Privacy_Microphone")
            return
        }
        Task { @MainActor in
            _ = await AudioRecorder.requestMicrophoneAccess()
            refresh()
        }
    }

    // MARK: - Клавиатура

    var keyboardGranted: Bool { accessibilityGranted && inputMonitoringGranted }

    /// Системный запрос сам добавляет приложение в нужный список — человеку
    /// остаётся щёлкнуть переключатель, а не искать программу кнопкой «+».
    func requestAccessibility() {
        HotkeyMonitor.requestTrust()
        openPrivacyPane("Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        HotkeyMonitor.requestInputMonitoring()
        openPrivacyPane("Privacy_ListenEvent")
    }

    // MARK: - Ключ

    var keySaved: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func pasteKey() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            keyState = .failed("В буфере нет текста")
            return
        }
        apiKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
        keyState = .idle
    }

    /// Проверка заодно и сохраняет: до этого момента ключ живёт только в поле.
    /// Записывать его в связку на каждое нажатие клавиши незачем.
    func checkKey() async {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        keyState = .checking

        if let error = await Transcriber.validateKey(trimmed) {
            keyState = .failed(error)
            return
        }

        Keychain.writeAPIKey(trimmed)
        keyState = .ok
    }

    /// Сохранение без проверки: человек может пойти дальше и с непроверенным
    /// ключом — если тот окажется битым, приложение скажет об этом при первой
    /// же диктовке, а держать его в мастере ради сетевого запроса незачем.
    func saveKeyQuietly() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Keychain.writeAPIKey(trimmed)
    }

    func openKeyPage() {
        guard let url = URL(string: "https://platform.openai.com/api-keys") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Переходы

    func next() {
        if step == .key { saveKeyQuietly() }

        guard let index = OnboardingStep.allCases.firstIndex(of: step),
              index + 1 < OnboardingStep.allCases.count else {
            finish()
            return
        }
        step = OnboardingStep.allCases[index + 1]
    }

    func back() {
        guard let index = OnboardingStep.allCases.firstIndex(of: step), index > 0 else { return }
        step = OnboardingStep.allCases[index - 1]
    }

    func finish() {
        saveKeyQuietly()
        stopPolling()
        Settings.shared.onboardingCompleted = true
        Log.write("Онбординг завершён. Микрофон: \(micGranted) "
                  + "| универсальный доступ: \(accessibilityGranted) "
                  + "| мониторинг ввода: \(inputMonitoringGranted) "
                  + "| ключ: \(keySaved)")
        onFinish?()
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
