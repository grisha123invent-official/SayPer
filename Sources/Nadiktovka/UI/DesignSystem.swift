import AppKit
import SwiftUI

/// Токены и общие кирпичики окна настроек.
///
/// Сигнатуры заморожены: разделы вызывают их и не переопределяют.
/// Реализация здесь намеренно простая — оформление доводит слайс «Оформление»,
/// он же единственный, кто правит этот файл.
enum Palette {
    // Шаг сетки 4pt.
    static let space2xs: CGFloat = 4
    static let spaceXs: CGFloat = 8
    static let spaceSm: CGFloat = 12
    static let spaceMd: CGFloat = 16
    static let spaceLg: CGFloat = 20
    static let spaceXl: CGFloat = 24
    static let space2xl: CGFloat = 32

    // Вертикальный ритм. Базовая шкала выше рассчитана на плотные системные
    // панели, а здесь окно просторное и разделов немного — по высоте всё
    // выглядело набитым. Эти четыре значения дают воздух, не трогая ширину.
    /// Между карточками в панели раздела.
    static let spaceCardGap: CGFloat = 30
    /// Верхнее и нижнее поле внутри карточки.
    static let spaceCardVertical: CGFloat = 20
    /// Между строками внутри карточки.
    static let spaceCardRows: CGFloat = 16
    /// Отбивка вокруг разделителя-волоска.
    static let spaceDivider: CGFloat = 12

    static let radiusCard: CGFloat = 12
    /// Скругление единой панели раздела.
    static let radiusPanel: CGFloat = 16
    static let radiusTile: CGFloat = 10
    static let radiusField: CGFloat = 6
    static let radiusRow: CGFloat = 8

    /// Максимальная ширина колонки с карточками. Окно тянется по ширине,
    /// колонка растёт вместе с ним до этого предела и дальше стоит по центру:
    /// строки «подпись слева, контрол справа» на километровой ширине
    /// разъезжаются и перестают читаться как пара.
    static let contentWidth: CGFloat = 900

    /// Высота строки настройки: одна строка / строка с описанием под ней.
    static let rowHeight: CGFloat = 32
    static let rowHeightWithSubtitle: CGFloat = 50
    /// Высота строки списка истории.
    static let historyRowHeight: CGFloat = 36
    /// Высота кнопки-капсулы (`components.md` §7).
    static let capsuleHeight: CGFloat = 26

    /// Полоса разделов: высота аксессуара в титлбаре и высота самой капсулы
    /// (`components.md` §6 — 32 внутри 44, по 6 сверху и снизу).
    /// Полоса разделов заметно выше капсулы: при высоте впритык капсула
    /// прилипала к кнопкам окна и полоса читалась сплющенной.
    static let tabStripHeight: CGFloat = 58
    static let tabCapsuleHeight: CGFloat = 34
    /// Воздух между кнопками окна и капсулой.
    static let tabStripTopInset: CGFloat = 10

    /// Длительности движения (`tokens.md` §10).
    static let durHover: Double = 0.12

    // MARK: - Цвета

