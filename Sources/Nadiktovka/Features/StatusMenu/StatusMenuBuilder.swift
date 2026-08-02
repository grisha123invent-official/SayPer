import AppKit

/// Что меню умеет попросить у приложения. Протокол заморожен и реализован
/// целиком: слайс «Меню» верстает пункты, не трогая `AppDelegate`.
protocol StatusMenuActions: AnyObject {
    /// Строка состояния первым пунктом: «Готово · зажми ⌥», «Идёт запись…», «Ошибка: …».
    var menuStatusTitle: String { get }
    /// Работает ли перехват клавиатуры. Если нет — меню показывает пункт про доступ.
    var isHotkeyActive: Bool { get }

    func menuOpenSettings(_ section: SettingsSection)
    func menuCopy(_ text: String)
    func menuInsertAgain(_ text: String)
    func menuShowDiagnostics()
    func menuRequestKeyboardAccess()
    func menuToggleSounds()
    func menuQuit()
}

/// Собирает меню в строке статуса. Сам является target пунктов, чтобы
/// `AppDelegate` не держал у себя ни одного `@objc`-обработчика меню.
///
/// Разделение труда: состав и порядок пунктов знает `StatusMenuSections`,
/// билдер отвечает за две вещи — сшить группы разделителями и выполнить то,
/// на что кликнули. Поэтому обработчики здесь читают `representedObject`
/// и не хранят состояния: пункт приносит с собой всё, что нужно.
final class StatusMenuBuilder: NSObject, NSMenuDelegate {
    weak var actions: StatusMenuActions?

    /// Последний расшифрованный текст — из него берутся «Скопировать» и «Вставить снова».
    /// Пустое значение не беда: снимок состояния подставит верхнюю запись истории.
    var lastText: String?

    init(actions: StatusMenuActions? = nil) {
        self.actions = actions
        super.init()
    }

    /// Собрать меню. Наполнение при этом не окончательное: между сборкой
    /// и открытием проходит сколько угодно времени, поэтому меню
    /// пересобирается ещё раз перед показом (`menuNeedsUpdate`).
    func build() -> NSMenu {
        let menu = NSMenu()
        // Пункты включает и гасит вёрстка, а не цепочка респондеров: строка
        // состояния должна быть серой, оставаясь при этом обычным пунктом.
        menu.autoenablesItems = false
        menu.delegate = self
        populate(menu)
        return menu
    }

    /// Перед каждым показом меню собирается заново: «Сегодня», история и режим
    /// меняются между двумя кликами по иконке, а меню живёт от сборки до сборки.
    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        let sections = StatusMenuSections(
            builder: self,
            context: .current(actions: actions, lastText: lastText)
        )

        // Разделитель ставится перед группой, а не после: так пустая группа
        // (нет истории, нет расходов за сегодня) исчезает целиком и не оставляет
        // за собой ни висящей черты, ни двух подряд.
        for group in sections.groups where !group.isEmpty {
            if menu.numberOfItems > 0 {
                menu.addItem(.separator())
            }
            group.forEach(menu.addItem)
        }
    }

    // MARK: - Обработчики
    //
    // Внутренние, а не приватные: на них ссылается `StatusMenuSections`
    // через `#selector`. Все они однострочные — вся работа у `actions`.

    @objc func openSettings(_ sender: NSMenuItem) {
        let section = (sender.representedObject as? String)
            .flatMap(SettingsSection.init(rawValue:)) ?? .general
        actions?.menuOpenSettings(section)
    }

    @objc func copyText(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        actions?.menuCopy(text)
    }

    @objc func insertText(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        actions?.menuInsertAgain(text)
    }

    /// Пункт подменю «Режим»: сам режим лежит в `representedObject`,
    /// как у «Настроек…», — так меню не заводит по обработчику на вариант.
    ///
    /// Пишем прямо в настройки, а не через `StatusMenuActions`: протокол
    /// заморожен планом и расширять его слайсу запрещено. Канал до шлюза
    /// не нужен — `RecordingGate` сам слушает `UserDefaults.didChangeNotification`
    /// и перечитывает режим, как и карточка «Режим» в окне.
    @objc func setActivation(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = HotkeyActivation(rawValue: raw) else { return }
        Settings.shared.hotkeyActivation = mode
    }

    /// «Причёсывать текст». Пишется прямо в настройки той же дорогой, что и
    /// режим: в `StatusMenuActions` метода под неё нет, а протокол заморожен.
    ///
    /// Своего состояния пункт не держит — галочку рисует снимок настроек при
    /// следующей сборке меню. Единственный владелец значения — `Settings`.
    @objc func toggleCleanup(_ sender: NSMenuItem) {
        Settings.shared.cleanup = !Settings.shared.cleanup
    }

    @objc func showDiagnostics() {
        actions?.menuShowDiagnostics()
    }

    @objc func requestKeyboardAccess() {
        actions?.menuRequestKeyboardAccess()
    }

    @objc func quit() {
        actions?.menuQuit()
    }
}
