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
    /// Раздел, на котором окно настроек закрыли в прошлый раз: «Настройки…»
    /// возвращают человека туда же, куда и ⌘, из самого приложения.
    var lastSection: SettingsSection
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
            // Режим читается из настроек, а не у `AppDelegate`: писателей
            // двое (карточка «Режим» и это меню), оба пишут туда же, а шлюз
            // перечитывает значение сам — лишнего звена в протоколе не нужно.
            activation: settings.hotkeyActivation,
            lastText: carried ?? history.first?.text,
            history: history,
            today: UsageStore.shared.today,
            cleanup: settings.cleanup,
            lastSection: settings.lastSettingsSection,
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

        let records = Array(context.history.prefix(max(context.historyCount, 1)))
        let rows = records.map { (head: preview($0.text), tail: Self.stamp($0.date)) }

        // Правая колонка одна на всё подменю (`menu.html`: `.mi .tail` с
        // `margin-left:auto`). Позиция считается по самому длинному превью,
        // иначе на короткой расшифровке время уехало бы влево к тексту.
        let column = Self.tailColumn(heads: rows.map { $0.head },
                                     tails: rows.map { $0.tail } + [Self.insertTail])

        for (record, row) in zip(records, rows) {
            let copy = item(row.head, #selector(StatusMenuBuilder.copyText))
            copy.attributedTitle = Self.twoColumnTitle(row.head, tail: row.tail, column: column)
            copy.representedObject = record.text
            menu.addItem(copy)

            let insert = item(row.head, #selector(StatusMenuBuilder.insertText))
            insert.attributedTitle = Self.twoColumnTitle(row.head,
                                                         tail: Self.insertTail,
                                                         column: column)
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
            usage.representedObject = SettingsSection.system.rawValue
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

        // Звуков здесь нет и не будет: `design/ia.md` §4 «Что в меню не попадает»
        // называет их поимённо, а `menu.html` под ⌥ показывает ровно одну
        // подмену — «Настройки…» → «Диагностика…». `menuToggleSounds` остаётся
        // нереализованным в UI: протокол заморожен именно с таким расчётом.

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

    /// «Настройки…» — обычная кликабельная строка с ⌘, (`menu.html`, `ia.md` §4).
    ///
    /// Подменю разделов здесь стоять не может: `NSMenuItem` с подменю не шлёт
    /// action и не показывает keyEquivalent — то есть отбирает у пункта ровно
    /// то, ради чего он существует. Вход в отдельные разделы остаётся там, где
    /// он осмыслен: «Показать все…» → «История», «Сегодня: …» → «Расходы».
    var navigation: [NSMenuItem] {
        let settings = item("Настройки…", #selector(StatusMenuBuilder.openSettings), key: ",")
        settings.representedObject = context.lastSection.rawValue

        // Альтернативный пункт: тот же keyEquivalent, другой модификатор —
        // так `NSMenu` подменяет «Настройки…» на «Диагностика…», пока держат ⌥.
        let diagnostics = item("Диагностика…",
                               #selector(StatusMenuBuilder.showDiagnostics), key: ",")
        diagnostics.keyEquivalentModifierMask = [.command, .option]
        diagnostics.isAlternate = true

        return [settings, diagnostics]
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

    // MARK: - Правая колонка подменю «История»

    /// Хвост альтернативного пункта: то же место, где у обычного стоит время.
    private static let insertTail = "вставить"

    /// Шрифт пунктов меню. Кегль 0 — «системный размер меню», тот же, которым
    /// `NSMenu` рисует обычные заголовки: колонка обязана считаться по нему,
    /// иначе она разъедется при другом размере системного шрифта.
    private static var menuFont: NSFont { .menuFont(ofSize: 0) }

    /// Позиция правого края колонки хвостов.
    ///
    /// Считается по самому длинному превью плюс отбивка 22pt (`menu.html`:
    /// `.tail { padding-left: 22px }`) плюс самый длинный хвост — так все
    /// хвосты кончаются на одной вертикали и ни один не наезжает на текст.
    private static func tailColumn(heads: [String], tails: [String]) -> CGFloat {
        ceil(widest(heads)) + 22 + ceil(widest(tails))
    }

    private static func widest(_ strings: [String]) -> CGFloat {
        strings.reduce(0) { widest, string in
            max(widest, (string as NSString).size(withAttributes: [.font: menuFont]).width)
        }
    }

    /// Две колонки в одном заголовке: текст слева, хвост справа по табу.
    ///
    /// Цвет не задаётся намеренно: у `attributedTitle` заданный цвет переживает
    /// подсветку пункта, и серый хвост остался бы серым на синей полосе.
    private static func twoColumnTitle(_ head: String,
                                       tail: String,
                                       column: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: column)]

        return NSAttributedString(
            string: "\(head)\t\(tail)",
            attributes: [.font: menuFont, .paragraphStyle: style]
        )
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
    ///
    /// Размер и вес задаются явно (`tokens.md` §9: значок в строке — 14pt,
    /// начертание `regular`): без конфигурации SF Symbol берёт собственный
    /// умолчательный кегль и раздувает высоту строк меню против эталона.
    static func symbol(_ name: String, color: NSColor? = nil) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }

        let size = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)

        guard let color else {
            let plain = image.withSymbolConfiguration(size)
            plain?.isTemplate = true
            return plain
        }

        let tinted = image.withSymbolConfiguration(
            size.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        )
        tinted?.isTemplate = false
        return tinted
    }
}