    /// Значение зависит от темы: `tokens.md` задаёт для светлой и тёмной разные числа,
    /// и `Color.primary.opacity(...)` их не воспроизводит — в тёмной теме подложка
    /// должна быть *светлее* фона, а в светлой *темнее* или наоборот, в зависимости
    /// от токена. `NSColor(name:dynamicProvider:)` пересчитывается сам при смене темы,
    /// поэтому вызывающим ничего знать не нужно.
    private static func themed(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: themedNS(light: light, dark: dark))
    }

    /// То же самое, но `NSColor`: поле записи хоткея рисуется на `CALayer`,
    /// а слою нужен `CGColor`, который из SwiftUI-цвета не достать.
    private static func themedNS(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static func white(_ alpha: CGFloat) -> NSColor { NSColor(white: 1, alpha: alpha) }
    private static func black(_ alpha: CGFloat) -> NSColor { NSColor(white: 0, alpha: alpha) }

    /// Карточка-секция поверх подложки панели.
    static var surfaceCard: Color { themed(light: white(0.70), dark: white(0.055)) }
    /// Единая панель раздела: заливка под стеклом делает его матовым,
    /// иначе фон-орб бьёт сквозь панель и мешает читать текст.
    static var surfacePanel: Color { themed(light: white(0.62), dark: black(0.34)) }
    /// Вложенная плитка статистики, поле словаря, обычная кнопка-капсула.
    static var surfaceTile: Color { themed(light: black(0.045), dark: white(0.075)) }
    /// Строка под курсором.
    static var surfaceRowHover: Color { Color(nsColor: surfaceRowHoverNS) }
    /// AppKit-двойник: наведение на поле записи хоткея (`components.md` §2).
    static var surfaceRowHoverNS: NSColor { themedNS(light: black(0.05), dark: white(0.07)) }
    /// Выбранная строка списка.
    static var surfaceRowSelected: Color { Color(nsColor: .selectedContentBackgroundColor) }
    /// Активный сегмент полосы разделов в титлбаре.
    static var surfaceTabActive: Color { themed(light: white(0.85), dark: white(0.14)) }
    /// Поля ввода — системная семантика, своих значений не заводим.
    static var surfaceField: Color { Color(nsColor: .textBackgroundColor) }

    /// Контур карточки-секции.
    static var rimCard: Color { themed(light: black(0.08), dark: white(0.10)) }
    /// Контур стеклянных поверхностей: HUD, капсула разделов.
    ///
    /// `tokens.md` §2 задаёт кромку парой: светлая обводка поверх и тёмная снизу.
    /// Без нижней половины капсула в светлой теме висит в воздухе — она светлее
    /// материала титлбара со всех четырёх сторон и не садится на него.
    static var rimGlass: Color { themed(light: white(0.55), dark: white(0.12)) }
    /// Нижняя кромка стеклянной поверхности: в мокапе это вторая тень
    /// капсулы (`0 .5px 1px`), а не вторая обводка.
    static var rimGlassBottom: Color { themed(light: black(0.08), dark: white(0.04)) }
    /// Разделитель строк внутри карточки.
    static var hairline: Color { Color(nsColor: .separatorColor) }

    /// Дорожка сегментированного контрола (значения из утверждённого мокапа).
    static var segmentTrack: Color {
        themed(light: NSColor(red: 0.47, green: 0.47, blue: 0.50, alpha: 0.13),
               dark: NSColor(red: 0.47, green: 0.47, blue: 0.50, alpha: 0.24))
    }
    /// Выбранный сегмент.
    static var segmentThumb: Color { themed(light: white(1.0), dark: white(0.20)) }
    /// Тень бегунка сегментов (`--seg-active-shadow` из мокапа): без неё белый
    /// бегунок на светлой дорожке остаётся без края и «растворяется» в ней.
    static var segmentThumbShadow: Color { themed(light: black(0.20), dark: black(0.35)) }

    /// Дорожка капсулы разделов: L1 из мокапа. Материал полосы даёт
    /// `NSVisualEffectView(.headerView)`, а капсула поверх него читается
    /// как отдельная поверхность только с этой подложкой.
    static var surfaceTabTrack: Color { themed(light: white(0.42), dark: white(0.06)) }

    /// Обводка полей ввода: у `.separatorColor` в светлой теме контраст к белому
    /// полю ниже порога, поле «растворяется» в карточке.
    static var fieldBorder: Color { Color(nsColor: fieldBorderNS) }
    /// AppKit-двойник обводки поля — для поля записи хоткея.
    static var fieldBorderNS: NSColor { themedNS(light: black(0.16), dark: white(0.14)) }

    /// Блик по верхней кромке — только у того, что парит (П4): HUD и капсула разделов.
    static let specular = LinearGradient(
        stops: [
            .init(color: Color.white.opacity(0.20), location: 0),
            .init(color: Color.white.opacity(0.04), location: 0.35),
            .init(color: Color.white.opacity(0), location: 1)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Предупреждение: баннер отсутствия доступа, ошибка автозапуска.
    static var warning: Color { Color(nsColor: .systemOrange) }
    static var success: Color { Color(nsColor: .systemGreen) }

    /// Подложка и обводка баннера. Прозрачность у оранжевого своя, не из
    /// `surfaceTile`: баннер обязан читаться поверх любой подложки.
    static var bannerFill: Color { Color(nsColor: .systemOrange).opacity(0.12) }
    static var bannerRim: Color { Color(nsColor: .systemOrange).opacity(0.30) }
}

/// Материал `NSVisualEffectView` как подложка SwiftUI-вида.
///
/// Нужен там, где SwiftUI-материалы не дают нужного слоя: `.regularMaterial`
/// не различает `.contentBackground` и `.headerView`, а именно на этой разнице
/// держится правило «один слой размытия на глубину» (`tokens.md` §1).
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State

    init(
        material: NSVisualEffectView.Material,
        blending: NSVisualEffectView.BlendingMode = .withinWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blending = blending
        self.state = state
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = state
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.state = state
    }
}

/// Оправа поля ввода: заливка, обводка и фокусное кольцо.
///
/// Поля в разделах собраны вручную из `TextField`/`SecureField`/`TextEditor`
/// с `.textFieldStyle(.plain)`, а он снимает вместе с системным бордюром и
/// системное фокусное кольцо — без него у полей нет состояния «фокус»
/// (`tokens.md` §11). Кольцо рисуется цветом `keyboardFocusIndicatorColor`
/// поверх обводки и **без анимации**: §10 прямо запрещает `transition` на фокусе.
///
/// Флаг приходит снаружи, потому что `@FocusState` живёт только в том виде,
/// где объявлено само поле.
struct FieldChrome: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.surfaceField)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.fieldBorder, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius + 1.5, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .keyboardFocusIndicatorColor),
                        lineWidth: 3
                    )
                    .padding(-2.5)
                    .opacity(isFocused ? 1 : 0)
            )
            // Кольцо не участвует в раскладке: иначе поле бы дёргалось на фокусе.
            .animation(nil, value: isFocused)
    }
}

