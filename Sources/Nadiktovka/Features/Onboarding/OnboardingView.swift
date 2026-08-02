import AppKit
import AVFoundation
import SwiftUI

/// Мастер первого запуска.
///
/// До него человека встречали три системных алерта подряд без единого слова
/// о том, зачем они. Мастер объясняет каждый шаг и, главное, сам видит, когда
/// разрешение выдано, — возвращаться и нажимать «я включил» не надо.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, Palette.spaceMd)

            Spacer(minLength: Palette.spaceLg)

            // Панель обнимает содержимое, а не растягивается на всё окно:
            // у шагов разный объём текста, и растянутая панель на коротком
            // шаге превращалась в пустую коробку в пол-экрана.
            panel

            Spacer(minLength: Palette.spaceLg)

            footer
        }
        .padding(.horizontal, Palette.spaceXl)
        .padding(.bottom, Palette.spaceXl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.28, extraBounce: 0), value: model.step)
    }

    // MARK: - Прогресс

    /// Точки, а не «шаг 2 из 5»: цифры человек начинает считать, а точки
    /// показывают ровно то, что нужно, — что путь короткий и конец близко.
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { item in
                Capsule(style: .continuous)
                    .fill(item == model.step ? Palette.accent : Color.primary.opacity(0.16))
                    .frame(width: item == model.step ? 22 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Шаг \(model.step.rawValue + 1) из \(OnboardingStep.allCases.count)")
    }

    // MARK: - Содержимое шага

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.step {
            case .welcome: WelcomeStep()
            case .microphone: MicrophoneStep(model: model)
            case .keyboard: KeyboardStep(model: model)
            case .key: KeyStep(model: model)
            case .done: DoneStep(model: model)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .padding(.horizontal, Palette.spaceXl)
        .padding(.vertical, Palette.spaceXl)
        .background(
            RoundedRectangle(cornerRadius: Palette.radiusPanel, style: .continuous)
                .fill(Palette.surfacePanel)
        )
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: Palette.radiusPanel, style: .continuous)
        )
    }

    // MARK: - Кнопки

    private var footer: some View {
        HStack(spacing: Palette.spaceXs) {
            if model.step != .welcome {
                CapsuleButton("Назад") { model.back() }
            }

            Spacer(minLength: Palette.spaceSm)

            // Пока разрешение не выдано, главной кнопкой становится сам запрос,
            // а «Пропустить» уходит в тихую текстовую. Так человек не проскочит
            // шаг случайно, но и не окажется в тупике, если выдавать не хочет.
            if let action = pendingAction {
                Button("Пропустить") { model.next() }
                    .buttonStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Palette.spaceXs)

                CapsuleButton(action.title, kind: .accent, action: action.run)
            } else {
                CapsuleButton(model.step == .done ? "Начать" : "Далее", kind: .accent) {
                    model.next()
                }
            }
        }
    }

    private struct PendingAction {
        let title: String
        let run: () -> Void
    }

    /// Что осталось сделать на текущем шаге. `nil` — шаг закрыт, можно дальше.
    private var pendingAction: PendingAction? {
        switch model.step {
        case .microphone where !model.micGranted:
            return PendingAction(
                title: model.micStatus == .notDetermined ? "Разрешить микрофон" : "Открыть настройки",
                run: model.requestMicrophone
            )
        case .keyboard where !model.keyboardGranted:
            return PendingAction(
                title: "Открыть настройки",
                run: model.accessibilityGranted ? model.requestInputMonitoring : model.requestAccessibility
            )
        case .key where !model.keySaved:
            return PendingAction(title: "Взять ключ", run: model.openKeyPage)
        default:
            return nil
        }
    }
}

// MARK: - Шаг 1. Приветствие

private struct WelcomeStep: View {
    var body: some View {
        StepBody(
            title: "SayPer",
            subtitle: "Зажми клавишу, скажи вслух — текст появится там, где стоит курсор."
        ) {
            VStack(alignment: .leading, spacing: Palette.spaceSm) {
                Bullet("Микрофон", "Записать голос.")
                Bullet("Доступ к клавиатуре", "Увидеть горячую клавишу и вставить текст.")
                Bullet("Ключ OpenAI", "Расшифровать записанное.")
            }

            // Про деньги честно и сразу, а не когда придёт счёт. Ставка whisper-1
            // на август 2026 — $0.006 за минуту звука.
            Hint("Расшифровка идёт через OpenAI и стоит денег: около $0.006 за минуту речи — "
                 + "примерно 36 центов за час диктовки. Расходы приложение считает само, "
                 + "они видны в настройках.")
        }
    }

    private struct Bullet: View {
        let title: String
        let text: String

        init(_ title: String, _ text: String) {
            self.title = title
            self.text = text
        }

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: Palette.spaceSm) {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 5, height: 5)
                    .alignmentGuide(.firstTextBaseline) { _ in 4 }
                Text(title)
                    .font(.body.weight(.medium))
                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Шаг 2. Микрофон

private struct MicrophoneStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        StepBody(
            title: "Микрофон",
            subtitle: "Без него записывать нечего. Звук уходит в OpenAI только на время "
                    + "расшифровки и на диске не остаётся."
        ) {
            StatusLine(granted: model.micGranted, text: statusText)

            if model.micStatus == .denied {
                Hint("Доступ был отклонён раньше, поэтому системное окно больше не появится. "
                     + "Включи «SayPer» в разделе «Конфиденциальность и безопасность» → «Микрофон».")
            }
        }
    }

    private var statusText: String {
        switch model.micStatus {
        case .authorized: return "Доступ выдан"
        case .denied: return "Доступ запрещён"
        case .restricted: return "Доступ ограничен системой"
        default: return "Доступа пока нет"
        }
    }
}

