import SwiftUI

/// Раздел «Диктовка»: весь путь от нажатия клавиши до текста в поле.
///
/// Прежде это были два раздела — «Запись» и «Текст». Настраивают они одно
/// и то же действие, просто разные его стадии, и переключаться между ними
/// приходилось посреди одной задачи. Секции внутри идут по ходу дела:
/// чем запускаю → что вижу, пока говорю → как распознаётся → куда попадает.
struct SettingsSectionGeneral: View {
    @ObservedObject var model: SettingsModel

    @FocusState private var vocabularyFocused: Bool

    @State private var duckMode = Settings.shared.duckMode
    @State private var duckLevel = Settings.shared.duckLevel
    @State private var micChoice = MicrophoneChoice(Settings.shared.microphoneMode)
    @State private var micDevices = AudioDevices.inputs()
    @State private var micExplained = AudioDevices.explain(Settings.shared.microphoneMode)

    private let languages: [(String, String)] = [
        ("", "Автоопределение"),
        ("ru", "Русский"),
        ("en", "English"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fr", "Français")
    ]

    var body: some View {
        SectionScaffold {
            activation
            microphone
            duringRecording
            transcription
            insertion
        }
    }

    // MARK: - Чем запускается

    /// Сочетание и режим — одна тема: чем запускается запись.
    private var activation: some View {
        GlassCard("Активация") {
            SettingRow(
                "Сочетание",
                subtitle: "Кликни по полю и зажми клавиши. Левые и правые различаются"
            ) {
                // Сброс живёт внутри поля, у правого края с отступом 6
                // (`components.md` §2), и рисует его сам рекордер. Отдельной
                // кнопкой рядом он сдвигал поле на 28pt в момент появления —
                // то есть ровно тогда, когда человек целится в клавиши.
                HotkeyRecorder(hotkey: $model.hotkey)
                    .frame(width: 190, height: 28)
            }

            RecordingModeRow()
        }
    }

    // MARK: - Откуда слушать

    private var microphone: some View {
        GlassCard("Микрофон") {
            SettingRow("Устройство", subtitle: micExplained) {
                Picker("", selection: $micChoice) {
                    Text("Умно").tag(MicrophoneChoice.smart)
                    Text("Встроенный").tag(MicrophoneChoice.builtIn)
                    Text("Как в системе").tag(MicrophoneChoice.systemDefault)
                    Divider()
                    ForEach(micDevices) { device in
                        Text(device.name).tag(MicrophoneChoice.specific(device.uid))
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .onChange(of: micChoice) { _, choice in
                    Settings.shared.microphoneMode = choice.mode
                    micExplained = AudioDevices.explain(choice.mode)
                }
            }

            // Ради чего вся настройка: беспроводные наушники, подключённые
            // и к маку, и к телефону, числятся микрофоном по умолчанию, даже
            // когда играет телефон. Открыв на них вход, приложение отбирает
            // их у телефона и обрывает музыку.
            Hint("«Умно» не трогает беспроводные наушники, пока ты слушаешь через них "
                 + "не мак, а телефон: в этом случае запись идёт со встроенного микрофона. "
                 + "Как только звук пойдёт с мака, диктовка снова пойдёт через наушники.")
        }
        // Список устройств меняется, пока окно открыто: наушники подключают
        // и отключают. Обновляем при каждом показе раздела.
        .onAppear {
            micDevices = AudioDevices.inputs()
            micExplained = AudioDevices.explain(Settings.shared.microphoneMode)
        }
    }

    // MARK: - Пока говоришь

    private var duringRecording: some View {
        GlassCard("Во время записи") {
            SwitchToggle("Показывать индикатор", isOn: $model.showIndicator)

            SettingRow(
                "Звук компьютера",
                subtitle: "Музыка и видео лезут в микрофон и портят расшифровку"
            ) {
                SegmentedControl(selection: $duckMode, options: OutputDucker.Mode.allCases,
                                 compact: true) { $0.title }
                    .frame(width: 230)
            }
            .onChange(of: duckMode) { _, newValue in
                Settings.shared.duckMode = newValue
            }

            // Ползунок нужен только в режиме «Убавить»: в остальных
            // уровень ни на что не влияет и только сбивал бы с толку.
            if duckMode == .dim {
                SettingRow("Насколько убавлять") {
                    HStack(spacing: Palette.spaceSm) {
                        Slider(value: $duckLevel, in: 0.05...0.9)
                            .frame(width: 170)
                            // Системный синий здесь спорил с выбранным акцентом:
                            // единственный элемент окна, живущий своим цветом.
                            .tint(Palette.accent)
                        Text("\(Int((duckLevel * 100).rounded()))%")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .onChange(of: duckLevel) { _, newValue in
                    Settings.shared.duckLevel = newValue
                }
            }
        }
    }

    // MARK: - Как распознаётся

    private var transcription: some View {
        GlassCard("Расшифровка") {
            SettingRow("Модель") {
                Picker("", selection: $model.model) {
                    ForEach(TranscriptionModel.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 260)
            }

            SettingRow("Язык речи") {
                Picker("", selection: $model.language) {
                    ForEach(languages, id: \.0) { code, title in
                        Text(title).tag(code)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            vocabulary

            SwitchToggle(
                "Причёсывать текст",
                subtitle: "Пунктуация и слова-паразиты, +1 секунда · gpt-4o-mini",
                isOn: $model.cleanup
            )
        }
    }

    /// Подпись-заголовок над редактором убрана: что писать, объясняет плейсхолдер
    /// внутри поля — там это видно ровно в тот момент, когда нужно (`ia.md` §3).
    private var vocabulary: some View {
        HStack(alignment: .top, spacing: Palette.spaceSm) {
            Text("Словарь")
                .font(.body)
                .frame(height: Palette.rowHeight, alignment: .center)

            Spacer(minLength: Palette.spaceSm)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.vocabulary)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 5)
                    .focused($vocabularyFocused)

                if model.vocabulary.isEmpty {
                    Text("имена и термины через запятую")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 330, height: 62)
            // Заливка, обводка и фокусное кольцо — одним кирпичиком:
            // `.plain`-редактор системного кольца не рисует (`tokens.md` §11).
            .fieldChrome(isFocused: vocabularyFocused)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Куда попадает

    private var insertion: some View {
        GlassCard("Вставка") {
            SettingRow("Способ") {
                Picker("", selection: $model.insertMode) {
                    ForEach(InsertMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 300)
            }
        }
    }
}

/// Обёртка над `MicrophoneMode` для `Picker`: ему нужен Hashable-тег,
/// а разбирать ассоциированное значение в каждой ветке меню неудобно.
enum MicrophoneChoice: Hashable {
    case smart
    case builtIn
    case systemDefault
    case specific(String)

    init(_ mode: MicrophoneMode) {
        switch mode {
        case .smart: self = .smart
        case .builtIn: self = .builtIn
        case .systemDefault: self = .systemDefault
        case .specific(let uid): self = .specific(uid)
        }
    }

    var mode: MicrophoneMode {
        switch self {
        case .smart: return .smart
        case .builtIn: return .builtIn
        case .systemDefault: return .systemDefault
        case .specific(let uid): return .specific(uid)
        }
    }
}