extension View {
    /// Заливка `surfaceField`, обводка `fieldBorder` и фокусное кольцо.
    func fieldChrome(isFocused: Bool, cornerRadius: CGFloat = Palette.radiusField) -> some View {
        modifier(FieldChrome(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}

/// Каркас панели раздела: одна колонка карточек, прокрутка и поля от краёв окна.
struct SectionScaffold<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            // Секции идут одной матовой панелью: раздельные карточки с широкими
            // просветами разрывали раздел на куски, и фон лез между ними.
            // Границы секций внутри держат заголовки и волоски.
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Palette.radiusPanel, style: .continuous)
                    .fill(Palette.surfacePanel)
            )
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: Palette.radiusPanel, style: .continuous)
            )
            .frame(maxWidth: Palette.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Palette.spaceLg)
            .padding(.vertical, Palette.spaceXl)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Карточка-секция: заголовок внутри, первой строкой.
///
/// `separated: true` — карточка со строками, разделёнными волоском: собственные
/// отступы между строками отключаются, отбивку задаёт сам `CardDivider`
/// (по 8pt сверху и снизу), а разделители расставляет вызывающий — только там,
/// где они нужны по мокапу.
struct GlassCard<Content: View>: View {
    private let title: String
    private let accessory: AnyView?
    private let separated: Bool
    private let content: Content

    init(
        _ title: String,
        accessory: AnyView? = nil,
        separated: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory
        self.separated = separated
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: separated ? 0 : Palette.spaceCardRows) {
            HStack(spacing: Palette.spaceXs) {
                // 13/semibold обычным цветом — как записано в `tokens.md` §6.
                // Прежние 10pt tertiary uppercase были ТИШЕ основного текста:
                // группа не может читаться как группа, если её название бледнее
                // её содержимого. Отсюда и шло ощущение, что раздел слипается.
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: Palette.spaceXs)
                accessory
            }
            .frame(minHeight: 16)
            .padding(.bottom, Palette.space2xs)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Palette.spaceLg)
        .padding(.vertical, Palette.spaceCardVertical)
        // Границы секций держит воздух, а не линии: заголовок-метка сверху
        // уже отделяет группу, и волосок поверх него был третьим сигналом
        // об одной и той же границе.
    }
}

