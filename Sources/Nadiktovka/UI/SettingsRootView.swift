import AppKit
import Combine
import SwiftUI

/// Окно раздела целиком: полоса вкладок, баннер доступа и сам раздел.
///
/// Полоса вкладок лежит здесь, а не в `NSTitlebarAccessoryViewController`:
/// под аксессуаром система рисует разделительную линию, которая режет
/// сплошной фон окна надвое, и `titlebarSeparatorStyle` её не убирает.
struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabStrip(model: model)
                .frame(height: Palette.tabStripHeight)

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
        case .history:
            SettingsSectionHistory()
        case .customization:
            SettingsSectionCustomization()
        case .system:
            SettingsSectionSystem(model: model)
        case .about:
            SettingsSectionAbout(model: model)
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

    /// Без отскока: пружина с недостаточным затуханием читается как дёрганье.
    private static let flow = Animation.smooth(duration: 0.42, extraBounce: 0)

    var body: some View {
        // Плашка — отдельный НИЖНИЙ слой ZStack, а не `.background` у ряда:
        // стекло рисует себя выше содержимого подложки, и подписи вкладок
        // оказывались под матовым слоем.
        ZStack(alignment: .topLeading) {
            GlassEffectContainer(spacing: 14) {
                activeCapsule
            }
            segments
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Разделы настроек")
    }

    private var segments: some View {
        HStack(spacing: 2) {
            ForEach(SettingsSection.allCases) { item in
                Segment(item: item, isSelected: model.section == item) {
                    // Анимацию задаёт сама капсула. Оборачивать смену ещё и
                    // в withAnimation нельзя: две анимации на одно изменение
                    // дерутся между собой и дают рывок.
                    model.section = item
                    // Запоминается только то, куда человек перешёл сам. Открытия
                    // из меню (`show(.system)`) и принудительный «Ключ и расходы»
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
        .padding(2)
        .frame(height: Palette.tabCapsuleHeight)
        .padding(.top, Palette.tabStripTopInset)
    }

    @ViewBuilder
    private var activeCapsule: some View {
        if let frame = frames[model.section] {
            ActiveCapsule(namespace: glassSpace)
                .frame(width: frame.width, height: frame.height)
                // Капля: по дороге плашка вытягивается вдоль движения
                // и сплющивается поперёк, в конце упруго возвращается
                // в форму. Само перемещение — отдельной анимацией.
                .keyframeAnimator(
                    initialValue: Morph(),
                    trigger: model.section
                ) { view, morph in
                    view.scaleEffect(x: morph.stretch, y: morph.squash, anchor: .center)
                } keyframes: { _ in
                    KeyframeTrack(\.stretch) {
                        CubicKeyframe(1.16, duration: 0.20)
                        CubicKeyframe(0.97, duration: 0.14)
                        CubicKeyframe(1.0, duration: 0.12)
                    }
                    KeyframeTrack(\.squash) {
                        CubicKeyframe(0.84, duration: 0.20)
                        CubicKeyframe(1.04, duration: 0.14)
                        CubicKeyframe(1.0, duration: 0.12)
                    }
                }
                // Сдвиг учитывает поля ряда: плашка лежит в своём слое и
                // о padding'ах соседа сама не знает.
                .offset(x: frame.minX + 2, y: Palette.tabStripTopInset + 2)
                // Перемещение покрывает все пути смены раздела:
                // клик, ⌘1…⌘5, открытие из меню статус-бара.
                .animation(Self.flow, value: model.section)
        }
    }

    /// Активная вкладка: родное Liquid Glass в прозрачном варианте.
    ///
    /// `.clear` вместо `.regular` — стекло не тонируется под тему и остаётся
    /// прозрачным, с бликом и преломлением по краю. Светлый `colorScheme`
    /// заставляет систему рисовать его как светлое стекло: в тёмной теме
    /// `.regular` уходил в тёмное и плашка сливалась с фоном полосы.
    ///
    /// `NSVisualEffectView` тут не годится: он даёт ровную матовую заливку
    /// без бликов — на тёмном фоне это читается как серый прямоугольник.
    private struct ActiveCapsule: View {
        let namespace: Namespace.ID

        var body: some View {
            Capsule(style: .continuous)
                // Светлая подложка под стеклом: на тёмном фоне полосы одно
                // лишь прозрачное стекло остаётся тёмным, а плашка должна
                // читаться как светлая — так же, как в референсе Apple.
                .fill(.white.opacity(0.26))
                .glassEffect(.clear.interactive(), in: Capsule(style: .continuous))
                .environment(\.colorScheme, .light)
                .glassEffectID("activeTab", in: namespace)
        }
    }

    /// Деформация плашки на лету: вытянуться по ходу движения и сплющиться
    /// поперёк — это и читается как «капля», а не как едущий прямоугольник.
    private struct Morph: Equatable {
        var stretch: Double = 1
        var squash: Double = 1
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
                        // Вес постоянный. Раньше выбранная вкладка становилась
                        // medium — от этого менялась ширина сегмента, кадры
                        // разъезжались, и капсула дёргалась, догоняя их.
                        // Выделение несёт стекло и цвет подписи, не насыщенность.
                        .font(.system(size: 11, weight: .medium))
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
