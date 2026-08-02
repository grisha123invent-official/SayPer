import AppKit
import Combine
import SwiftUI

/// Панель раздела: подложка L2, баннер доступа и сам раздел.
///
/// Полосы вкладок здесь нет намеренно — она живёт в титлбаре
/// (`SettingsTabStrip` внутри `NSTitlebarAccessoryViewController`, см. `ia.md` §1),
/// а этот вид отвечает только за содержимое под ней.
struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            // Волосок между полосой разделов и контентом: без него подложка
            // панели в светлой теме сливается с материалом титлбара.
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)

            VStack(spacing: 0) {
                if !model.accessibilityGranted {
                    AccessBanner { KeyboardAccess.request(model) }
                        .frame(maxWidth: Palette.contentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Palette.spaceLg)
                        .padding(.top, Palette.spaceLg)
                        // 4 + 20 у панели = отбивка 24 до первой карточки.
                        .padding(.bottom, Palette.space2xs)
                }

                section
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Фон здесь не рисуется: орб живёт на уровне окна и тянется под
            // титлбар с полосой вкладок — иначе над панелью остаётся глухая
            // серая полоса, а стеклу капсулы нечего преломлять.
        }
        // Пока доступа нет, главное действие на экране — «Выдать доступ»,
        // поэтому акцентные кнопки внутри карточек гаснут (П6).
        .environment(\.accentActionsMuted, !model.accessibilityGranted)
        .onAppear { model.refreshPermissions() }
        // Доступ выдают в Системных настройках, то есть в другом приложении:
        // единственный надёжный момент перечитать состояние — возвращение сюда.
        // Иначе баннер висит и после выданного доступа, а акцентные кнопки
        // в карточках остаются погашенными до перезапуска окна.
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            model.refreshPermissions()
        }
    }

    @ViewBuilder
    private var section: some View {
        switch model.section {
        case .general:
            SettingsSectionGeneral(model: model)
        case .dictation:
            SettingsSectionDictation(model: model)
        case .history:
            SettingsSectionHistory()
        case .usage:
            SettingsSectionUsage()
        case .system:
            SettingsSectionSystem(model: model)
        }
    }
}

/// Запрос доступа к клавиатуре: одно действие на два вызова — баннер и карточка
/// в разделе «Ключ и доступ». Разводить их по разным реализациям нельзя: человек
/// нажмёт то, что ближе, и обязан получить один и тот же результат.
enum KeyboardAccess {
    private static let privacyPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    static func request(_ model: SettingsModel) {
        HotkeyMonitor.requestTrust()
        if let url = URL(string: privacyPane) {
            NSWorkspace.shared.open(url)
        }
        // Разрешение выдают в системном окне: к моменту возврата в приложение
        // состояние уже другое, и его надо перечитать.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            model.refreshPermissions()
        }
    }
}

/// Полоса разделов: стеклянная капсула с пятью сегментами (`components.md` §6).
///
/// Кладётся в титлбар аксессуаром, поэтому знает только про модель и ничего —
/// про окно. ⌘1…⌘5 вешает `SettingsWindowController`: аксессуар титлбара не
/// участвует в разборе `performKeyEquivalent` у `contentView`, и шорткаты SwiftUI
/// отсюда до окна не доходят.
struct SettingsTabStrip: View {
    @ObservedObject var model: SettingsModel
    @Namespace private var glassSpace

    /// Кадры сегментов в системе координат полосы. Нужны, чтобы активная
    /// капсула была ОДНОЙ вьюхой, которая ездит, а не появлялась заново
    /// в каждом сегменте: условная вставка даёт скачок, а не перетекание.
    @State private var frames: [SettingsSection: CGRect] = [:]

    private static let flow = Animation.spring(response: 0.5, dampingFraction: 0.72)

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { item in
                    Segment(item: item, isSelected: model.section == item) {
                        withAnimation(Self.flow) {
                            model.section = item
                        }
                        // Запоминается только то, куда человек перешёл сам. Открытия
                        // из меню (`show(.usage)`) и принудительный «Ключ и доступ»
                        // при невыданном доступе запомненный раздел не переписывают.
                        Settings.shared.lastSettingsSection = item
                    }
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TabFrames.self,
                                value: [item: proxy.frame(in: .named("tabStrip"))]
                            )
                        }
                    }
                }
            }
            .coordinateSpace(name: "tabStrip")
            .onPreferenceChange(TabFrames.self) { frames = $0 }
            .background(alignment: .leading) {
                if let frame = frames[model.section] {
                    ActiveCapsule(namespace: glassSpace)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX)
                        // Анимация висит на капсуле и покрывает все пути смены
                        // раздела: клик, ⌘1…⌘5, открытие из меню статус-бара.
                        .animation(Self.flow, value: model.section)
                }
            }
            .padding(2)
            .frame(height: Palette.tabCapsuleHeight)
            // Дорожка — настоящее стекло macOS 26: оно само преломляет материал
            // титлбара и рисует кромку.
            .glassEffect(.regular, in: Capsule(style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Разделы настроек")
    }

    /// Активная вкладка: стеклянная капсула с жидким градиентом внутри.
    /// `glassEffectID` внутри контейнера — родной механизм слияния стекла:
    /// по дороге капсула сплавляется с дорожкой, а не летит поверх неё.
    private struct ActiveCapsule: View {
        let namespace: Namespace.ID

        var body: some View {
            Capsule(style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.32),
                        Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.28),
                        Color(red: 0.93, green: 0.28, blue: 0.60).opacity(0.30)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                // interactive() — стекло отзывается бликом на курсор.
                .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
                .glassEffectID("activeTab", in: namespace)
        }
    }

    private struct TabFrames: PreferenceKey {
        static let defaultValue: [SettingsSection: CGRect] = [:]

        static func reduce(
            value: inout [SettingsSection: CGRect],
            nextValue: () -> [SettingsSection: CGRect]
        ) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    private struct Segment: View {
        let item: SettingsSection
        let isSelected: Bool
        let action: () -> Void

        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 15))
                        .symbolRenderingMode(.hierarchical)
                    Text(item.title)
                        .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, Palette.spaceSm)
                .frame(minWidth: 84, maxHeight: .infinity)
                // Заливку выбранного сегмента рисует перетекающая ActiveCapsule
                // уровнем выше; здесь остаётся только подсветка наведения.
                .background(
                    Capsule(style: .continuous)
                        .fill(isHovered && !isSelected ? Palette.surfaceRowHover : .clear)
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help(Text(verbatim: "\(item.title) (⌘\(item.shortcut))"))
            .animation(.easeOut(duration: Palette.durHover), value: isHovered)
            .onHover { isHovered = $0 }
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }

    }
}