/// Строка настройки: подпись слева, контрол справа, описание под подписью.
struct SettingRow<Control: View>: View {
    private let title: String
    private let subtitle: String?
    private let control: Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        // Контрол выравнивается по центру своей строки, а описание уходит под
        // всю строку целиком: если положить его в одну колонку с подписью,
        // переключатель уезжает к середине блока и строки перестают держать
        // общую линию (`components.md` §1).
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: Palette.spaceSm) {
                Text(title)
                    .font(.body)
                Spacer(minLength: Palette.spaceSm)
                control
            }
            .frame(minHeight: Palette.rowHeight)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: subtitle == nil ? Palette.rowHeight : Palette.rowHeightWithSubtitle,
            alignment: .leading
        )
    }
}

/// Переключатель — всегда switch, никогда не чекбокс.
struct SwitchToggle: View {
    private let title: String
    private let subtitle: String?
    @Binding private var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        SettingRow(title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(GlassSwitchStyle())
        }
    }
}

/// Переключатель на настоящем стекле macOS 26: дорожка преломляет то, что под
/// ней, включённое состояние подкрашивается акцентом. Системный `.switch`
/// рисует плоскую заливку и рядом со стеклянным окном смотрится чужеродно.
struct GlassSwitchStyle: ToggleStyle {
    private let trackWidth: CGFloat = 43
    private let trackHeight: CGFloat = 20
    /// Линза крупнее дорожки и свешивается за её края — как в референсе,
    /// где стеклянный кругляш «сидит» поверх синей полосы, а не внутри неё.
    private var knobSize: CGFloat { trackHeight + 5 }

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Capsule()
                // Дорожка включённого — яркий акцент: он и есть цвет контрола,
                // а стеклянная линза сверху его преломляет.
                .fill(configuration.isOn
                      ? AnyShapeStyle(Palette.accent)
                      : AnyShapeStyle(Color.white.opacity(0.10)))
                .frame(width: trackWidth, height: trackHeight)
                // Кромка дорожки: без неё выключенный переключатель
                // растворяется в панели.
                .overlay(
                    Capsule().strokeBorder(Palette.rimGlass, lineWidth: 1)
                )
                .overlay(
                    // Линза: прозрачное стекло со светлой кромкой, сквозь
                    // которое видно дорожку. Глухой белый кружок закрывал
                    // цвет собой и стеклом не читался.
                    Circle()
                        .fill(.white.opacity(0.22))
                        .glassEffect(.clear.interactive(), in: Circle())
                        // Светлый вид: в тёмной теме стекло тонируется
                        // в тёмное, и линза выходила чёрным кругляшом
                        // вместо прозрачной.
                        .environment(\.colorScheme, .light)
                        .overlay(
                            Circle().strokeBorder(.white.opacity(0.75), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                        .frame(width: knobSize, height: knobSize),
                    alignment: configuration.isOn ? .trailing : .leading
                )
                .animation(.snappy(duration: 0.18), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
                .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
        }
    }
}

/// Подсказка под контролом. Допустима, только если объясняет невидимое последствие.
struct Hint: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Плитка статистики: крупное моноширинное число и подпись под ним.
struct StatTile: View {
    private let value: String
    private let caption: String
    private let isEmpty: Bool

    /// `isEmpty` — данных нет и в значении стоит прочерк: `components.md` §5
    /// требует красить его `tertiaryLabelColor`, иначе «—» по контрасту
    /// неотличим от настоящего числа. Раздел сам знает, пусто у него или нет,
    /// а по содержимому строки это угадывать нельзя.
    init(value: String, caption: String, isEmpty: Bool = false) {
        self.value = value
        self.caption = caption
        self.isEmpty = isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Palette.space2xs) {
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Palette.spaceSm)
        // Плитки — единственное место, где стекло уместно поверх карточки:
        // они крупные, стоят рядом и читаются как один блок.
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: Palette.radiusTile, style: .continuous)
        )
    }
}

/// Разделитель-волосок между строками карточки.
///
/// Инсет слева (`tokens.md` §2) — чтобы линия не резала карточку насквозь;
/// отбивка сверху и снизу по 8pt. В списках, где строки уже имеют собственные
/// поля, инсет складывается: строка истории отступает на 8, значит волосок —
/// `CardDivider(inset: 20, spacing: 0)`.
struct CardDivider: View {
    private let inset: CGFloat
    private let spacing: CGFloat

    init(inset: CGFloat = Palette.spaceSm, spacing: CGFloat = Palette.spaceDivider) {
        self.inset = inset
        self.spacing = spacing
    }

    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
            .padding(.vertical, spacing)
    }
}

