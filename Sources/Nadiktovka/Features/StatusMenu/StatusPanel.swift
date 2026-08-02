import AppKit
import SwiftUI

/// Панель, которая раскрывается из иконки в строке меню вместо системного
/// списка. Список из десяти пунктов заставлял целиться в тонкие строки;
/// здесь то, чем пользуются каждый день, — крупными зонами: состояние,
/// последние расшифровки в один клик, режим и расходы.
///
/// Окно — `NSPanel` без рамки: системное меню не умеет ни стекла, ни своей
/// вёрстки. Позиционируется под иконкой, закрывается кликом мимо и по Esc.
final class StatusPanelController {
    private weak var actions: StatusPanelActions?
    private var panel: NSPanel?
    private var resignObserver: NSObjectProtocol?
    private var localKeyMonitor: Any?

    private let model = StatusPanelModel()

    private static let size = NSSize(width: 320, height: 0)

    init(actions: StatusPanelActions) {
        self.actions = actions
    }

    var isOpen: Bool { panel?.isVisible ?? false }

    func toggle(from button: NSStatusBarButton) {
        isOpen ? close() : open(from: button)
    }

    func open(from button: NSStatusBarButton) {
        guard let actions else { return }

        model.refresh(from: actions)

        let panel = self.panel ?? makePanel()
        layout(panel, under: button)

        panel.alphaValue = 0
        // Панель делается ключевой: тогда клик мимо забирает у неё фокус,
        // и она закрывается сама. Прежний вариант — глобальный монитор мыши —
        // требовал прав универсального доступа, и система спрашивала их
        // при каждом открытии.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        startMonitors()
    }

    func close() {
        stopMonitors()
        guard let panel, panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    /// Состояние в панели живое: пока она открыта, статус и цифры обновляются.
    func refreshIfOpen() {
        guard isOpen, let actions else { return }
        model.refresh(from: actions)
    }

    // MARK: - Окно

    private func makePanel() -> NSPanel {
        let root = StatusPanelView(model: model) { [weak self] in self?.close() }
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // Панель повторяет окно приложения: тёмное шасси, поверх — фон-орб,
        // и уже на нём стеклянные элементы. Прежний светлый `.sidebar`
        // сам по себе давал ровную серую плашку: материалу нечего было
        // показывать, кроме тёмного экрана под панелью.
        let glass = NSVisualEffectView()
        glass.material = .windowBackground
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 16
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true

        // Хостинг обязан быть прозрачным: непрозрачный слой SwiftUI закрыл бы
        // стекло собой, и весь эффект пропал бы независимо от материала.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        glass.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: glass.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: Self.size.width, height: 320)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = glass
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Тень и кромку рисует стекло содержимого.
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        self.panel = panel
        return panel
    }

    private func layout(_ panel: NSPanel, under button: NSStatusBarButton) {
        panel.layoutIfNeeded()
        let fitting = panel.contentView?.fittingSize ?? NSSize(width: Self.size.width, height: 320)
        let height = max(fitting.height, 200)
        panel.setContentSize(NSSize(width: Self.size.width, height: height))

        guard let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )

        var x = buttonRect.midX - Self.size.width / 2
        let y = buttonRect.minY - height - 6

        // Не вылезать за край экрана: у правого края строки меню иконок много.
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(buttonRect) }) {
            let limit = screen.visibleFrame
            x = min(max(x, limit.minX + 8), limit.maxX - Self.size.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Закрытие

    private func startMonitors() {
        stopMonitors()

        // Клик мимо панели уводит у неё фокус — этого достаточно, чтобы
        // закрыться. Никаких глобальных мониторов ввода: они требуют
        // разрешения и приводят к системному запросу при каждом открытии.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.close()
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                self?.close()
                return nil
            }
            return event
        }
    }

    private func stopMonitors() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        resignObserver = nil
        localKeyMonitor = nil
    }
}

/// Окно без рамки по умолчанию не может стать ключевым, а панели это нужно:
/// на потере фокуса она закрывается.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// То, что панель умеет попросить у приложения. Расширяет протокол меню:
/// сама панель ничего не знает ни про запись, ни про настройки.
protocol StatusPanelActions: AnyObject {
    var menuStatusTitle: String { get }
    var isHotkeyActive: Bool { get }
    var menuActivation: HotkeyActivation { get }

    func menuOpenSettings(_ section: SettingsSection)
    func menuCopy(_ text: String)
    func menuInsertAgain(_ text: String)
    func menuShowDiagnostics()
    func menuRequestKeyboardAccess()
    func menuSetActivation(_ mode: HotkeyActivation)
    func menuQuit()
}

// MARK: - Модель

final class StatusPanelModel: ObservableObject {
    @Published var statusTitle = ""
    @Published var hasKeyboardAccess = true
    @Published var activation: HotkeyActivation = .hold
    @Published var hotkey = ""
    @Published var cleanup = false
    @Published var history: [TranscriptionRecord] = []
    @Published var todayMinutes = 0.0
    @Published var todayCost = 0.0
    @Published var todayCount = 0

    weak var actions: StatusPanelActions?

