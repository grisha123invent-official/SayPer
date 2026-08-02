import AppKit

// MARK: - Что меню знает о мире

/// Снимок состояния на момент открытия меню.
///
/// Группы пунктов собираются из этой структуры и больше ниоткуда: пока данные
/// читались бы по месту (тут `HistoryStore`, там `Settings`), меню незаметно
/// стало бы вторым владельцем логики приложения. Снимок делается один раз
/// за открытие — иначе соседние пункты могли бы показать разные версии правды.
struct StatusMenuContext {
    /// Строка состояния первым пунктом: «Готово · зажми ⌥», «Идёт запись…».
    var statusTitle: String
    /// Работает ли перехват клавиатуры. Нет — сверху появляется баннер.
    var isHotkeyActive: Bool
    /// Текущий режим активации: в подменю «Режим» на нём галочка.
    var activation: HotkeyActivation
    /// Последний текст для «Скопировать» и «Вставить снова».
    var lastText: String?
    /// Последние расшифровки, свежая первой.
    var history: [TranscriptionRecord]
    /// Итог за сегодня для строки «Сегодня: N мин · $X.XX».
    var today: UsageStore.Summary
    var cleanup: Bool
    var playSounds: Bool
    var historyCount: Int
    var previewLength: Int

    /// Собрать снимок из живых хранилищ.
    ///
    /// `actions == nil` — не ошибка, а состояние до того, как `AppDelegate`
    /// подставил себя: меню в этот момент обязано построиться пустым каркасом,
    /// а не упасть и не показать баннер «нет доступа» на пустом месте.
    static func current(actions: StatusMenuActions?, lastText: String?) -> StatusMenuContext {
        let settings = Settings.shared
        let history = HistoryStore.shared.items

        // Последний текст держит `AppDelegate` в памяти, и после перезапуска
        // его нет — но история пережила перезапуск. Для человека «последнее,
        // что я наговорил» одно и то же в обоих случаях, поэтому подставляем
        // верхнюю запись истории. Пустая строка последним текстом не считается.
        let carried = (lastText?.isEmpty == false) ? lastText : nil

        return StatusMenuContext(
            statusTitle: actions?.menuStatusTitle ?? "",
            isHotkeyActive: actions?.isHotkeyActive ?? true,
            activation: actions?.menuActivation ?? .hold,
            lastText: carried ?? history.first?.text,
            history: history,
            today: UsageStore.shared.today,
            cleanup: settings.cleanup,
            playSounds: settings.playSounds,
            historyCount: settings.menuHistoryCount,
            previewLength: settings.menuPreviewLength
        )
    }

    /// Значок строки состояния.
    ///
    /// Протокол `StatusMenuActions` отдаёт состояние строкой и не отдаёт
    /// перечислением — расширять его слайсу запрещено, поэтому значок
    /// выводится из заголовка. Заголовки задаёт `AppDelegate` и они
    /// заморожены вместе с ним; если там появится новая формулировка,
    /// значок деградирует до `mic`, а не до пустоты.
    var statusSymbol: String {
        let title = statusTitle.lowercased()
        if title.hasPrefix("идёт запись") { return "mic.fill" }
        if title.hasPrefix("расшифровка") { return "waveform" }
        if title.hasPrefix("ошибка") { return "exclamationmark.triangle" }
        return "mic"
    }
}

// MARK: - Группы пунктов

/// Строит меню группами в порядке `design/ia.md` §4: сверху то, что блокирует
/// работу, затем состояние, затем действия с результатом, цифры и режим,
/// внизу — вход вглубь и выход.
///
/// Группа — массив пунктов; пустую группу билдер выбрасывает вместе с её
/// разделителем, поэтому «нет истории» и «нет расходов» не оставляют в меню
/// двух разделителей подряд.
struct StatusMenuSections {
    /// Target всех пунктов. Обработчики живут в билдере — он владеет меню
    /// и он же переживает открытие; группы существуют только на время сборки.
    unowned let builder: StatusMenuBuilder
    let context: StatusMenuContext