// MARK: - Шаг 3. Клавиатура

private struct KeyboardStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        StepBody(
            title: "Доступ к клавиатуре",
            subtitle: "Два разных разрешения, и нужны оба. macOS не даёт выдать их из "
                    + "приложения — переключатели живут в системных настройках."
        ) {
            VStack(alignment: .leading, spacing: Palette.spaceSm) {
                AccessRow(
                    title: "Универсальный доступ",
                    purpose: "Вставлять текст в чужие окна",
                    granted: model.accessibilityGranted,
                    action: model.requestAccessibility
                )
                AccessRow(
                    title: "Мониторинг ввода",
                    purpose: "Видеть горячую клавишу, пока работаешь в другой программе",
                    granted: model.inputMonitoringGranted,
                    action: model.requestInputMonitoring
                )
            }

            Hint("Перезапускать приложение не надо: как только переключатель включён, "
                 + "галочка здесь загорится сама.")
        }
    }

    private struct AccessRow: View {
        let title: String
        let purpose: String
        let granted: Bool
        let action: () -> Void

        var body: some View {
            HStack(spacing: Palette.spaceSm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body)
                    Text(purpose)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Palette.spaceSm)

                if granted {
                    StatusBadge(granted: true, text: "Выдан")
                } else {
                    CapsuleButton("Открыть", action: action)
                }
            }
            .frame(minHeight: Palette.rowHeightWithSubtitle)
        }
    }
}

// MARK: - Шаг 4. Ключ

private struct KeyStep: View {
    @ObservedObject var model: OnboardingModel

    @FocusState private var fieldFocused: Bool

    var body: some View {
        StepBody(
            title: "Ключ OpenAI",
            subtitle: "Свой ключ: платишь напрямую OpenAI, посредников между тобой "
                    + "и расшифровкой нет."
        ) {
            HStack(spacing: 6) {
                SecureField("sk-…", text: $model.apiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13).monospaced())
                    .focused($fieldFocused)

                Button {
                    model.pasteKey()
                } label: {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Вставить из буфера")
            }
            .padding(.leading, Palette.spaceXs)
            .padding(.trailing, 3)
            .frame(height: Palette.capsuleHeight)
            .fieldChrome(isFocused: fieldFocused)

            HStack(spacing: Palette.spaceSm) {
                CapsuleButton("Проверить", isLoading: model.keyState == .checking) {
                    Task { await model.checkKey() }
                }
                .disabled(!model.keySaved)

                switch model.keyState {
                case .ok:
                    StatusBadge(granted: true, text: "Ключ рабочий")
                case .failed(let message):
                    StatusBadge(granted: false, text: message)
                default:
                    EmptyView()
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: Palette.rowHeight)

            Hint("Ключ создаётся на platform.openai.com в разделе API keys и показывается "
                 + "один раз — скопируй сразу. Хранится он на этом маке, в связке ключей.")
        }
    }
}

// MARK: - Шаг 5. Готово

private struct DoneStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        StepBody(
            title: "Готово",
            subtitle: "Зажми сочетание, говори, отпусти — текст встанет в поле, "
                    + "где стоит курсор."
        ) {
            HStack(spacing: Palette.spaceSm) {
                Text(Settings.shared.hotkey.displayString)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .padding(.horizontal, Palette.spaceMd)
                    .padding(.vertical, Palette.spaceXs)
                    .background(
                        RoundedRectangle(cornerRadius: Palette.radiusTile, style: .continuous)
                            .fill(Palette.surfaceTile)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Palette.radiusTile, style: .continuous)
                            .strokeBorder(Palette.rimCard, lineWidth: 1)
                    )

                Text("Сочетание меняется в настройках, там же — режим «нажал-нажал», "
                     + "если держать клавишу неудобно.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SwitchToggle("Запускать при входе в систему", isOn: $model.launchAtLogin)

            if let error = model.launchError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Значок в строке меню — единственный вход в приложение: окна у него
            // нет, и без этой строчки человек будет искать его в Dock.
            Hint("Приложение живёт в строке меню, значком микрофона. Клик по нему — "
                 + "история, расходы и настройки.")

            if !allSet {
                Hint(missing)
            }
        }
    }

    private var allSet: Bool { model.micGranted && model.keyboardGranted && model.keySaved }

    private var missing: String {
        var parts: [String] = []
        if !model.micGranted { parts.append("микрофон") }
        if !model.keyboardGranted { parts.append("доступ к клавиатуре") }
        if !model.keySaved { parts.append("ключ") }
        return "Пропущено: \(parts.joined(separator: ", ")). Без этого диктовка не заработает — "
             + "доделать можно в настройках, раздел «Ключ и расходы»."
    }
}

// MARK: - Общие части шага

/// Заголовок, подзаголовок и содержимое — одинаковая рамка у всех шагов,
/// чтобы текст не прыгал по вертикали при переходе.
private struct StepBody<Content: View>: View {
    private let title: String
    private let subtitle: String
    private let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Palette.spaceMd) {
            VStack(alignment: .leading, spacing: Palette.space2xs) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Строка состояния разрешения.
private struct StatusLine: View {
    let granted: Bool
    let text: String

    var body: some View {
        StatusBadge(granted: granted, text: text)
            .frame(minHeight: Palette.rowHeight)
    }
}

/// Значок состояния: цвет здесь не единственный носитель смысла — форма
/// глифа и текст говорят то же самое.
private struct StatusBadge: View {
    let granted: Bool
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(granted ? Palette.success : Palette.warning)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
