import AppKit
import SwiftUI

/// Раздел «О программе»: кто сделал, как написать, что показать при разборе.
///
/// Последний по счёту и самый редкий: сюда приходят один раз — когда что-то
/// не работает или хочется предложить функцию.
struct SettingsSectionAbout: View {
    /// Нужен помощнику: предложенные им кнопки меняют настройки через модель,
    /// иначе переключатели в соседних разделах остались бы на старом значении.
    @ObservedObject var model: SettingsModel

    @State private var verboseLog = Settings.shared.verboseLog
    @State private var logSize = About.logSize()
    @State private var copied = false
    @StateObject private var chat: HelpChat

    /// Готовый `chat` подставляет только стенд проверки интерфейса — в самом
    /// приложении помощник заводится здесь и живёт вместе с разделом.
    @MainActor
    init(model: SettingsModel, chat: HelpChat? = nil) {
        self.model = model
        let object = chat ?? HelpChat()
        _chat = StateObject(wrappedValue: object)
    }

    @State private var question = ""
    @FocusState private var questionFocused: Bool
    /// Уже нажатые кнопки — по паре «реплика + действие». Именно по паре:
    /// то же действие в следующем ответе должно предлагаться заново.
    @State private var applied: Set<String> = []

    var body: some View {
        SectionScaffold {
            heading
            CardDivider(inset: 0)
            contacts
            CardDivider(inset: 0)
            helper
            CardDivider(inset: 0)
            diagnostics
        }
    }

    // MARK: - Помощник

    /// Спросить про приложение словами. Отвечает по зашитой справке
    /// и по текущим настройкам, на ключе самого пользователя — своего
    /// сервера у приложения нет.
    private var helper: some View {
        GlassCard("Спросить про приложение") {
            if !chat.hasKey {
                Hint("Нужен ключ OpenAI — тот же, что и для расшифровки. "
                     + "Задаётся в разделе «Ключ и расходы».")
            }

            if chat.messages.isEmpty {
                starters
            } else {
                thread
            }

            if let failure = chat.failure {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.warning)
                    Text(failure)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            input
            footnote
        }
    }