    var groups: [[NSMenuItem]] {
        [accessBanner, status, results, figures, navigation, exit]
    }

    // MARK: 1. Что блокирует работу

    /// Баннер отсутствия доступа. Единственный пункт выше строки состояния:
    /// без доступа к клавиатуре приложение не работает вообще, и сообщать
    /// об этом надо раньше, чем «Готово».
    var accessBanner: [NSMenuItem] {
        guard !context.isHotkeyActive else { return [] }

        let banner = item("Нет доступа к клавиатуре",
                          #selector(StatusMenuBuilder.requestKeyboardAccess))
        banner.image = Self.symbol("exclamationmark.triangle.fill", color: .systemOrange)
        return [banner]
    }

    // MARK: 2. Состояние

    /// Строка состояния. Выключена намеренно: она сообщает, а не действует.
    var status: [NSMenuItem] {
        guard !context.statusTitle.isEmpty else { return [] }

        let row = NSMenuItem(title: context.statusTitle, action: nil, keyEquivalent: "")
        row.isEnabled = false
        row.image = Self.symbol(context.statusSymbol)
        return [row]
    }

    // MARK: 3. Действия с результатом

    var results: [NSMenuItem] {
        var items: [NSMenuItem] = []

        if let text = context.lastText, !text.isEmpty {
            let copy = item("Скопировать «\(preview(text))»",
                            #selector(StatusMenuBuilder.copyText), key: "c")
            copy.representedObject = text
            items.append(copy)

            let insert = item("Вставить снова", #selector(StatusMenuBuilder.insertText))
            insert.representedObject = text
            items.append(insert)
        }

        if !context.history.isEmpty {
            let history = NSMenuItem(title: "История", action: nil, keyEquivalent: "")
            history.submenu = historySubmenu()
            items.append(history)
        }

        return items
    }

    /// Подменю «История»: несколько последних записей и вход в раздел.
    ///
    /// Действия те же, что у строки списка в окне (`design/components.md`):
    /// клик — скопировать, ⌥ — вставить снова. Второе сделано альтернативным
    /// пунктом, а не вложенным подменю на каждую запись: три уровня меню ради
    /// двух действий превращают «достать последний текст» в поход.
    private func historySubmenu() -> NSMenu {
        let menu = NSMenu(title: "История")
        menu.autoenablesItems = false

        for record in context.history.prefix(max(context.historyCount, 1)) {
            let text = preview(record.text)

            let copy = item("\(text)  ·  \(Self.stamp(record.date))",
                            #selector(StatusMenuBuilder.copyText))
            copy.representedObject = record.text
            menu.addItem(copy)

            let insert = item("\(text)  ·  вставить", #selector(StatusMenuBuilder.insertText))
            insert.representedObject = record.text
            insert.keyEquivalentModifierMask = .option
            insert.isAlternate = true
            menu.addItem(insert)
        }

        menu.addItem(.separator())

        let all = item("Показать все…", #selector(StatusMenuBuilder.openSettings))
        all.representedObject = SettingsSection.history.rawValue
        menu.addItem(all)

        return menu
    }

    // MARK: 4. Цифры и быстрые переключатели

    var figures: [NSMenuItem] {
        var items: [NSMenuItem] = []

        if !context.today.isEmpty {
            let usage = item(Self.todayTitle(context.today),
                             #selector(StatusMenuBuilder.openSettings))
            usage.representedObject = SettingsSection.usage.rawValue
            items.append(usage)
        }

        let mode = NSMenuItem(title: "Режим", action: nil, keyEquivalent: "")
        mode.submenu = modeSubmenu()
        items.append(mode)

        // «Причёсывать текст» — вторая и последняя настройка в меню: она меняет
        // то, что случится со следующей расшифровкой, и решение о ней принимают
        // ровно в тот момент, когда меню открыто.
        let cleanup = item("Причёсывать текст", #selector(StatusMenuBuilder.toggleCleanup))
        cleanup.state = context.cleanup ? .on : .off
        items.append(cleanup)

        // Звуки — служебная мелочь («сейчас неудобно, чтобы пикало»), поэтому
        // живут альтернативным пунктом под ⌥, тем же приёмом, что «Диагностика…»:
        // в обычном виде меню их нет, но выключить можно не открывая окно.
        let sounds = item("Звуковые сигналы", #selector(StatusMenuBuilder.toggleSounds))
        sounds.state = context.playSounds ? .on : .off
        sounds.keyEquivalentModifierMask = .option
        sounds.isAlternate = true
        items.append(sounds)

        return items
    }

    /// Подменю «Режим»: радио-выбор с галочкой на текущем.
    private func modeSubmenu() -> NSMenu {
        let menu = NSMenu(title: "Режим")
        menu.autoenablesItems = false

        for mode in HotkeyActivation.allCases {
            let row = item(mode.title, #selector(StatusMenuBuilder.setActivation))
            row.representedObject = mode.rawValue
            row.state = mode == context.activation ? .on : .off
            menu.addItem(row)
        }

        return menu
    }

    // MARK: 5. Вход вглубь

    var navigation: [NSMenuItem] {
        let settings = NSMenuItem(title: "Настройки…", action: nil, keyEquivalent: ",")
        settings.submenu = settingsSubmenu()

        // Альтернативный пункт: тот же keyEquivalent, другой модификатор —
        // так `NSMenu` подменяет «Настройки…» на «Диагностика…», пока держат ⌥.
        let diagnostics = item("Диагностика…",
                               #selector(StatusMenuBuilder.showDiagnostics), key: ",")
        diagnostics.keyEquivalentModifierMask = [.command, .option]
        diagnostics.isAlternate = true

        return [settings, diagnostics]
    }

    /// Подменю разделов: окно открывается сразу на нужном, без прохода по вкладкам.
    private func settingsSubmenu() -> NSMenu {
        let menu = NSMenu(title: "Настройки")
        menu.autoenablesItems = false

        for section in SettingsSection.allCases {
            let row = item(section.title, #selector(StatusMenuBuilder.openSettings))
            row.representedObject = section.rawValue
            row.image = Self.symbol(section.symbol)
            menu.addItem(row)
        }

        return menu
    }

    // MARK: 6. Выход

    var exit: [NSMenuItem] {
        [item("Выйти", #selector(StatusMenuBuilder.quit), key: "q")]
    }

    // MARK: - Мелочи сборки

    private func item(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = builder
        return item
    }

    /// Превью текста для пункта меню: одна строка, без хвостов пробелов.
    ///
    /// Переносы схлопываются в пробел — многострочная расшифровка иначе
    /// растянула бы пункт меню на весь экран.
    private func preview(_ text: String) -> String {
        let flat = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        let limit = max(context.previewLength, 4)

        guard flat.count > limit else { return flat }
        return flat.prefix(limit - 1) + "…"
    }

    /// «Сегодня: 12 мин · $0.08».
    ///
    /// Минуты округляются вверх до целой: «0 мин · $0.02» выглядит как ошибка
    /// счёта, хотя это просто короткая фраза.
    static func todayTitle(_ summary: UsageStore.Summary) -> String {
        let minutes = max(1, Int(summary.minutes.rounded()))
        return String(format: "Сегодня: %d мин · $%.2f", minutes, summary.cost)
    }

    /// Время записи: сегодняшняя — часами, вчерашняя и старше — датой.
    static func stamp(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now)
            ? timeFormatter.string(from: date)
            : dayFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    /// Значок пункта. Без цвета — шаблонный: так он следует теме строки меню
    /// и остаётся читаемым в обеих. Цвет задаётся только баннеру отсутствия
    /// доступа, и это единственное цветное пятно в меню (`design/dna.md`, П6).
    static func symbol(_ name: String, color: NSColor? = nil) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }

        guard let color else {
            image.isTemplate = true
            return image
        }

        let tinted = image.withSymbolConfiguration(.init(paletteColors: [color]))
        tinted?.isTemplate = false
        return tinted
    }
}
