import AppKit
import Foundation

/// Действие, которое помощник предлагает кнопкой под своим ответом.
///
/// Устройство намеренно неравноправное: модель выбирает только идентификатор
/// из закрытого списка ниже, а подпись кнопки, объяснение и само изменение
/// написаны здесь, руками. Ошибиться в понимании вопроса помощник может —
/// соврать о том, что произойдёт по нажатию, уже нет.
///
/// Нажимает всегда человек. Молча приложение ничего не переключает: иначе
/// настройка уехала бы незаметно, и человек узнал бы об этом через неделю,
/// когда что-то перестало работать, — без единой подсказки, откуда это взялось.
struct HelpAction: Identifiable {
    let id: String
    /// Подпись кнопки.
    let title: String
    /// Что произойдёт по нажатию. Показывается до нажатия, а не после.
    let detail: String
    /// Что стало — короткой строкой, вместо кнопки после нажатия.
    let done: String
    /// По каким словам это опознавать. Только для системной подсказки:
    /// по названию «Океан» модель не догадается, что человек просил синий.
    var when: String? = nil
    /// Есть ли смысл предлагать. Уже включённое не предлагаем: кнопка
    /// «включить то, что и так включено» выглядит как непонимание вопроса.
    let isRelevant: () -> Bool
    let apply: (SettingsModel) -> Void

