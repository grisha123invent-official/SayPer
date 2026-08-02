import AppKit
import SwiftUI

/// Обёртка над NSWindow, чтобы окно жило независимо от меню.
///
/// Слои материалов — строго по `tokens.md` §1:
/// L0 — шасси окна, `.windowBackground` / `.behindWindow`;
/// L1 — полоса разделов в титлбаре, `.headerView` / `.withinWindow`;
/// L2 — подложка панели раздела, `.contentBackground` / `.withinWindow` (в корневом виде).
/// Прежний `.underWindowBackground` — самый прозрачный материал системы, из-за него
/// фон «пропадал» и текст просвечивал насквозь.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    let model = SettingsModel()

    /// ⌘1…⌘5. Через `keyboardShortcut` их не повесить: полоса разделов живёт
    /// в титлбаре, а `performKeyEquivalent` окна обходит только `contentView`.
    private var shortcutMonitor: Any?

    private static let size = NSSize(width: 740, height: 540)
    private static let minSize = NSSize(width: 700, height: 480)

    func show() {
        show(defaultSection())
    }

    /// Открыть окно сразу на нужном разделе — так работают пункты меню.
    func show(_ section: SettingsSection) {
        model.refreshPermissions()
        model.section = section

        let window = self.window ?? makeWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Окно

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // L0 — шасси. Стекло глушит рабочий стол до фона-шума, но само по себе
        // подложкой под текст не служит: текст лежит на L2 внутри корневого вида.
        let chassis = NSVisualEffectView()
        chassis.material = .windowBackground
        chassis.blendingMode = .behindWindow
        chassis.state = .followsWindowActiveState
        window.contentView = chassis

        // Фон-орб занимает всё окно, включая титлбар и полосу вкладок, —
        // стеклу капсулы разделов есть что преломлять, глухой полосы сверху нет.
        let backdrop = NSHostingView(rootView: AmbientGlow())
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        chassis.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: chassis.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: chassis.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: chassis.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: chassis.bottomAnchor)
        ])

        let hosting = NSHostingView(rootView: SettingsRootView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        chassis.addSubview(hosting)

        // `contentLayoutGuide` уже учитывает титлбар вместе с аксессуаром,
        // поэтому панель раздела встаёт ровно под полосу вкладок.
        let layoutGuide = window.contentLayoutGuide as? NSLayoutGuide
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: chassis.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: chassis.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: chassis.bottomAnchor),
            hosting.topAnchor.constraint(
                equalTo: layoutGuide?.topAnchor ?? chassis.topAnchor
            )
        ])

        window.addTitlebarAccessoryViewController(makeTabAccessory())

        window.title = "Надиктовка"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = Self.minSize
        // Окно тянется и по ширине: колонка карточек растягивается вместе с ним
        // до Palette.contentWidth, дальше остаётся по центру.
        window.setContentSize(Self.size)
        window.center()

        self.window = window
        installShortcutMonitor()

        return window
    }

    /// Полоса разделов в титлбаре, `layoutAttribute = .bottom`, высота 44.
    /// Подложки у полосы нет: под ней виден фон-орб окна, стеклянная капсула
    /// вкладок преломляет его сама.
    private func makeTabAccessory() -> NSTitlebarAccessoryViewController {
        let strip = NSHostingView(rootView: SettingsTabStrip(model: model))
        strip.frame = NSRect(x: 0, y: 0, width: Self.size.width, height: Palette.tabStripHeight)
        strip.autoresizingMask = [.width]

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .bottom
        accessory.view = strip
        return accessory
    }

    // MARK: - ⌘1…⌘5

    private func installShortcutMonitor() {
        guard shortcutMonitor == nil else { return }

        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }
            // Сравниваем только по значимым модификаторам: в
            // `deviceIndependentFlagsMask` входят ещё `.capsLock`, `.numericPad`
            // и `.function`, поэтому при горящем Caps Lock и на нумпаде
            // строгое равенство `.command` не выполняется никогда.
            let significant: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            guard event.modifierFlags.intersection(significant) == .command else {
                return event
            }
            // Пока в поле записывают сочетание, ⌘-клавиши принадлежат ему.
            guard !(window.firstResponder is HotkeyRecorderView) else { return event }

            guard let section = SettingsSection.allCases.first(where: {
                String($0.shortcut) == event.charactersIgnoringModifiers
            }) else { return event }

            self.model.section = section
            // Второй пользовательский путь смены раздела — наравне с кликом
            // по сегменту полосы. Больше `ui.lastSection` не пишет никто:
            // подписка на `model.$section` сохраняла и принудительные открытия
            // из меню, и откат к «Ключ и доступ» при невыданном доступе,
            // затирая раздел, на котором человек действительно работал.
            Settings.shared.lastSettingsSection = section
            return nil
        }
    }

    deinit {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
    }

    /// Пока нечем работать — открываем там, где это чинится; иначе возвращаем
    /// человека туда, где он был в прошлый раз.
    private func defaultSection() -> SettingsSection {
        if Settings.shared.apiKey == nil || !HotkeyMonitor.isTrusted {
            return .system
        }
        return Settings.shared.lastSettingsSection
    }
}
