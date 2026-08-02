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
final class StatusMenuBuilder: NSObject {
    weak var actions: StatusMenuActions?

    /// Последний расшифрованный текст — из него берутся «Скопировать» и «Вставить снова».
    var lastText: String?

    init(actions: StatusMenuActions? = nil) {
        self.actions = actions
    }

    func build() -> NSMenu {
        let menu = NSMenu()

        let statusRow = NSMenuItem(title: actions?.menuStatusTitle ?? "", action: nil, keyEquivalent: "")
        statusRow.isEnabled = false
        menu.addItem(statusRow)

        menu.addItem(.separator())

        if let lastText {
            let preview = lastText.count > 60 ? String(lastText.prefix(60)) + "…" : lastText
            menu.addItem(item("Скопировать: «\(preview)»", #selector(copyLast)))
            menu.addItem(.separator())
        }

        let settings = item("Настройки…", #selector(openSettings), key: ",")
        settings.representedObject = SettingsSection.general.rawValue
        menu.addItem(settings)

        if actions?.isHotkeyActive == false {
            menu.addItem(item("Выдать доступ к клавиатуре…", #selector(requestKeyboardAccess)))
        }

        menu.addItem(item("Диагностика…", #selector(showDiagnostics)))
        menu.addItem(item("Выйти", #selector(quit), key: "q"))

        return menu
    }

    private func item(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Обработчики

    @objc private func openSettings(_ sender: NSMenuItem) {
        let section = (sender.representedObject as? String)
            .flatMap(SettingsSection.init(rawValue:)) ?? .general
        actions?.menuOpenSettings(section)
    }

    @objc private func copyLast() {
        guard let lastText else { return }
        actions?.menuCopy(lastText)
    }

    @objc private func insertAgain() {
        guard let lastText else { return }
        actions?.menuInsertAgain(lastText)
    }

    @objc private func showDiagnostics() {
        actions?.menuShowDiagnostics()
    }

    @objc private func requestKeyboardAccess() {
        actions?.menuRequestKeyboardAccess()
    }

    @objc private func toggleSounds() {
        actions?.menuToggleSounds()
    }

    @objc private func quit() {
        actions?.menuQuit()
    }
}