    func refresh(from actions: StatusPanelActions) {
        self.actions = actions
        statusTitle = actions.menuStatusTitle
        hasKeyboardAccess = actions.isHotkeyActive
        activation = actions.menuActivation
        hotkey = Settings.shared.hotkey.displayString
        cleanup = Settings.shared.cleanup
        history = Array(HistoryStore.shared.items.prefix(3))

        let today = UsageStore.shared.today
        todayMinutes = today.minutes
        todayCost = today.cost
        todayCount = today.count
    }
}

// MARK: - Вид

private struct StatusPanelView: View {
    @ObservedObject var model: StatusPanelModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.hasKeyboardAccess {
                accessBanner
            }

            header

            if !model.history.isEmpty {
                recent
            }

            controls
            usage
            footer
        }
        .padding(14)
        .frame(width: 320)
        // Тот же фон, что в окне настроек: без него стеклу элементов нечего
        // преломлять и панель выглядит плоской серой плашкой. Слегка
        // приглушён — панель узкая, орб в ней крупнее относительно текста.
        // Свой фон, не орб из окна: два свечения по краям светят там, где
        // стоят стеклянные элементы, и не засвечивают середину со списком.
        .background(PanelGlow())
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.rimGlass, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                // Внутри панели стекло уже есть — своё поверх него мутит
                // картинку. Кружок держится заливкой и кромкой.
                Circle()
                    .fill(.white.opacity(0.10))
                    .glassEffect(.clear, in: Circle())
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(model.activation == .hold
                     ? "Зажми \(model.hotkey) и говори"
                     : "Нажми \(model.hotkey), потом ещё раз")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var accessBanner: some View {
        Button {
            model.actions?.menuRequestKeyboardAccess()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
                Text("Нет доступа к клавиатуре")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.bannerFill)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Расходы

    /// Строка вместо трёх плиток: цифры за день смотрят из любопытства раз
    /// в неделю, а места плитки занимали четверть панели. Клик ведёт
    /// в раздел «Расходы», где та же статистика подробно.
    private var usage: some View {
        Button {
            model.actions?.menuOpenSettings(.usage)
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Text("Сегодня")
                    .foregroundStyle(.secondary)
                Text(summary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var summary: String {
        let minutes = model.todayMinutes < 1 && model.todayMinutes > 0
            ? "меньше минуты"
            : "\(Int(model.todayMinutes.rounded())) мин"
        return "\(model.todayCount) · \(minutes) · " + String(format: "$%.2f", model.todayCost)
    }

    // MARK: Последние расшифровки

    private var recent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Последние")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(model.history) { record in
                    RecentRow(record: record) {
                        model.actions?.menuInsertAgain(record.text)
                        dismiss()
                    } copy: {
                        model.actions?.menuCopy(record.text)
                        dismiss()
                    }
                }
            }
            .padding(4)
            // Данные — спокойная плашка с обводкой, без стекла: сквозь стекло
            // орб просвечивал прямо в строки и мешал их читать. Стекло здесь
            // работает на кнопках, где нужна отзывчивость, а не на списке.
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black.opacity(0.30))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.rimGlass, lineWidth: 1)
            )
        }
    }

    private struct RecentRow: View {
        let record: TranscriptionRecord
        let insert: () -> Void
        let copy: () -> Void

        @State private var hovered = false

        var body: some View {
            HStack(spacing: 8) {
                Text(record.text)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)

                if hovered {
                    Button(action: copy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Скопировать")
                }

                Text(Self.time.string(from: record.date))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovered ? Palette.surfaceRowHover : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovered = $0 }
            .onTapGesture(perform: insert)
            .help("Вставить снова")
        }

        private static let time: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f
        }()
    }

    // MARK: Быстрые переключатели

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Режим")
                    .font(.system(size: 12))
                Spacer(minLength: 0)
                SegmentedControl(
                    selection: Binding(
                        get: { model.activation },
                        set: { model.actions?.menuSetActivation($0); model.activation = $0 }
                    ),
                    options: HotkeyActivation.allCases,
                    compact: true
                ) { $0.title }
                // 168 не хватало: «Нажал-нажал» обрезался многоточием.
                .frame(width: 196)
            }

            HStack(spacing: 8) {
                Text("Причёсывать текст")
                    .font(.system(size: 12))
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { model.cleanup },
                    set: { Settings.shared.cleanup = $0; model.cleanup = $0 }
                ))
                .labelsHidden()
                .toggleStyle(GlassSwitchStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.rimGlass, lineWidth: 1)
        )
    }

    // MARK: Низ

    private var footer: some View {
        HStack(spacing: 8) {
            action("Настройки", symbol: "gearshape") {
                model.actions?.menuOpenSettings(Settings.shared.lastSettingsSection)
                dismiss()
            }
            action("Выйти", symbol: "power") {
                model.actions?.menuQuit()
            }
        }
    }

    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    // Символы разной высоты (стетоскоп выше шестерёнки)
                    // разгоняли кнопки по высоте — фиксируем зону иконки.
                    .frame(height: 14)
                Text(title)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            // Кнопки — на стекле: они отзываются на курсор и должны читаться
            // как поверхность, которую нажимают. Рецепт тот же, что у активной
            // вкладки: лёгкая подложка, прозрачное стекло и светлый вид —
            // плотная заливка глушила стекло и давала серую плиту.
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.26))
            )
            .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .environment(\.colorScheme, .light)
        }
        .buttonStyle(.plain)
    }
}
