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

    private let languages: [(String, String)] = [
        ("", "Автоопределение"),
        ("ru", "Русский"),
        ("en", "English"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fr", "Français")
    ]

    @State private var showsMore = false
    @State private var routing = Settings.shared.micRouting
    @State private var routes = Settings.shared.hotkeyRoutes
    @State private var devices = AudioDevices.inputs()

    var body: some View {
        SectionScaffold {
            activation
            CardDivider(inset: 0)
            recordingAndText
            CardDivider(inset: 0)
            more
        }
    }

    // MARK: - Чем запускается

    /// Сочетание и режим — одна тема: чем запускается запись.
    private var activation: some View {
        GlassCard("Активация") {
            SettingRow("Сочетание") {
                // Сброс живёт внутри поля, у правого края с отступом 6
                // (`components.md` §2), и рисует его сам рекордер. Отдельной
                // кнопкой рядом он сдвигал поле на 28pt в момент появления —
                // то есть ровно тогда, когда человек целится в клавиши.
                HotkeyRecorder(hotkey: $model.hotkey)
                    .frame(width: 190, height: 28)
            }

            RecordingModeRow()

            SettingRow("Выбор микрофона", subtitle: routing.summary) {
                SegmentedControl(selection: $routing, options: MicRouting.allCases,
                                 compact: true) { $0.title }
                    .frame(width: 240)
            }
            .onChange(of: routing) { _, newValue in
                Settings.shared.micRouting = newValue
                model.onHotkeyChange?()
            }

            if routing == .perHotkey {
                hotkeyRoutes
            }
        }
        .onAppear { devices = AudioDevices.inputs() }
    }

    /// Таблица «сочетание → микрофон». Первая строка играет роль основного
    /// сочетания: без неё записывать нечем, поэтому последнюю удалить нельзя.
    private var hotkeyRoutes: some View {
        VStack(alignment: .leading, spacing: Palette.spaceXs) {
            ForEach($routes) { $route in
                HStack(spacing: Palette.spaceXs) {
                    HotkeyRecorder(hotkey: Binding(
                        get: { route.binding },
                        set: { route.binding = $0; saveRoutes() }
                    ))
                    .frame(width: 170, height: 28)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Picker("", selection: Binding(
                        get: { route.deviceTag },
                        set: { route.deviceTag = $0; saveRoutes() }
                    )) {
                        ForEach(devices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)

                    Button {
                        routes.removeAll { $0.id == route.id }
                        saveRoutes()
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 13))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(routes.count <= 1)
                    .help("Убрать строку")
                }
            }

            CapsuleButton("Добавить сочетание", symbol: "plus") {
                routes.append(HotkeyRoute(binding: HotkeyBinding(mask: 0, keyCode: nil),
                                          deviceTag: "builtin"))
                saveRoutes()
            }

            Hint("Если одно сочетание входит в другое — ⌃ и ⌃⇧, — короткое ждёт "
                 + "четверть секунды, прежде чем начать: нажать оба модификатора "
                 + "одновременно физически нельзя.")
        }
    }

    private func saveRoutes() {
        Settings.shared.hotkeyRoutes = routes
        model.onHotkeyChange?()
    }

    // MARK: - Запись и текст

    /// То, что трогают. Остальное уехало в «Ещё»: держать четырнадцать строк
    /// на виду значит заставлять человека каждый раз перечитывать весь экран.
    private var recordingAndText: some View {
        GlassCard("Запись и текст") {
            SwitchToggle("Показывать индикатор", isOn: $model.showIndicator)

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
                .frame(width: 260)
            }

            SettingRow("Способ вставки") {
                Picker("", selection: $model.insertMode) {
                    ForEach(InsertMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 260)
            }
        }
    }

    // MARK: - Редкое

    /// Свёрнуто по умолчанию. Раскрытое состояние не запоминается: настроил
    /// раз — и снова с глаз долой, ради этого всё и затевалось.
    private var more: some View {
        GlassCard("Ещё") {
            Button {
                withAnimation(.smooth(duration: 0.22, extraBounce: 0)) { showsMore.toggle() }
            } label: {
                HStack(spacing: Palette.spaceXs) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(showsMore ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Text(showsMore ? "Свернуть" : "Звук компьютера, словарь, причёсывание")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Palette.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsMore {
                rareSettings
            }
        }
    }

    private var rareSettings: some View {
        VStack(alignment: .leading, spacing: Palette.spaceCardRows) {
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

            SwitchToggle(
                "Причёсывать текст",
                subtitle: "Пунктуация и слова-паразиты, +1 секунда · gpt-4o-mini",
                isOn: $model.cleanup
            )

            vocabulary
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
}
