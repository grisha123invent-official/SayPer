import AppKit
import SwiftUI

/// Модель окна настроек: пишет значения сразу в Settings/Keychain.
final class SettingsModel: ObservableObject {
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

/// Настройки в две колонки: окно широкое и целиком помещается на экране.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    private let languages: [(String, String)] = [
        ("", "Автоопределение"),
        ("ru", "Русский"),
        ("en", "English"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fr", "Français")
    ]

    var body: some View {
        // ScrollView — страховка: если системный шрифт крупнее обычного,
        // содержимое не обрежется, а прокрутится.
        ScrollView {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 16) {
                    openAI
                    hotkey
                    Spacer(minLength: 0)
                }
                VStack(spacing: 16) {
                    insertion
                    quality
                    system
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
        .scrollContentBackground(.hidden)
        .onAppear { model.refreshPermissions() }
    }

    /// Секция-карточка с заголовком.
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 9) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text(title).font(.headline)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Колонка слева

    private var openAI: some View {
        card("OpenAI") {
            HStack(spacing: 8) {
                SecureField("API-ключ (sk-…)", text: $model.apiKey)
                    .textFieldStyle(.roundedBorder)
                Button("Вставить") { model.pasteAPIKey() }
            }

            HStack(spacing: 8) {
                Button("Проверить ключ") {
                    Task { await model.checkAPIKey() }
                }
                .disabled(model.apiKey.isEmpty || model.isCheckingKey)

                if model.isCheckingKey {
                    ProgressView().controlSize(.small)
                }
                if let result = model.keyCheckResult {
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(result.isOK ? .green : .orange)
                }
                Spacer()
            }

            Picker("Модель", selection: $model.model) {
                ForEach(TranscriptionModel.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            Picker("Язык речи", selection: $model.language) {
                ForEach(languages, id: \.0) { code, title in
                    Text(title).tag(code)
                }
            }

            hint("Ключ хранится в связке ключей macOS, а не в файле настроек.")
        }
    }

    private var hotkey: some View {
        card("Горячая клавиша") {
            HStack {
                Text("Зажимать")
                Spacer()
                HotkeyRecorder(hotkey: $model.hotkey)
                    .frame(width: 190, height: 26)
            }

            HStack {
                Spacer()
                Button("Сбросить на правый ⌥") { model.hotkey = .rightOptionOnly }
                    .buttonStyle(.link)
                    .font(.caption)
            }

            hint("Кликни по полю и зажми любое сочетание — хоть один модификатор, "
                 + "хоть ⌃⌥D. Левые и правые клавиши различаются.")

            hint(model.hotkey.keyCode == nil
                 ? "Держи и говори. Нажатая во время удержания обычная клавиша отменяет запись, "
                   + "так что привычные шорткаты не ломаются."
                 : "Держи и говори. Пока сочетание назначено, эта клавиша не печатается "
                   + "в других приложениях.")

            hint("Esc прерывает и запись, и ожидание расшифровки.")
        }
    }

    // MARK: - Колонка справа

    private var insertion: some View {
        card("Вставка текста") {
            Picker("Способ", selection: $model.insertMode) {
                ForEach(InsertMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            Toggle("Звуковые сигналы", isOn: $model.playSounds)
            Toggle("Показывать индикатор записи", isOn: $model.showIndicator)
        }
    }

    private var quality: some View {
        card("Качество") {
            Toggle("Причёсывать текст через gpt-4o-mini", isOn: $model.cleanup)
            hint("Расставит пунктуацию и уберёт слова-паразиты. Добавляет ~1 секунду.")

            Text("Словарь: имена и термины через запятую")
                .font(.caption)
            TextEditor(text: $model.vocabulary)
                .frame(height: 44)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var system: some View {
        card("Система и доступ") {
            Toggle("Запускать при входе в систему", isOn: $model.launchAtLogin)
            if let error = model.launchError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: model.accessibilityGranted
                      ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.accessibilityGranted ? .green : .orange)
                Text(model.accessibilityGranted
                     ? "Доступ к клавиатуре выдан"
                     : "Нет доступа к клавиатуре — хоткей не сработает")
                    .font(.caption)
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Открыть настройки доступа") {
                    HotkeyMonitor.requestTrust()
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("Проверить") { model.refreshPermissions() }
                Spacer()
            }
        }
    }
}

/// Обёртка над NSWindow, чтобы окно жило независимо от меню.
final class SettingsWindowController {
    private var window: NSWindow?
    let model = SettingsModel()

    func show() {
        model.refreshPermissions()

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let size = NSSize(width: 820, height: 486)
        let hosting = NSHostingController(rootView: SettingsView(model: model))

        // Стеклянная подложка кладётся в contentView окна — иначе окно
        // остаётся просто прозрачным и фон «пропадает».
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = .underWindowBackground
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]

        hosting.view.frame = glass.bounds
        hosting.view.autoresizingMask = [.width, .height]
        glass.addSubview(hosting.view)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = glass
        window.title = "Надиктовка — настройки"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