/// Сегментированный контрол: выбор из двух-трёх равноправных вариантов.
///
/// Обобщён по значению, подписи берутся замыканием — так один и тот же контрол
/// обслуживает и режим активации («Удержание / Нажал-нажал»), и период
/// в «Расходах» («7 дней / 30 дней / Всё время»), не заставляя перечисления
/// подписываться под общий протокол.
///
/// ```swift
/// SegmentedControl(selection: $mode) { $0.title }                 // по CaseIterable
/// SegmentedControl(selection: $period, compact: true) { $0.title } // в шапке карточки
/// ```
struct SegmentedControl<Value: Hashable>: View {
    @Binding private var selection: Value
    private let options: [Value]
    private let compact: Bool
    private let title: (Value) -> String

    init(
        selection: Binding<Value>,
        options: [Value],
        compact: Bool = false,
        title: @escaping (Value) -> String
    ) {
        self._selection = selection
        self.options = options
        self.compact = compact
        self.title = title
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Segment(
                    title: title(option),
                    isSelected: option == selection,
                    compact: compact
                ) {
                    selection = option
                }
            }
        }
        .padding(2)
        .background(
            // Капсула, а не прямоугольник со слабым скруглением: рядом
            // переключатели и поле хоткея скруглены сильно, и угловатая
            // дорожка сегментов выпадала из общего языка форм.
            Capsule(style: .continuous)
                .fill(Palette.segmentTrack)
        )
    }

    private struct Segment: View {
        let title: String
        let isSelected: Bool
        let compact: Bool
        let action: () -> Void

        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(compact ? .subheadline : .body)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .padding(.horizontal, compact ? 9 : Palette.spaceSm)
                    .padding(.vertical, compact ? 3 : Palette.space2xs)
                    .background(
                        // Бегунок повторяет форму дорожки: капсула в капсуле.
                        Capsule(style: .continuous)
                            .fill(fill)
                            // Край бегунка: в мокапе `--seg-active-shadow`,
                            // тень только у выбранного сегмента.
                            .shadow(
                                color: isSelected ? Palette.segmentThumbShadow : .clear,
                                radius: 1,
                                y: 0.5
                            )
                    )
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: Palette.durHover), value: isSelected)
            .animation(.easeOut(duration: Palette.durHover), value: isHovered)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }

        private var fill: Color {
            if isSelected { return Palette.segmentThumb }
            return isHovered ? Palette.surfaceRowHover : .clear
        }
    }
}

extension SegmentedControl where Value: CaseIterable {
    /// Все варианты перечисления, в порядке объявления.
    init(selection: Binding<Value>, compact: Bool = false, title: @escaping (Value) -> String) {
        self.init(
            selection: selection,
            options: Array(Value.allCases),
            compact: compact,
            title: title
        )
    }
}

/// Пока в окне висит баннер «нет доступа к клавиатуре», главное действие на экране —
/// «Выдать доступ», поэтому акцентные кнопки внутри карточек теряют заливку:
/// контрастное пятно на экране ровно одно (П6). Раздел выставляет флаг один раз
/// на всю панель — `.environment(\.accentActionsMuted, !model.hasKeyboardAccess)`.
private struct AccentActionsMutedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var accentActionsMuted: Bool {
        get { self[AccentActionsMutedKey.self] }
        set { self[AccentActionsMutedKey.self] = newValue }
    }
}

/// Кнопка-капсула: единый вид для действий в карточках и в баннере доступа.
struct CapsuleButton: View {
    enum Kind {
        /// Обычная: заливка плитки, обводка карточки.
        case normal
        /// Основная, одна на экран (П6): акцентная заливка, текст выделения.
        case accent
    }

    private let title: String
    private let symbol: String?
    private let kind: Kind
    private let isLoading: Bool
    private let action: () -> Void

    /// Задержка показа и минимальное время жизни спиннера (`components.md` §7).
    private static let spinnerDelay: Double = 0.150
    private static let spinnerMinLifetime: Double = 0.300

    /// Видимость спиннера отделена от `isLoading`: проверка ключа при валидном
    /// ключе отвечает за десятки миллисекунд, и спиннер, привязанный к запросу
    /// напрямую, успевает только мигнуть.
    @State private var showsSpinner = false
    @State private var spinnerShownAt: Date?