    /// Лента реплик. Своя прокрутка, а не рост карточки вниз: раздел
    /// не должен уезжать от кнопок диагностики по мере разговора.
    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Palette.spaceXs) {
                    ForEach(chat.messages) { bubble($0) }
                    if chat.isThinking { thinking }
                    // Якорь для автопрокрутки: новая реплика должна быть
                    // видна сразу, без ручного скролла.
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(Palette.spaceSm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .background(
                RoundedRectangle(cornerRadius: Palette.radiusCard, style: .continuous)
                    .fill(Palette.surfaceTile)
            )
            .onChange(of: chat.messages.count) { _, _ in scrollDown(proxy) }
            .onChange(of: chat.isThinking) { _, _ in scrollDown(proxy) }
        }
    }

    private static let bottomAnchor = "конец переписки"

    private func scrollDown(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    private func bubble(_ message: HelpChat.Message) -> some View {
        VStack(alignment: .leading, spacing: Palette.spaceXs) {
            HStack(spacing: 0) {
                if message.role == .user { Spacer(minLength: 48) }
                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Palette.spaceSm)
                    .padding(.vertical, Palette.spaceXs)
                    .background(
                        RoundedRectangle(cornerRadius: Palette.radiusTile, style: .continuous)
                            .fill(message.role == .user
                                  ? AnyShapeStyle(Palette.accent.opacity(0.22))
                                  : AnyShapeStyle(.background.secondary))
                    )
                if message.role == .assistant { Spacer(minLength: 48) }
            }

            ForEach(message.actions, id: \.self) { id in
                if let action = HelpAction.named(id) {
                    offer(action, in: message)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Предложенное действие: сначала объяснение, что произойдёт, потом кнопка.
    ///
    /// Порядок именно такой. Кнопка с одной подписью — это «нажми и узнаешь»;
    /// человек должен понимать, что меняется, до нажатия, а не после.
    private func offer(_ action: HelpAction, in message: HelpChat.Message) -> some View {
        let key = "\(message.id)|\(action.id)"
        let isDone = applied.contains(key)

        return VStack(alignment: .leading, spacing: Palette.spaceXs) {
            Text(action.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isDone {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.accent)
                    Text(action.done)
                        .font(.subheadline)
                }
            } else {
                CapsuleButton(action.title, kind: .accent) {
                    action.apply(model)
                    applied.insert(key)
                    // Своё же состояние раздела могло поменяться той же кнопкой.
                    verboseLog = Settings.shared.verboseLog
                }
            }
        }
        .padding(Palette.spaceSm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Palette.radiusTile, style: .continuous)
                .fill(Palette.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Palette.radiusTile, style: .continuous)
                .stroke(Palette.accent.opacity(0.35), lineWidth: 1)
        )
        .padding(.trailing, 48)
    }

    private var thinking: some View {
        HStack(spacing: Palette.space2xs) {
            ProgressView().controlSize(.small)
            Text("Думает…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Palette.spaceXs)
    }

    /// С чего начать, когда разговора ещё нет. Пустое поле ввода в настройках
    /// вопросов не вызывает — а эти три показывают, о чём вообще можно спросить.
    private var starters: some View {
        VStack(alignment: .leading, spacing: Palette.spaceXs) {
            Hint("Спроси про сочетание клавиш, микрофон, разрешения — помощник "
                 + "знает и приложение, и то, что настроено у тебя. Где дело "
                 + "решается настройкой, предложит кнопку — с объяснением, "
                 + "что она сделает. Нажимаешь сам.")
            FlowRow(spacing: Palette.spaceXs) {
                ForEach(Self.starterQuestions, id: \.self) { text in
                    CapsuleButton(text) { chat.ask(text) }
                        .disabled(!chat.hasKey)
                }
            }
        }
    }

    private static let starterQuestions = [
        "Какая у меня клавиша?",
        "Почему прерывается музыка?",
        "Текст не вставляется"
    ]

    private var input: some View {
        HStack(spacing: Palette.spaceXs) {
            TextField(chat.isFull ? "Разговор окончен" : "Спроси о чём угодно",
                      text: $question)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($questionFocused)
                .onSubmit(sendQuestion)
                // Esc отпускает поле: щелчок мимо в этом окне фокус
                // не снимает, а других способов выйти из него нет.
                .onExitCommand { questionFocused = false }
                .padding(.horizontal, Palette.spaceSm)
                .frame(height: Palette.capsuleHeight + 6)
                // Ни обводки, ни фокусного кольца — намеренно. Это строка
                // чата, а не поле формы: рамка вокруг неё лезла в глаза
                // и в покое, и при наборе, а места, куда писать, здесь
                // всё равно одно.
                .background(
                    Capsule(style: .continuous).fill(Palette.surfaceTile)
                )
                .disabled(chat.isFull)

            CapsuleButton("Спросить", kind: .accent, isLoading: chat.isThinking,
                          action: sendQuestion)
                .disabled(!chat.hasKey || chat.isFull
                          || question.trimmingCharacters(in: .whitespaces).isEmpty)

            if !chat.messages.isEmpty {
                CapsuleButton("Заново") {
                    chat.reset()
                    question = ""
                }
            }
        }
    }

    @ViewBuilder
    private var footnote: some View {
        if chat.isFull {
            Hint("Разговор дошёл до десяти вопросов — дальше помощник начнёт "
                 + "путаться в собственных ответах. Нажми «Заново» и спроси "
                 + "с чистого листа или напиши разработчику в телеграм.")
        } else if chat.remaining <= 3 {
            Hint("Вопросов в этом разговоре осталось: \(chat.remaining).")
        } else if chat.messages.isEmpty {
            // Про деньги и про доступность — сразу, а не когда придёт счёт
            // или когда запрос молча не пройдёт.
            Hint("Ответы идут через OpenAI по твоему ключу — каждый вопрос стоит "
                 + "доли цента. Из России OpenAI недоступен без VPN, там помощник "
                 + "работать не будет.")
        }
    }

    private func sendQuestion() {
        let text = question
        question = ""
        chat.ask(text)
    }

    // MARK: - Шапка

    private var heading: some View {
        GlassCard("Приложение") {
            HStack(spacing: Palette.spaceMd) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SayPer")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Версия \(AppInfo.versionLine)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Диктовка голосом для macOS")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                // Готовая справка о системе: в обращении её всё равно спросят,
                // а человек будет искать версию macOS по меню.
                CapsuleButton(copied ? "Скопировано" : "Скопировать сведения",
                              symbol: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(About.systemSummary(), forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
            }
        }
    }

    // MARK: - Связь

    private var contacts: some View {
        GlassCard("Связь") {
            SettingRow(
                "Написать разработчику",
                subtitle: "Быстрый вопрос, что-то не работает, просто сказать спасибо"
            ) {
                CapsuleButton("Телеграм", symbol: "paperplane") { About.openTelegram() }
            }

            SettingRow(
                "Сообщить об ошибке",
                subtitle: "Письмо откроется с уже вписанной версией и сведениями о системе"
            ) {
                CapsuleButton("Написать", symbol: "envelope") { About.mailBugReport() }
            }

            SettingRow(
                "Предложить функцию",
                subtitle: "Чего не хватает и в какой момент это понадобилось"
            ) {
                CapsuleButton("Написать", symbol: "lightbulb") { About.mailFeature() }
            }
        }
    }

    // MARK: - Диагностика

    private var diagnostics: some View {
        GlassCard("Диагностика") {
            SwitchToggle(
                "Подробный журнал",
                subtitle: "Записывает всё, что происходит: устройства, форматы, "
                        + "сетевые попытки, решения приглушения. Включают, чтобы "
                        + "поймать плавающую ошибку и отдать файл разработчику",
                isOn: $verboseLog
            )
            .onChange(of: verboseLog) { _, newValue in
                Settings.shared.verboseLog = newValue
                Log.write(newValue ? "Подробный журнал включён" : "Подробный журнал выключен")
                logSize = About.logSize()
            }

            SettingRow("Журнал", subtitle: logSize) {
                HStack(spacing: Palette.spaceXs) {
                    CapsuleButton("Показать") {
                        NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
                    }
                    CapsuleButton("Сохранить копию…") { About.saveLogCopy() }
                }
            }

            SettingRow("Состояние", subtitle: "Доступы, микрофон, ключ и текущий хоткей") {
                CapsuleButton("Показать") {
                    NotificationCenter.default.post(name: .showDiagnostics, object: nil)
                }
            }
        }
        .onAppear { logSize = About.logSize() }
    }
}

/// Действия раздела «О программе». Вынесены из вида: он про раскладку,
/// а не про почтовые ссылки и файлы.
enum About {
    /// Ник в телеграме. Меняется здесь и больше нигде.
    static let telegram = "grisha123invent"
    static let email = "grig.perev@gmail.com"

    static func systemSummary() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return """
        SayPer \(AppInfo.versionLine)
        macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        \(hardwareModel())
        """
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }

    static func logSize() -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: Log.fileURL.path)
        let bytes = (attributes?[.size] as? Int) ?? 0
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(Log.fileURL.path) · \(formatter.string(fromByteCount: Int64(bytes)))"
    }

    static func openTelegram() {
        guard let url = URL(string: "https://t.me/\(telegram)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func mailBugReport() {
        // Сведения о системе подставляются заранее: без них разбор начинается
        // с переписки «а какая у вас версия».
        mail(subject: "SayPer: ошибка",
             body: """


             ——— не удаляй, это нужно для разбора ———
             \(systemSummary())
             """)
    }

    static func mailFeature() {
        mail(subject: "SayPer: предложение",
             body: """
             Чего не хватает:

             В какой момент это понадобилось:

             ——— \(AppInfo.versionLine) ———
             """)
    }

    private static func mail(subject: String, body: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Копия журнала туда, где её удобно приложить к письму.
    static func saveLogCopy() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SayPer-журнал.txt"
        panel.canCreateDirectories = true
        panel.message = "Куда сохранить копию журнала"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let target = panel.url else { return }
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: Log.fileURL, to: target)
    }
}