    /// Всё, что помощник вправе предложить. Список закрытый: чего здесь нет,
    /// того он предложить не может, даже если очень захочет.
    ///
    /// Каждое действие — одна настройка и один шаг назад. Ничего
    /// необратимого, ничего, что стирает данные, ничего, что уходит наружу.
    static let catalog: [HelpAction] = [
        HelpAction(
            id: "mic.builtin",
            title: "Писать встроенным микрофоном",
            detail: "Микрофоном станет встроенный микрофон мака. Музыка "
                  + "в беспроводных наушниках перестанет прерываться на время "
                  + "диктовки, но и голос пойдёт с мака, а не с гарнитуры.",
            done: "Микрофон — встроенный",
            isRelevant: { Settings.shared.microphone != .builtIn },
            apply: { _ in Settings.shared.microphone = .builtIn }
        ),
        HelpAction(
            id: "mic.headset",
            title: "Писать микрофоном гарнитуры",
            detail: "Микрофоном станет беспроводная гарнитура. Голос будет "
                  + "ближе ко рту, но на время записи наушники перейдут "
                  + "в гарнитурный режим и музыка в них прервётся.",
            done: "Микрофон — гарнитура",
            isRelevant: {
                guard let headset = AudioDevices.inputs().first(where: \.isBluetooth) else {
                    return false
                }
                return Settings.shared.microphone != .device(headset.uid)
            },
            apply: { _ in
                guard let headset = AudioDevices.inputs().first(where: \.isBluetooth) else { return }
                Settings.shared.microphone = .device(headset.uid)
            }
        ),
        HelpAction(
            id: "duck.off",
            title: "Не трогать звук компьютера",
            detail: "Во время записи громкость останется прежней. Голос "
                  + "придётся перекрикивать музыку, зато ничего не переключается.",
            done: "Звук компьютера не трогаем",
            isRelevant: { Settings.shared.duckMode != .off },
            apply: { _ in Settings.shared.duckMode = .off }
        ),
        HelpAction(
            id: "duck.dim",
            title: "Убавлять звук на время записи",
            detail: "Пока идёт запись, громкость мака опускается, после — "
                  + "возвращается на прежнюю. Глубина настраивается ползунком "
                  + "в «Диктовке», под «Ещё».",
            done: "Звук убавляется на время записи",
            isRelevant: { Settings.shared.duckMode != .dim },
            apply: { _ in Settings.shared.duckMode = .dim }
        ),
        HelpAction(
            id: "insert.paste",
            title: "Вставлять через ⌘V",
            detail: "Текст встанет мгновенно, а буфер обмена вернётся к тому, "
                  + "что в нём было. Обычный способ, подходит почти везде.",
            done: "Вставка — через ⌘V",
            isRelevant: { Settings.shared.insertMode != .paste },
            apply: { model in model.insertMode = .paste }
        ),
        HelpAction(
            id: "insert.type",
            title: "Печатать посимвольно",
            detail: "Приложение наберёт текст как с клавиатуры. Медленнее, "
                  + "зато работает в окнах, где ⌘V перехвачен или запрещён.",
            done: "Вставка — посимвольно",
            isRelevant: { Settings.shared.insertMode != .type },
            apply: { model in model.insertMode = .type }
        ),
        HelpAction(
            id: "insert.clipboard",
            title: "Только копировать в буфер",
            detail: "Никуда не вставляем — текст просто ложится в буфер, "
                  + "и вставишь его сам. Годится, когда «Универсальный доступ» "
                  + "не выдан.",
            done: "Текст только копируется в буфер",
            isRelevant: { Settings.shared.insertMode != .clipboardOnly },
            apply: { model in model.insertMode = .clipboardOnly }
        ),
        HelpAction(
            id: "activation.hold",
            title: "Включить режим удержания",
            detail: "Держишь клавишу — идёт запись, отпустил — расшифровка. "
                  + "Забыть выключенным нельзя.",
            done: "Режим — удержание",
            isRelevant: { Settings.shared.hotkeyActivation != .hold },
            apply: { _ in Settings.shared.hotkeyActivation = .hold }
        ),
        HelpAction(
            id: "activation.toggle",
            title: "Включить режим «нажал-нажал»",
            detail: "Первое нажатие начинает запись, второе заканчивает. "
                  + "Удобно для длинных мыслей; забытая запись сама остановится "
                  + "через пять минут.",
            done: "Режим — «нажал-нажал»",
            isRelevant: { Settings.shared.hotkeyActivation != .toggle },
            apply: { _ in Settings.shared.hotkeyActivation = .toggle }
        ),
        HelpAction(
            id: "cleanup.on",
            title: "Причёсывать текст",
            detail: "После расшифровки текст уходит на второй запрос: убрать "
                  + "«э-э» и повторы, расставить знаки. Немного точнее по виду "
                  + "и немного дороже — это ещё один вызов модели.",
            done: "Текст причёсывается",
            isRelevant: { !Settings.shared.cleanup },
            apply: { model in model.cleanup = true }
        ),
        HelpAction(
            id: "cleanup.off",
            title: "Не причёсывать текст",
            detail: "Текст встанет ровно таким, каким его услышал Whisper. "
                  + "Быстрее и дешевле, но со словами-паразитами.",
            done: "Текст не причёсывается",
            isRelevant: { Settings.shared.cleanup },
            apply: { model in model.cleanup = false }
        ),
        HelpAction(
            id: "indicator.on",
            title: "Показывать индикатор записи",
            detail: "Во время диктовки на экране появляется пилюля — видно, "
                  + "что микрофон слышит.",
            done: "Индикатор показывается",
            isRelevant: { !Settings.shared.showIndicator },
            apply: { model in model.showIndicator = true }
        ),
        HelpAction(
            id: "indicator.off",
            title: "Скрыть индикатор записи",
            detail: "Пилюля перестанет появляться. Понять, что запись идёт, "
                  + "можно будет по знаку в строке меню.",
            done: "Индикатор скрыт",
            isRelevant: { Settings.shared.showIndicator },
            apply: { model in model.showIndicator = false }
        ),
        HelpAction(
            id: "sounds.off",
            title: "Выключить звуковые сигналы",
            detail: "Начало и конец записи перестанут звучать. Заодно "
                  + "приложение перестанет трогать вывод звука своими сигналами.",
            done: "Сигналы выключены",
            isRelevant: { Settings.shared.playSounds },
            apply: { model in model.playSounds = false }
        ),
        HelpAction(
            id: "sounds.on",
            title: "Включить звуковые сигналы",
            detail: "Начало и конец записи будут отмечаться коротким звуком. "
                  + "Громкость настраивается в «Кастомизации».",
            done: "Сигналы включены",
            isRelevant: { !Settings.shared.playSounds },
            apply: { model in model.playSounds = true }
        ),
        HelpAction(
            id: "history.off",
            title: "Не хранить историю",
            detail: "Расшифровки перестанут сохраняться на маке. Уже "
                  + "сохранённое останется — очистить его можно в разделе "
                  + "«История».",
            done: "История не хранится",
            isRelevant: { Settings.shared.historyEnabled },
            apply: { _ in Settings.shared.historyEnabled = false }
        ),
        HelpAction(
            id: "history.on",
            title: "Хранить историю",
            detail: "Последние расшифровки будут сохраняться на маке "
                  + "и показываться в панели строки меню. Наружу они не уходят.",
            done: "История хранится",
            isRelevant: { !Settings.shared.historyEnabled },
            apply: { _ in Settings.shared.historyEnabled = true }
        ),
        HelpAction(
            id: "verbose.on",
            title: "Включить подробный журнал",
            detail: "В журнал начнёт писаться всё: устройства, форматы, "
                  + "сетевые попытки, решения приглушения. Нужно, чтобы поймать "
                  + "плавающую ошибку и отдать файл разработчику.",
            done: "Подробный журнал включён",
            isRelevant: { !Settings.shared.verboseLog },
            apply: { _ in
                Settings.shared.verboseLog = true
                Log.write("Подробный журнал включён из помощника")
            }
        ),
        HelpAction(
            id: "verbose.off",
            title: "Выключить подробный журнал",
            detail: "Журнал вернётся к коротким записям о главном "
                  + "и перестанет расти.",
            done: "Подробный журнал выключен",
            isRelevant: { Settings.shared.verboseLog },
            apply: { _ in
                Settings.shared.verboseLog = false
                Log.write("Подробный журнал выключен из помощника")
            }
        ),
        HelpAction(
            id: "accent.violet",
            title: "Сделать фиолетовым",
            detail: "Акцентом станет «Фиолетовый». Поменяется всё, что подсвечено: "
                  + "переключатели, активная вкладка, свечение фона "
                  + "и индикатор записи во время диктовки.",
            done: "Акцент — «Фиолетовый»",
            when: "фиолетовый, сиреневый, лиловый",
            isRelevant: { Settings.shared.accentTheme != .violet },
            apply: { model in
                Settings.shared.accentTheme = .violet
                model.appearanceChanged()
            }
        ),
        HelpAction(
            id: "accent.ocean",
            title: "Сделать синим",
            detail: "Акцентом станет «Океан». Поменяется всё, что подсвечено: "
                  + "переключатели, активная вкладка, свечение фона "
                  + "и индикатор записи во время диктовки.",
            done: "Акцент — «Океан»",
            when: "синий, голубой",
            isRelevant: { Settings.shared.accentTheme != .ocean },
            apply: { model in
                Settings.shared.accentTheme = .ocean
                model.appearanceChanged()
            }
        ),
        HelpAction(
            id: "accent.mint",
            title: "Сделать зелёным",
            detail: "Акцентом станет «Мята». Поменяется всё, что подсвечено: "
                  + "переключатели, активная вкладка, свечение фона "
                  + "и индикатор записи во время диктовки.",
            done: "Акцент — «Мята»",
            when: "зелёный, мятный, салатовый, бирюзовый",
            isRelevant: { Settings.shared.accentTheme != .mint },
            apply: { model in
                Settings.shared.accentTheme = .mint
                model.appearanceChanged()
            }
        ),
        HelpAction(
            id: "accent.sunset",
            title: "Сделать оранжевым",
            detail: "Акцентом станет «Закат». Поменяется всё, что подсвечено: "
                  + "переключатели, активная вкладка, свечение фона "
                  + "и индикатор записи во время диктовки.",
            done: "Акцент — «Закат»",
            when: "оранжевый, рыжий, тёплый",
            isRelevant: { Settings.shared.accentTheme != .sunset },
            apply: { model in
                Settings.shared.accentTheme = .sunset
                model.appearanceChanged()
            }
        ),
        HelpAction(
            id: "accent.rose",
            title: "Сделать розовым",
            detail: "Акцентом станет «Роза». Поменяется всё, что подсвечено: "
                  + "переключатели, активная вкладка, свечение фона "
                  + "и индикатор записи во время диктовки.",
            done: "Акцент — «Роза»",
            when: "розовый, малиновый",
            isRelevant: { Settings.shared.accentTheme != .rose },
            apply: { model in
                Settings.shared.accentTheme = .rose
                model.appearanceChanged()
            }
        ),
        HelpAction(
            id: "accent.graphite",
            title: "Сделать серым",
            detail: "Акцентом станет «Графит». Поменяется всё, что подсвечено: "
                  + "переключатели, активная вкладка, свечение фона "
                  + "и индикатор записи во время диктовки.",
            done: "Акцент — «Графит»",
            when: "серый, графитовый, без цвета, поспокойнее",
            isRelevant: { Settings.shared.accentTheme != .graphite },
            apply: { model in
                Settings.shared.accentTheme = .graphite
                model.appearanceChanged()
            }
        ),
        HelpAction(
            id: "theme.dark",
            title: "Включить тёмную тему",
            detail: "Окна приложения станут тёмными независимо от того, что стоит в macOS.",
            done: "Тема — тёмная",
            when: "тёмная, ночная, потемнее",
            isRelevant: { Settings.shared.appearanceMode != .dark },
            apply: { model in
                Settings.shared.appearanceMode = .dark
                AppearanceMode.dark.apply()
                model.appearanceChanged()
            }
        ),
        HelpAction(
            id: "theme.light",
            title: "Включить светлую тему",
            detail: "Окна приложения станут светлыми независимо от того, что стоит в macOS.",
            done: "Тема — светлая",
            when: "светлая, белая, посветлее",
            isRelevant: { Settings.shared.appearanceMode != .light },
            apply: { model in
                Settings.shared.appearanceMode = .light
                AppearanceMode.light.apply()
                model.appearanceChanged()
            }
        ),
        HelpAction(
            id: "theme.system",
            title: "Следовать теме системы",
            detail: "Приложение будет светлеть и темнеть вместе с macOS.",
            done: "Тема — как в системе",
            when: "как в системе, автоматически, вслед за macOS",
            isRelevant: { Settings.shared.appearanceMode != .system },
            apply: { model in
                Settings.shared.appearanceMode = .system
                AppearanceMode.system.apply()
                model.appearanceChanged()
            }
        ),
        HelpAction(
            id: "open.hotkey",
            title: "Открыть настройку сочетания",
            detail: "Перейдём в «Диктовку», где сочетание задаётся: кликнуть "
                  + "по полю и зажать нужные клавиши. Ничего не меняется, "
                  + "просто открывается раздел.",
            done: "Открыт раздел «Диктовка»",
            isRelevant: { true },
            apply: { model in model.section = .general }
        ),
        HelpAction(
            id: "open.key",
            title: "Открыть раздел с ключом",
            detail: "Перейдём в «Ключ и расходы» — там задаётся ключ OpenAI "
                  + "и видны расходы. Ничего не меняется.",
            done: "Открыт раздел «Ключ и расходы»",
            isRelevant: { true },
            apply: { model in model.section = .system }
        ),
        HelpAction(
            id: "grant.accessibility",
            title: "Открыть «Универсальный доступ»",
            detail: "macOS спросит разрешение и откроет нужный список "
                  + "в системных настройках — останется щёлкнуть переключатель "
                  + "у SayPer. Без этого текст не вставляется в чужие окна.",
            done: "Системные настройки открыты",
            isRelevant: { !HotkeyMonitor.isTrusted },
            apply: { _ in
                HotkeyMonitor.requestTrust()
                openPrivacyPane("Privacy_Accessibility")
            }
        ),
        HelpAction(
            id: "grant.input",
            title: "Открыть «Мониторинг ввода»",
            detail: "macOS спросит разрешение и откроет нужный список. "
                  + "Без него приложение не видит горячую клавишу.",
            done: "Системные настройки открыты",
            isRelevant: { !HotkeyMonitor.hasInputMonitoring },
            apply: { _ in
                HotkeyMonitor.requestInputMonitoring()
                openPrivacyPane("Privacy_ListenEvent")
            }
        )
    ]

    static func named(_ id: String) -> HelpAction? {
        catalog.first { $0.id == id }
    }

    /// Список для системной подсказки: идентификатор и когда его предлагать.
    static var promptList: String {
        catalog.map { action in
            var line = "- \(action.id): \(action.title.lowercased())"
            if let when = action.when { line += " — \(when)" }
            return line
        }.joined(separator: "\n")
    }

    private static func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