    init(
        _ title: String,
        kind: Kind = .normal,
        symbol: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.symbol = symbol
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                }
                Text(title)
            }
        }
        .buttonStyle(CapsuleButtonStyle(kind: kind))
        // Пока идёт запрос, повторное нажатие не нужно; пока висит спиннер —
        // кнопка тоже не нажимается, иначе получится живая кнопка со спиннером.
        .disabled(isLoading || showsSpinner)
        .task(id: isLoading) { await syncSpinner() }
    }

    @MainActor
    private func syncSpinner() async {
        if isLoading {
            guard !showsSpinner else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.spinnerDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            spinnerShownAt = Date()
            showsSpinner = true
        } else {
            guard showsSpinner else { return }
            let shown = spinnerShownAt.map { Date().timeIntervalSince($0) } ?? Self.spinnerMinLifetime
            let rest = Self.spinnerMinLifetime - shown
            if rest > 0 {
                try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }
            showsSpinner = false
            spinnerShownAt = nil
        }
    }
}

/// Заливка, обводка и состояния кнопки-капсулы (`components.md` §7).
struct CapsuleButtonStyle: ButtonStyle {
    let kind: CapsuleButton.Kind

    init(kind: CapsuleButton.Kind = .normal) {
        self.kind = kind
    }

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, kind: kind)
    }

    /// Имя не `Body`: так называется associatedtype самого `ButtonStyle`.
    private struct Content: View {
        let configuration: ButtonStyleConfiguration
        let kind: CapsuleButton.Kind

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accentActionsMuted) private var accentMuted
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.body)
                // На акценте — семантика системного выделения, а не жёсткий белый:
                // при жёлтом системном акценте белый текст на нём нечитаем,
                // а `alternateSelectedControlTextColor` там становится тёмным.
                .foregroundStyle(isAccent
                                 ? Color(nsColor: .alternateSelectedControlTextColor)
                                 : Color.primary)
                .padding(.horizontal, 14)
                .frame(height: Palette.capsuleHeight)
                .background(background)
                .overlay(border)
                .clipShape(Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
                .opacity(isEnabled ? 1 : 0.5)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: Palette.durHover), value: isHovered)
        }

        /// Акцент гаснет, пока на экране висит баннер отсутствия доступа.
        private var isAccent: Bool { kind == .accent && !accentMuted }

        @ViewBuilder
        private var background: some View {
            ZStack {
                Capsule(style: .continuous).fill(isAccent ? Palette.accent : Palette.surfaceTile)
                // Наведение — на уровень плотнее, нажатие — ещё на уровень. Без сдвига.
                if isEnabled, isHovered || configuration.isPressed {
                    Capsule(style: .continuous)
                        .fill(scrim)
                        .opacity(configuration.isPressed ? 1 : 0.55)
                }
            }
        }

        private var scrim: Color {
            isAccent ? Color.black.opacity(0.14) : Palette.surfaceRowHover
        }

        @ViewBuilder
        private var border: some View {
            if !isAccent {
                Capsule(style: .continuous).strokeBorder(Palette.rimCard, lineWidth: 1)
            }
        }
    }
}

/// Баннер отсутствия доступа к клавиатуре.
///
/// Единственный элемент, который имеет право стоять выше карточек (`ia.md` §1.4):
/// без доступа хоткей не сработает и всё остальное в окне бессмысленно. Показывается
/// в любом разделе и живёт вне прокрутки — уехать из виду он не должен.
struct AccessBanner: View {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        HStack(spacing: Palette.spaceXs + 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.warning)
            Text("Нет доступа к клавиатуре — хоткей не сработает")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Palette.spaceSm)
            CapsuleButton("Выдать доступ", kind: .accent, action: action)
        }
        .padding(.horizontal, Palette.spaceSm)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Palette.radiusCard, style: .continuous)
                .fill(Palette.bannerFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Palette.radiusCard, style: .continuous)
                .strokeBorder(Palette.bannerRim, lineWidth: 1)
        )
        // Кнопка баннера — единственное акцентное пятно, пока доступа нет,
        // поэтому сам баннер из общего приглушения выведен.
        .environment(\.accentActionsMuted, false)
        .accessibilityElement(children: .contain)
    }
}

/// Строка списка истории (`components.md` §4).
///
/// Клик — скопировать, ⌥+клик — вставить снова, двойной клик — развернуть до трёх
/// строк. Всё то же продублировано контекстным меню: афордансы, живущие только
/// под курсором, запрещены.
struct HistoryRow: View {
    private let text: String
    private let time: String
    private let duration: String?
    private let isSelected: Bool
    private let onCopy: () -> Void
    private let onInsertAgain: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var didCopy = false

    /// Ширина зоны меты фиксирована, иначе при наведении текст «переливается».
    private let metaWidth: CGFloat = 56

    init(
        text: String,
        time: String,
        duration: String? = nil,
        isSelected: Bool = false,
        onCopy: @escaping () -> Void,
        onInsertAgain: @escaping () -> Void
    ) {
        self.text = text
        self.time = time
        self.duration = duration
        self.isSelected = isSelected
        self.onCopy = onCopy
        self.onInsertAgain = onInsertAgain
    }

    var body: some View {
        HStack(spacing: Palette.spaceSm) {
            Text(text)
                .font(.body)
                .lineLimit(isExpanded ? 3 : 1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let duration {
                Text(duration)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? selectedText : Color.secondary)
            }

            meta
                .frame(width: metaWidth, alignment: .trailing)
        }
        .foregroundStyle(isSelected ? selectedText : Color.primary)
        .padding(.horizontal, Palette.spaceXs)
        .frame(minHeight: Palette.historyRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Palette.radiusRow, style: .continuous)
                .fill(rowFill)
        )
        .contentShape(RoundedRectangle(cornerRadius: Palette.radiusRow, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: Palette.durHover), value: isHovered)
        // ⌥+клик перехватывается раньше обычного, иначе сработает копирование.
        .highPriorityGesture(TapGesture().modifiers(.option).onEnded { onInsertAgain() })
        .onTapGesture(count: 2) { isExpanded.toggle() }
        .onTapGesture { copy() }
        .contextMenu {
            Button("Скопировать") { copy() }
            Button("Вставить снова") { onInsertAgain() }
            Button(isExpanded ? "Свернуть" : "Показать целиком") { isExpanded.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text), \(time)")
    }

    @ViewBuilder
    private var meta: some View {
        if didCopy {
            // Молчаливый успех: галочка на 1,2 секунды вместо тоста.
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: .systemGreen))
        } else if isHovered {
            HStack(spacing: Palette.space2xs) {
                actionButton("doc.on.doc", help: "Скопировать", action: copy)
                actionButton("arrow.down.doc", help: "Вставить снова", action: onInsertAgain)
            }
        } else {
            Text(time)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(isSelected ? selectedText : Color.secondary)
        }
    }

    private func actionButton(
        _ symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? selectedText : Color.secondary)
        .help(help)
    }

    /// Текст на выбранной строке — системная семантика выделения: при светлом
    /// системном акценте он не белый, и захардкоженный белый там пропадает.
    private var selectedText: Color { Color(nsColor: .alternateSelectedControlTextColor) }

    private var rowFill: Color {
        if isSelected { return Palette.surfaceRowSelected }
        return isHovered ? Palette.surfaceRowHover : .clear
    }

    private func copy() {
        onCopy()
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopy = false
        }
    }
}

/// Заглушка раздела, который ещё не сделан.
///
/// Живёт здесь, а не в `SettingsRootView`: её показывают разделы «История»
/// и «Расходы», то есть файлы разных слайсов.
struct SectionPlaceholder: View {
    private let symbol: String

    init(symbol: String) {
        self.symbol = symbol
    }

    var body: some View {
        VStack(spacing: Palette.spaceSm) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("Раздел в работе")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Ряд, который переносит не поместившееся на следующую строку.
///
/// `HStack` в такой роли не годится: он сжимает содержимое до нечитаемого,
/// а `LazyVGrid` требует заранее известной ширины колонок — у кнопок с текстом
/// она у каждой своя.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var line: CGFloat = 0
        var height: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if line > 0, line + spacing + size.width > width {
                height += lineHeight + spacing
                line = 0
                lineHeight = 0
            }
            line += (line > 0 ? spacing : 0) + size.width
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: proposal.width ?? line, height: height + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
